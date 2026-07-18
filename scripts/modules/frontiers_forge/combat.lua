local Util = require("frontiers_forge.util")
local ffi = require("ffi")
local bit = require("bit")

-- Combat event capture via a code-cave hook on the server-message dispatcher.
-- Server opcode 0xDB is the only combat "number" message, but the client's
-- handling is purely visual and option-gated, so to build a damage meter we hook
-- the dispatcher case and copy every event into a ring buffer Lua polls. The
-- patch site is resolved from the VIWndGame overlay slide and verified against an
-- exact instruction signature (with a scan fallback) before any write, and
-- uninstalling restores the displaced instruction then zeroes the cave. When the
-- Sandstorm patch already hooks the site, we take the site ourselves and jump
-- into its cave from ours, so the raw packet fields are recorded before that
-- patch can rewrite them and both game versions are supported.

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
-- signature words with a jal into its own cave plus a nop. Its cave rewrites a
-- pet event's attacker to the local player (that is how it shows pet damage
-- numbers), so anything reading the event after it has run sees the pet's
-- damage as the player's. To see the raw fields we take the site jal ourselves,
-- record the event, then end our cave with a plain j into the foreign cave.
-- Both jals set ra to site+8, and the j leaves ra alone, so the foreign cave's
-- jr ra still returns to the dispatcher and its own logic runs unchanged.
-- Earlier versions of this hook instead chained onto the displaced lw a1 at the
-- end of the foreign cave, which is what read the rewritten fields; a leftover
-- chain patch from one of those sessions is restored before installing.
local FOREIGN_CAVE_SCAN_WORDS = 0x100

-- Fallback signature-scan window
local SCAN_START = 0x00300000
local SCAN_END   = 0x01800000

-- 0x000F5000 sits in the EE kernel-reserved gap below the ELF load address, so
-- EQOA never touches it. Verified all-zero before install to be safe. The
-- caves start at 0xF5000 rather than 0xF0000 because code below 0xF5000 carries
-- references into that range, and staying clear of them avoids the question of
-- whether those references are real.
local CAVE_CODE_OFFSET = 0x000F5000
local BUF_OFFSET       = 0x000F50A0
-- Buffer header: +0x0 total event counter (u32), +0x4 magic, +0x8/+0xC reserved because who knows what I'll need to add later.
-- Entries start at +0x10, stride 0x20:
--   +0x0 attacker_id (u32), +0x4 defender_id (u32),
--   +0x8 amount (int32, < 0 damage / > 0 heal), +0xC sequence number (u32),
--   +0x10 color (u32, the 0xDB trailer's tagged number color, 0 when absent),
--   +0x14..+0x1C reserved
local BUF_MAGIC   = 0x46464243 -- "CBFF" (combat buffer frontiersforge)
local RING_SIZE   = 64         -- must be a power of two
local RING_MASK   = RING_SIZE - 1
local ENTRY_SIZE  = 0x20
local ENTRIES_OFFSET = BUF_OFFSET + 0x10
local CAVE_REGION_END = ENTRIES_OFFSET + RING_SIZE * ENTRY_SIZE

-- Cave code. Clobbers t0-t9 and a1 (all dead at the patch site, the foreign
-- cave clobbers the same set). When chain_target is given the cave ends by
-- jumping into the foreign cave instead of returning, so its logic still runs
-- after the raw event is recorded.
--
-- Besides the three stack fields, the patched server appends an optional
-- 3-byte trailer to 0xDB: an RGB number color, read little-endian and tagged
-- with +0x1000000 (the same parse the Sandstorm cave does for its recoloring;
-- pet swings arrive credited to the owner and colored red, 0x10000FF). The
-- stream object sits on the dispatcher frame: buffer base at sp+0x4, read
-- cursor at sp+0x10, end at sp+0xC. The cursor is already past the parsed
-- fields at the patch site, so 3 or more remaining bytes means the trailer is
-- present.
local function BuildCaveCode(chain_target)
    local hi = bit.rshift(BUF_OFFSET, 16)
    local lo = bit.band(BUF_OFFSET, 0xFFFF)
    local code = {
        0x8FA508DC,                 -- lw    a1,0x8DC(sp)   displaced instruction (attacker)
        0x8FA908E0,                 -- lw    t1,0x8E0(sp)   amount (signed)
        0x8FAA08E4,                 -- lw    t2,0x8E4(sp)   defender
        0x8FAE000C,                 -- lw    t6,0xC(sp)     stream end
        0x8FAF0010,                 -- lw    t7,0x10(sp)    stream cursor
        0x01CF7023,                 -- subu  t6,t6,t7       bytes left in the packet
        0x29CE0003,                 -- slti  t6,t6,3
        0x8FB80004,                 -- lw    t8,0x4(sp)     stream buffer base
        0x030FC021,                 -- addu  t8,t8,t7
        0x15C0000A,                 -- bnez  t6,+10         no trailer, keep the zero
        0x0000C825,                 -- _or   t9,zero,zero   source id defaults to 0
        0x93190000,                 -- lbu   t9,0x0(t8)     trailer byte 0
        0x930C0001,                 -- lbu   t4,0x1(t8)     trailer byte 1
        0x930D0002,                 -- lbu   t5,0x2(t8)     trailer byte 2
        0x000C6200,                 -- sll   t4,t4,0x8
        0x000D6C00,                 -- sll   t5,t5,0x10
        0x032CC821,                 -- addu  t9,t9,t4
        0x032DC821,                 -- addu  t9,t9,t5
        0x3C0C0100,                 -- lui   t4,0x100
        0x032CC821,                 -- addu  t9,t9,t4       tag as an entity id
        bit.bor(0x3C080000, hi),    -- lui   t0,hi(buffer)  build the address of the buffer
        bit.bor(0x35080000, lo),    -- ori   t0,t0,lo(buffer)
        0x8D0B0000,                 -- lw    t3,0x0(t0)     total event counter
        bit.bor(0x316C0000, RING_MASK), -- andi t4,t3,RING_MASK  get the slot we need to use via the total event counter, using the ring mask to make sure we stay within the ring buffer.
        0x000C6940,                 -- sll   t5,t4,0x5      slot * ENTRY_SIZE
        0x01A86821,                 -- addu  t5,t5,t0       get the address of the entry we want to write in the ring buffer.
        0xADA50010,                 -- sw    a1,0x10(t5)    entry.attacker
        0xADAA0014,                 -- sw    t2,0x14(t5)    entry.defender
        0xADA90018,                 -- sw    t1,0x18(t5)    entry.amount
        0xADAB001C,                 -- sw    t3,0x1C(t5)    entry.seq
        0xADB90020,                 -- sw    t9,0x20(t5)    entry.source
        0x256B0001,                 -- addiu t3,t3,0x1      add one to the total event counter
        0xAD0B0000,                 -- sw    t3,0x0(t0)     now update total event counter in the header
    }
    if chain_target ~= nil then
        code[#code + 1] = bit.bor(0x08000000, bit.rshift(chain_target, 2)) -- j foreign cave
    else
        code[#code + 1] = 0x03E00008 -- jr ra
    end
    code[#code + 1] = 0x00000000 -- _nop
    return code
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

-- A leftover chain patch from an older version of this hook, which patched the
-- displaced lw a1 at the end of the foreign cave with our j. Returns its
-- address, or nil when the foreign cave is clean.
local function FindLegacyChainPatch(target)
    for i = 0, FOREIGN_CAVE_SCAN_WORDS - 1 do
        if Util.ReadFromOffset(target + i * 4, "uint32_t") == J_CAVE
            and Util.ReadFromOffset(target + (i + 1) * 4, "uint32_t") == SITE_SIGNATURE[2] then
            return target + i * 4
        end
    end
    return nil
end

-- The foreign cave our installed cave chains into, recovered from the j at the
-- cave's tail. Nil when the cave ends with a plain jr ra (no foreign hook).
local function FindCaveChainTarget()
    local words = (BUF_OFFSET - CAVE_CODE_OFFSET) / 4
    for i = 0, words - 1 do
        local word = Util.ReadFromOffset(CAVE_CODE_OFFSET + i * 4, "uint32_t")
        if bit.band(word, 0xFC000000) == 0x08000000 then
            return JalTarget(word)
        end
    end
    return nil
end

-- Classifies the four words at a candidate site. Returns a table describing the
-- install, or nil when the site does not look like the 0xDB dispatcher case:
--   site    the dispatcher word to patch with our jal
--   restore what the site word goes back to on uninstall (the original load,
--           or the foreign hook's jal when one owns the site)
--   chain   foreign cave to jump into from our cave's tail, or nil
--   already true when the site already holds our jal
--   legacy  address of an old-style chain patch to clean up first, or nil
local function ClassifySite(site)
    local w1 = Util.ReadFromOffset(site, "uint32_t")
    local w3 = Util.ReadFromOffset(site + 8, "uint32_t")
    local w4 = Util.ReadFromOffset(site + 12, "uint32_t")
    if w3 ~= SITE_SIGNATURE[3] or w4 ~= SITE_SIGNATURE[4] then
        return nil
    end

    if w1 == JAL_CAVE then
        -- Already ours. What the site must go back to lives in our cave's
        -- tail: a j there means a foreign hook owned the site before us.
        local chain = FindCaveChainTarget()
        local restore = ORIGINAL_OPCODE
        if chain ~= nil then
            restore = bit.bor(0x0C000000, bit.rshift(chain, 2))
        end
        return { site = site, restore = restore, chain = chain, already = true }
    end

    local w2 = Util.ReadFromOffset(site + 4, "uint32_t")
    if w1 == ORIGINAL_OPCODE and w2 == SITE_SIGNATURE[2] then
        return { site = site, restore = ORIGINAL_OPCODE, already = false }
    end

    -- A foreign hook (the Sandstorm patch) owns the site. Take the site and
    -- chain into its cave, cleaning up any patch an older session left inside.
    if IsJal(w1) and w2 == 0 then
        local target = JalTarget(w1)
        if target > 0 and target < 0x02000000 - FOREIGN_CAVE_SCAN_WORDS * 4 then
            return {
                site = site, restore = w1, chain = target, already = false,
                legacy = FindLegacyChainPatch(target),
            }
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
            local info = ClassifySite(SCAN_START + i * 4)
            if info ~= nil then
                return info
            end
        end
    end
    return nil
end

-- Resolves the dispatcher site and how to install there (see ClassifySite),
-- or nil plus a reason.
local function ResolvePatchSite()
    local draw_ptr_offset = Util.GetOffsetFromPointerChain(WND_GAME_STATIC_PTR, WND_GAME_DRAW_STEPS)
    if draw_ptr_offset == nil then
        return nil, "game UI not loaded (are you in game?)"
    end
    local draw_runtime = Util.ReadFromOffset(draw_ptr_offset, "uint32_t")
    if draw_runtime == 0 or draw_runtime >= 0x02000000 then
        return nil, "bad draw-function pointer"
    end

    local slide = draw_runtime - WND_GAME_DRAW_STATIC
    local site = PATCH_SITE_STATIC + slide

    if site > 0 and site < 0x02000000 - 0x10 then
        local info = ClassifySite(site)
        if info ~= nil then
            return info
        end
    end

    -- Slide assumption failed so scan for the signature instead.
    local info = ScanForSite()
    if info ~= nil then
        return info
    end
    return nil, "0xDB dispatcher signature not found"
end

local hook_state = {
    installed = false,
    patch_site = nil,
    restore_word = nil, -- what the site goes back to on uninstall
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

    local info, err = ResolvePatchSite()
    if info == nil then
        return false, "combat hook: " .. err
    end

    -- The cave region must contain all zeros or our own magic (leftover from a previous session,
    -- e.g. script reloaded without uninstalling). Anything else means the region is in use and we
    -- probably shouldn't touch it.
    local magic = Util.ReadFromOffset(BUF_OFFSET + 4, "uint32_t")
    if magic ~= BUF_MAGIC then
        for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
            if Util.ReadFromOffset(offset, "uint32_t") ~= 0 then
                return false, "combat hook: cave region at 0xF5000 is not free"
            end
        end
    end

    -- An old-style chain patch inside the foreign cave has to go back to the
    -- displaced load before the site is taken, since together they would form
    -- a loop between the two caves.
    if info.legacy ~= nil then
        Util.WriteToOffset(info.legacy, "uint32_t", ORIGINAL_OPCODE)
    end

    -- Write the cave and buffer header first, then patch the dispatcher, so
    -- the branch target is always valid code by the time anything can jump
    -- to it.
    local code = BuildCaveCode(info.chain)
    for i, word in ipairs(code) do
        Util.WriteToOffset(CAVE_CODE_OFFSET + (i - 1) * 4, "uint32_t", word)
    end
    Util.WriteToOffset(BUF_OFFSET, "uint32_t", 0)          -- event counter
    Util.WriteToOffset(BUF_OFFSET + 4, "uint32_t", BUF_MAGIC)
    Util.WriteToOffset(BUF_OFFSET + 8, "uint32_t", RING_SIZE)
    Util.WriteToOffset(BUF_OFFSET + 12, "uint32_t", 0)

    if not info.already then
        Util.WriteToOffset(info.site, "uint32_t", JAL_CAVE)
    end

    hook_state.installed = true
    hook_state.patch_site = info.site
    hook_state.restore_word = info.restore
    hook_state.last_seq = 0
    hook_state.dropped = 0
    return true
end

--- Puts the dispatcher site back (to the original load, or to the foreign
--- hook's jal when one owned it) and zeroes the cave region. Safe to call even
--- if the hook is not installed.
--- @return boolean success True on success (including when there is nothing to clean up).
function Combat.UninstallHook()
    local site = hook_state.patch_site
    local restore = hook_state.restore_word
    if site == nil then
        -- Maybe a previous session left the hook in place, so find it just in case.
        local info = ResolvePatchSite()
        if info == nil then
            return true -- nothing to clean up
        end
        if not info.already then
            -- The site is not ours, but an old session may still have left its
            -- chain patch inside the foreign cave.
            if info.legacy ~= nil then
                Util.WriteToOffset(info.legacy, "uint32_t", ORIGINAL_OPCODE)
                for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
                    Util.WriteToOffset(offset, "uint32_t", 0)
                end
            end
            return true
        end
        site = info.site
        restore = info.restore
    end

    -- Only restore if the site actually holds our patch.
    if Util.ReadFromOffset(site, "uint32_t") == JAL_CAVE then
        Util.WriteToOffset(site, "uint32_t", restore or ORIGINAL_OPCODE)
    end

    -- With the patch gone nothing can reach the cave, so now we can overwrite it with zeros.
    for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end

    hook_state.installed = false
    hook_state.patch_site = nil
    hook_state.restore_word = nil
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

local function GetPetId()
    -- Pet entity id at singleton+0x2BE50, -1 when no pet is up.
    local offset = Util.GetOffsetFromPointerChain(0x4E37F0, { 0x2BE4C })
    if offset == nil then
        return nil
    end
    local id = Util.ReadFromOffset(offset, "uint32_t")
    if id == 0xFFFFFFFF or id == 0 then
        return nil
    end
    return id
end

--- @return integer|nil pet_id Entity id of the local player's pet, or nil when no pet is up.
function Combat.GetPetEntityId()
    return GetPetId()
end

--- A snapshot of everything the hook resolved, for diagnosing capture problems
--- in game. Fields: installed, patch_site, site_word (what the site holds right
--- now), restore_word, chain_target (foreign cave we jump into, nil when the
--- site was vanilla), player_id, pet_id, event_count, dropped.
--- @return table info
function Combat.GetHookInfo()
    local info = {
        installed = hook_state.installed,
        patch_site = hook_state.patch_site,
        restore_word = hook_state.restore_word,
        player_id = GetLocalPlayerId(),
        pet_id = GetPetId(),
        event_count = Combat.GetEventCount(),
        dropped = hook_state.dropped,
    }
    if hook_state.patch_site ~= nil then
        info.site_word = Util.ReadFromOffset(hook_state.patch_site, "uint32_t")
    end
    if hook_state.installed then
        info.chain_target = FindCaveChainTarget()
    end
    return info
end

--- The foreign (Sandstorm) cave's code, when one owns the 0xDB site. Words are
--- read from the chain target up to its jr ra, so the patch's actual logic can
--- be copied out of a live game for offline disassembly.
--- @param max_words integer|nil Cap on words returned, default 64.
--- @return table[]|nil rows Array of { addr = ea, word = u32 }, nil when not chained.
function Combat.ReadForeignCave(max_words)
    local target = hook_state.installed and FindCaveChainTarget() or nil
    if target == nil then
        return nil
    end
    max_words = max_words or 64
    local rows = {}
    for i = 0, max_words - 1 do
        local addr = target + i * 4
        local word = Util.ReadFromOffset(addr, "uint32_t")
        rows[#rows + 1] = { addr = addr, word = word }
        if word == 0x03E00008 then -- jr ra, plus its delay slot
            local slot = target + (i + 1) * 4
            rows[#rows + 1] = { addr = slot, word = Util.ReadFromOffset(slot, "uint32_t") }
            break
        end
    end
    return rows
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

-- Drains the ring buffer, returning events captured since the previous call.
-- Destructive, so only Combat.Update may call it. Anything else draining the
-- ring would starve every subscriber of the events it took. Event fields:
--   attacker_id  entity id of whoever dealt the damage / cast the heal
--   defender_id  entity id of whoever received it
--   amount       signed, negative = damage, positive = healing
--   seq          monotonically increasing event number
--   color        the patched 0xDB trailer, a per-hit number color as
--                0x1000000 | B<<16 | G<<8 | R (pet swings observed as
--                0x10000FF, pure red), nil when the packet had none
--   outgoing     true if the local player or their pet dealt it
--   incoming     true if defender is the local player
--   from_pet     informational only, true when the event looks like the pet's
--                doing. Not reliable enough to split pet output from the
--                player's, so nothing classifies on it
--   to_pet       true if defender is the local player's pet
--   is_heal      true if amount > 0
local function PollEventsInternal()
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
    local pet_id = GetPetId()
    for seq = first, count - 1 do
        local entry = ENTRIES_OFFSET + bit.band(seq, RING_MASK) * ENTRY_SIZE
        -- The seq stamp detects an entry overwritten between our count read
        -- and now... which should only possible under extreme event rates.
        if Util.ReadFromOffset(entry + 0xC, "uint32_t") == seq then
            local amount = Util.ReadFromOffset(entry + 0x8, "int32_t")
            local attacker = Util.ReadFromOffset(entry, "uint32_t")
            local defender = Util.ReadFromOffset(entry + 0x4, "uint32_t")
            local color = Util.ReadFromOffset(entry + 0x10, "uint32_t")
            if color == 0 then
                color = nil
            end
            -- A pet's own id shows up as the attacker on its heals, but its
            -- swings are credited to the owner, so the two cannot be told apart
            -- reliably. A pet acts only on the player's behalf, so both count as
            -- the player's own output and nothing branches on from_pet.
            local from_pet = pet_id ~= nil
                and (attacker == pet_id or (attacker == player_id and color ~= nil))
            events[#events + 1] = {
                attacker_id = attacker,
                defender_id = defender,
                color = color,
                amount = amount,
                seq = seq,
                outgoing = (attacker == player_id) or (pet_id ~= nil and attacker == pet_id),
                incoming = (defender == player_id),
                from_pet = from_pet,
                to_pet = (pet_id ~= nil and defender == pet_id),
                is_heal = amount > 0,
            }
        else
            hook_state.dropped = hook_state.dropped + 1
        end
    end

    hook_state.last_seq = count
    return events
end

--------------------------------------------------------------------------------
-- Hook ownership
--------------------------------------------------------------------------------

-- The hook is shared, so it is refcounted by owner. A mod releasing its own
-- claim must not tear the patch out from under everyone else still listening.
local hook_owners = {}
local hook_owner_count = 0

--- Claims the combat hook, installing it on the first claim. Every caller must
--- pair this with Release, normally from its DisableScript callback.
--- @param owner string Stable name identifying the caller, e.g. "wereoxxs_ui".
--- @return boolean success True if the hook is up (or already was).
--- @return string|nil error Present only when success is false.
function Combat.Acquire(owner)
    if hook_owners[owner] then
        return true
    end
    local ok, err = Combat.InstallHook()
    if not ok then
        return false, err
    end
    hook_owners[owner] = true
    hook_owner_count = hook_owner_count + 1
    return true
end

--- Drops one owner's claim, uninstalling the hook once the last owner is gone.
--- @param owner string The same name passed to Acquire.
function Combat.Release(owner)
    if not hook_owners[owner] then
        return
    end
    hook_owners[owner] = nil
    hook_owner_count = hook_owner_count - 1
    if hook_owner_count <= 0 then
        hook_owner_count = 0
        Combat.UninstallHook()
    end
end

--- @return integer count How many owners currently hold the hook.
function Combat.GetOwnerCount()
    return hook_owner_count
end

--- Whether one specific owner holds a claim. The hook being installed says
--- nothing about whether this caller is one of the owners keeping it up.
--- @param owner string The name passed to Acquire.
--- @return boolean held
function Combat.HasClaim(owner)
    return hook_owners[owner] == true
end

--------------------------------------------------------------------------------
-- Event bus
--------------------------------------------------------------------------------

-- The hook is a single patch site but the events it carries are not all the
-- same thing, so one poller classifies each event and fans it out to whoever
-- asked for that kind. Only these names are ever emitted.
-- These report what the hook captured and nothing more. Higher level notions
-- like "a fight is running" are deliberately absent, since where a fight starts
-- and ends is a judgement call (how long a lull ends it, whether healing counts)
-- that belongs to whoever is consuming the events, not to the module reporting
-- them.
Combat.Events = {
    OnDamageDealt     = "OnDamageDealt",     -- player or pet dealt damage
    OnDamageReceived  = "OnDamageReceived",  -- player took damage
    OnHealingDealt    = "OnHealingDealt",
    OnHealingReceived = "OnHealingReceived",
}

local subscribers = {}      -- event name -> owner -> handler
local subscriber_errors = {}

--- Subscribes to one combat event. Subscribing the same owner and event again
--- replaces the previous handler, so a hot reload cannot stack duplicates.
--- @param owner string Stable name identifying the caller.
--- @param event_name string One of Combat.Events.
--- @param fn function Receives the event table (see the field list above).
function Combat.On(owner, event_name, fn)
    if Combat.Events[event_name] == nil then
        return false, "unknown combat event: " .. tostring(event_name)
    end
    subscribers[event_name] = subscribers[event_name] or {}
    subscribers[event_name][owner] = fn
    return true
end

--- Unsubscribes an owner. Drops every subscription it holds when event_name is nil.
function Combat.Off(owner, event_name)
    if event_name ~= nil then
        if subscribers[event_name] ~= nil then
            subscribers[event_name][owner] = nil
        end
        return
    end
    for _, handlers in pairs(subscribers) do
        handlers[owner] = nil
    end
end

-- A handler that errors is dropped rather than left to fail every frame. The
-- error is kept so the mod that broke can be identified instead of silently
-- going quiet.
local function Emit(event_name, payload)
    local handlers = subscribers[event_name]
    if handlers == nil then
        return
    end
    for owner, fn in pairs(handlers) do
        local ok, err = pcall(fn, payload)
        if not ok then
            handlers[owner] = nil
            subscriber_errors[#subscriber_errors + 1] = {
                owner = owner, event = event_name, error = tostring(err),
            }
            while #subscriber_errors > 16 do
                table.remove(subscriber_errors, 1)
            end
        end
    end
end

--- Errors raised by subscriber handlers, oldest first. Each row is
--- { owner, event, error }. The handler was dropped when its error was recorded.
--- @return table[] errors
function Combat.GetSubscriberErrors()
    return subscriber_errors
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

-- Classifies one polled event and fires the public events it belongs to. A
-- self-heal has the player as both parties, so it fires dealt and received.
local function DispatchEvent(event)
    if event.is_heal then
        if event.outgoing then Emit(Combat.Events.OnHealingDealt, event) end
        if event.incoming then Emit(Combat.Events.OnHealingReceived, event) end
    else
        if event.outgoing then Emit(Combat.Events.OnDamageDealt, event) end
        if event.incoming then Emit(Combat.Events.OnDamageReceived, event) end
    end
end

--- Drains the ring once and dispatches to subscribers. Safe to call from every
--- subscriber's frame, since a second call in the same frame finds the ring
--- already empty.
function Combat.Update()
    if not hook_state.installed then
        return
    end
    for _, event in ipairs(PollEventsInternal()) do
        DispatchEvent(event)
    end
end

return Combat
