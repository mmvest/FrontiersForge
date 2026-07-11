local Util = require("frontiers_forge.util")
local ffi = require("ffi")
local bit = require("bit")

-- Combat event capture via a code-cave hook on the server-message dispatcher.
-- Server opcode 0xDB is the only combat "number" message, but the client's
-- handling is purely visual and option-gated, so to build a damage meter we hook
-- the dispatcher case and copy every event into a ring buffer Lua polls. The
-- patch site is resolved from the VIWndGame overlay slide and verified against an
-- exact instruction signature (with a scan fallback) before any write, and
-- uninstalling restores the original instruction then zeroes the cave. When the
-- Sandstorm patch already hooks the site, we chain onto the displaced
-- instruction inside its cave instead, so both game versions are supported.

local Combat = {}

local WND_GAME_STATIC_PTR = 0x14E200
local WND_GAME_DRAW_STEPS = { 0x190, 0x53C, 0x20, 0x1C }
local WND_GAME_DRAW_STATIC = 0x006AD8D8 -- VIWndGame_DrawHUD in the dump

local PATCH_SITE_STATIC = 0x0062FB24    -- dispatcher 0xDB case, in the dump

-- The four instructions starting at the patch site. All four encodings are
-- position-independent, so they are identical no matter where the overlay loaded.
local SITE_SIGNATURE = {
    0x8FA508DC, -- lw a1,0x8DC(sp)   (attacker id normally, but this is the instruction we patch)
    0x8E8271F8, -- lw v0,0x71F8(s4)  (local player entity id)
    0x14A20007, -- bne a1,v0,+7
    0x8FA608E0, -- _lw a2,0x8E0(sp)  (amount)
}
local ORIGINAL_OPCODE = SITE_SIGNATURE[1]

-- The Sandstorm patch hooks this same dispatcher case, replacing the first two
-- signature words with a jal into its own cave plus a nop. Its cave re-executes
-- both displaced loads right before its jr ra, so when we find a foreign jal at
-- the site we follow it and patch the displaced lw a1 inside that cave instead.
-- A plain j is used there rather than jal so the cave's ra stays intact, and the
-- lw v0 that follows runs in our jump's delay slot.
local FOREIGN_CAVE_SCAN_WORDS = 0x100

-- Fallback signature-scan window
local SCAN_START = 0x00300000
local SCAN_END   = 0x01800000

-- 0x000F0000 sits in the EE kernel-reserved gap below the ELF load address, so
-- EQOA never touches it. Verified all-zero before install to be safe.
local CAVE_CODE_OFFSET = 0x000F0000
local BUF_OFFSET       = 0x000F0080
-- Buffer header: +0x0 total event counter (u32), +0x4 magic, +0x8/+0xC reserved because who knows what I'll need to add later.
-- Entries start at +0x10, stride 0x10:
--   +0x0 attacker_id (u32), +0x4 defender_id (u32),
--   +0x8 amount (int32, < 0 damage / > 0 heal), +0xC sequence number (u32)
local BUF_MAGIC   = 0x46464243 -- "CBFF" (combat buffer frontiersforge)
local RING_SIZE   = 64         -- must be a power of two
local RING_MASK   = RING_SIZE - 1
local ENTRY_SIZE  = 0x10
local ENTRIES_OFFSET = BUF_OFFSET + 0x10
local CAVE_REGION_END = ENTRIES_OFFSET + RING_SIZE * ENTRY_SIZE

-- Cave code. Clobbers t0-t5 and a1.
local function BuildCaveCode()
    local hi = bit.rshift(BUF_OFFSET, 16)
    local lo = bit.band(BUF_OFFSET, 0xFFFF)
    return {
        0x8FA508DC,                 -- lw    a1,0x8DC(sp)   displaced instruction (attacker)
        0x8FA908E0,                 -- lw    t1,0x8E0(sp)   amount (signed)
        0x8FAA08E4,                 -- lw    t2,0x8E4(sp)   defender
        bit.bor(0x3C080000, hi),    -- lui   t0,hi(buffer)  build the address of the buffer
        bit.bor(0x35080000, lo),    -- ori   t0,t0,lo(buffer)
        0x8D0B0000,                 -- lw    t3,0x0(t0)     total event counter
        bit.bor(0x316C0000, RING_MASK), -- andi t4,t3,RING_MASK  get the slot we need to use via the total event counter, using the ring mask to make sure we stay within the ring buffer.
        0x000C6900,                 -- sll   t5,t4,0x4      slot * ENTRY_SIZE (remember shifting left multiplies 2^n where n is the bits shifted left)
        0x01A86821,                 -- addu  t5,t5,t0       get the address of the entry we want to write in the ring buffer.
        0xADA50010,                 -- sw    a1,0x10(t5)    entry.attacker
        0xADAA0014,                 -- sw    t2,0x14(t5)    entry.defender
        0xADA90018,                 -- sw    t1,0x18(t5)    entry.amount
        0xADAB001C,                 -- sw    t3,0x1C(t5)    entry.seq
        0x256B0001,                 -- addiu t3,t3,0x1      add one to the total event counter
        0xAD0B0000,                 -- sw    t3,0x0(t0)     now update total event counter in the header
        0x03E00008,                 -- jr    ra
        0x00000000,                 -- _nop
    }
end

local JAL_CAVE = bit.bor(0x0C000000, bit.rshift(CAVE_CODE_OFFSET, 2))
local J_CAVE   = bit.bor(0x08000000, bit.rshift(CAVE_CODE_OFFSET, 2))

local function IsJal(word)
    return bit.band(word, 0xFC000000) == 0x0C000000
end

local function JalTarget(word)
    -- The dispatcher and every cave sit below 0x10000000, so the pc-region bits are zero.
    return bit.lshift(bit.band(word, 0x03FFFFFF), 2)
end

-- Follows a foreign jal at the site into its cave and finds the displaced
-- lw a1 there (or our own j if a previous session already chained onto it).
-- Returns the offset to patch and whether it is already ours.
local function ResolveChainSite(jal_word)
    local target = JalTarget(jal_word)
    if target <= 0 or target >= 0x02000000 - FOREIGN_CAVE_SCAN_WORDS * 4 then
        return nil
    end
    for i = 0, FOREIGN_CAVE_SCAN_WORDS - 1 do
        local word = Util.ReadFromOffset(target + i * 4, "uint32_t")
        if Util.ReadFromOffset(target + (i + 1) * 4, "uint32_t") == SITE_SIGNATURE[2] then
            if word == ORIGINAL_OPCODE then
                return target + i * 4, false
            end
            if word == J_CAVE then
                return target + i * 4, true
            end
        end
    end
    return nil
end

-- Classifies the four words at a candidate site. Returns the offset to patch,
-- the opcode to patch it with, and whether it is already patched, or nil when
-- the site does not look like the 0xDB dispatcher case at all.
local function ClassifySite(site)
    local w1 = Util.ReadFromOffset(site, "uint32_t")
    local w3 = Util.ReadFromOffset(site + 8, "uint32_t")
    local w4 = Util.ReadFromOffset(site + 12, "uint32_t")
    if w3 ~= SITE_SIGNATURE[3] or w4 ~= SITE_SIGNATURE[4] then
        return nil
    end

    if w1 == JAL_CAVE then
        return site, JAL_CAVE, true
    end
    local w2 = Util.ReadFromOffset(site + 4, "uint32_t")
    if w1 == ORIGINAL_OPCODE and w2 == SITE_SIGNATURE[2] then
        return site, JAL_CAVE, false
    end

    -- A foreign hook (the Sandstorm patch) owns the site, so chain onto the
    -- displaced instruction inside its cave.
    if IsJal(w1) and w2 == 0 then
        local chain, already = ResolveChainSite(w1)
        if chain ~= nil then
            return chain, J_CAVE, already
        end
    end
    return nil
end

local function ScanForSite()
    local mem = ffi.cast("uint32_t*", Util.EEmem() + SCAN_START)
    local words = (SCAN_END - SCAN_START) / 4
    local s3, s4 = SITE_SIGNATURE[3], SITE_SIGNATURE[4]
    for i = 0, words - 4 do
        if mem[i + 2] == s3 and mem[i + 3] == s4 then
            local site, opcode, already = ClassifySite(SCAN_START + i * 4)
            if site ~= nil then
                return site, opcode, already
            end
        end
    end
    return nil
end

-- Returns the offset to patch (the dispatcher site itself, or the displaced
-- instruction inside a foreign hook's cave), the opcode to write there, and
-- whether it already holds our patch, or nil plus a reason.
local function ResolvePatchSite()
    local draw_ptr_offset = Util.GetOffsetFromPointerChain(WND_GAME_STATIC_PTR, WND_GAME_DRAW_STEPS)
    if draw_ptr_offset == nil then
        return nil, nil, nil, "game UI not loaded (are you in game?)"
    end
    local draw_runtime = Util.ReadFromOffset(draw_ptr_offset, "uint32_t")
    if draw_runtime == 0 or draw_runtime >= 0x02000000 then
        return nil, nil, nil, "bad draw-function pointer"
    end

    local slide = draw_runtime - WND_GAME_DRAW_STATIC
    local site = PATCH_SITE_STATIC + slide

    if site > 0 and site < 0x02000000 - 0x10 then
        local resolved, opcode, already = ClassifySite(site)
        if resolved ~= nil then
            return resolved, opcode, already, nil
        end
    end

    -- Slide assumption failed so scan for the signature instead.
    local resolved, opcode, already = ScanForSite()
    if resolved ~= nil then
        return resolved, opcode, already, nil
    end
    return nil, nil, nil, "0xDB dispatcher signature not found"
end

local hook_state = {
    installed = false,
    patch_site = nil,
    patch_opcode = nil, -- jal at the dispatcher site, or j inside a foreign cave
    last_seq = 0,       -- next sequence number we have not yet returned
    dropped = 0,        -- events lost to ring overruns across all polls
}

--- @return boolean installed True if the combat event hook is currently installed.
function Combat.IsHookInstalled()
    return hook_state.installed
end

--- Installs the hook. Never writes to game memory unless every patch
--- site resolved and signature-matched and the cave region is free.
--- @return boolean success True if the hook is installed (or already was).
--- @return string|nil error Present only when success is false; human-readable reason.
function Combat.InstallHook()
    if hook_state.installed then
        return true
    end

    local site, opcode, already_patched, err = ResolvePatchSite()
    if site == nil then
        return false, "combat hook: " .. err
    end

    -- The cave region must contain all zeros or our own magic (leftover from a previous session,
    -- e.g. script reloaded without uninstalling). Anything else means the region is in use and we
    -- probably shouldn't touch it.
    local magic = Util.ReadFromOffset(BUF_OFFSET + 4, "uint32_t")
    if magic ~= BUF_MAGIC then
        for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
            if Util.ReadFromOffset(offset, "uint32_t") ~= 0 then
                return false, "combat hook: cave region at 0xF0000 is not free"
            end
        end
    end

    -- Write the cave and buffer header first, then patch the dispatcher, so
    -- the branch target is always valid code by the time anything can jump
    -- to it.
    local code = BuildCaveCode()
    for i, word in ipairs(code) do
        Util.WriteToOffset(CAVE_CODE_OFFSET + (i - 1) * 4, "uint32_t", word)
    end
    Util.WriteToOffset(BUF_OFFSET, "uint32_t", 0)          -- event counter
    Util.WriteToOffset(BUF_OFFSET + 4, "uint32_t", BUF_MAGIC)
    Util.WriteToOffset(BUF_OFFSET + 8, "uint32_t", RING_SIZE)
    Util.WriteToOffset(BUF_OFFSET + 12, "uint32_t", 0)

    if not already_patched then
        Util.WriteToOffset(site, "uint32_t", opcode)
    end

    hook_state.installed = true
    hook_state.patch_site = site
    hook_state.patch_opcode = opcode
    hook_state.last_seq = 0
    hook_state.dropped = 0
    return true
end

--- Restores the original dispatcher instruction and zeroes the cave region.
--- Safe to call even if the hook is not installed.
--- @return boolean success True on success (including when there is nothing to clean up).
function Combat.UninstallHook()
    local site = hook_state.patch_site
    local opcode = hook_state.patch_opcode
    if site == nil then
        -- Maybe a previous session left the hook in place, so find it just in case.
        local resolved, found_opcode, already_patched = ResolvePatchSite()
        if resolved == nil or not already_patched then
            return true -- nothing to clean up
        end
        site = resolved
        opcode = found_opcode
    end

    -- Only restore if the site actually holds our patch. Both the dispatcher
    -- site and the foreign cave's displaced slot originally hold the same word.
    if Util.ReadFromOffset(site, "uint32_t") == opcode then
        Util.WriteToOffset(site, "uint32_t", ORIGINAL_OPCODE)
    end

    -- With the patch gone nothing can reach the cave, so now we can overwrite it with zeros.
    for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end

    hook_state.installed = false
    hook_state.patch_site = nil
    hook_state.patch_opcode = nil
    hook_state.last_seq = 0
    return true
end

local function GetLocalPlayerId()
    -- [0x4E37F0] = client singleton + 4; player entity id at singleton+0x71F8.
    local offset = Util.GetOffsetFromPointerChain(0x4E37F0, { 0x71F4 })
    if offset == nil then
        return nil
    end
    return Util.ReadFromOffset(offset, "uint32_t")
end

--- @return integer count Total number of combat events captured since the hook was installed.
function Combat.GetEventCount()
    if not hook_state.installed then
        return 0
    end
    return Util.ReadFromOffset(BUF_OFFSET, "uint32_t")
end

--- @return integer dropped Number of events lost to ring-buffer overruns.
function Combat.GetDroppedCount()
    return hook_state.dropped
end

--- Returns events captured since the previous poll. Each event table has fields:
---   attacker_id  entity id of whoever dealt the damage / cast the heal
---   defender_id  entity id of whoever received it
---   amount       signed: negative = damage, positive = healing
---   seq          monotonically increasing event number
---   outgoing     true if attacker is the local player
---   incoming     true if defender is the local player
---   is_heal      true if amount > 0
--- @return table[] events Array of event tables, oldest first. Empty if none or hook not installed.
function Combat.PollEvents()
    local events = {}
    if not hook_state.installed then
        return events
    end

    local count = Util.ReadFromOffset(BUF_OFFSET, "uint32_t")
    if count == hook_state.last_seq then
        return events
    end

    -- If more than RING_SIZE events arrived since the last poll, the oldest
    -- ones were overwritten.
    local first = hook_state.last_seq
    if count - first > RING_SIZE then
        hook_state.dropped = hook_state.dropped + (count - first - RING_SIZE)
        first = count - RING_SIZE
    end

    local player_id = GetLocalPlayerId()
    for seq = first, count - 1 do
        local entry = ENTRIES_OFFSET + bit.band(seq, RING_MASK) * ENTRY_SIZE
        -- The seq stamp detects an entry overwritten between our count read
        -- and now... which should only possible under extreme event rates.
        if Util.ReadFromOffset(entry + 0xC, "uint32_t") == seq then
            local amount = Util.ReadFromOffset(entry + 0x8, "int32_t")
            local attacker = Util.ReadFromOffset(entry, "uint32_t")
            local defender = Util.ReadFromOffset(entry + 0x4, "uint32_t")
            events[#events + 1] = {
                attacker_id = attacker,
                defender_id = defender,
                amount = amount,
                seq = seq,
                outgoing = (attacker == player_id),
                incoming = (defender == player_id),
                is_heal = amount > 0,
            }
        else
            hook_state.dropped = hook_state.dropped + 1
        end
    end

    hook_state.last_seq = count
    return events
end

return Combat
