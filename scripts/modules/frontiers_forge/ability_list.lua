local Util = require("frontiers_forge.util")
local Ability = require("frontiers_forge.ability")
local ffi = require("ffi")
local bit = require("bit")

-- The ability list is owned by the client-state singleton, resolved through the
-- static pointer at 0x4E37F0 which points at singleton + 4 (so each chain step is
-- offset - 4). The records double as binary-search-tree nodes linked by index,
-- with index 0 a null sentinel, so real abilities occupy indices 1 .. count-1.
local AbilityList = {}

local GUI_CONTEXT_PTR_OFFSET = 0x4E37F0

-- Base address of the record array, or nil if the ability list isn't loaded.
local function GetBaseOffset()
    return Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB30}, "uint32_t", nil)
end

--- Number of real abilities (excluding the 0 sentinel).
--- @return integer count Ability count, or 0 when the list is not loaded (e.g. not in game).
function AbilityList.GetCount()
    local count = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB28}, "uint32_t", 0)
    if count == 0 then
        return 0
    end
    return count - 1
end

--- Get the ability record at a raw array index. Index 0 is the sentinel. Real
--- abilities live at indices 1 .. GetCount(). This raw index is the same one
--- the game stores in hotbar slots (see ability_bar.lua).
--- @param index integer Raw index into the record array, valid from 1 to GetCount().
--- @return table|nil ability Ability object, or nil when the index is out of range or the list is not loaded.
function AbilityList.GetAbilityByIndex(index)
    if index < 1 or index > AbilityList.GetCount() then
        return nil
    end
    local base = GetBaseOffset()
    if base == nil or not Util.IsValidEEPointer(base) then
        return nil
    end
    local record_offset = base + (index * Ability.size)
    if record_offset + Ability.size > Util.EE_RAM_SIZE then
        return nil
    end
    return Ability.new(Util.EEmem() + record_offset)
end

-- Tree traversal. Both helpers treat an unresolvable node (list unloaded, or
-- a link index outside the valid range) as end-of-traversal (0) rather than
-- crashing on a nil node.
local function LeftmostFrom(index)
    while true do
        local node = AbilityList.GetAbilityByIndex(index)
        if node == nil then
            return 0
        end
        local left = node.ptr.left_index
        if left == 0 then
            return index
        end
        index = left
    end
end

local function NextIndex(index)
    local node = AbilityList.GetAbilityByIndex(index)
    if node == nil then
        return 0
    end
    local right = node.ptr.right_index
    if right ~= 0 then
        return LeftmostFrom(right)
    end

    -- No right subtree so climb until we come up from a left child
    local parent = node.ptr.parent_index
    while parent ~= 0 do
        local parent_node = AbilityList.GetAbilityByIndex(parent)
        if parent_node == nil then
            return 0
        end
        if parent_node.ptr.left_index == index then
            return parent
        end
        index = parent
        parent = parent_node.ptr.parent_index
    end
    return 0
end

--- Iterator over all abilities in id-sorted (in-order tree) order.
--- Usage looks like `for index, ability in AbilityList.Abilities() do ... end`.
--- @return function iterator Iterator producing raw index and Ability object pairs.
function AbilityList.Abilities()
    local next_idx = 0
    if AbilityList.GetCount() > 0 then
        local root = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB34}, "uint32_t", 0)
        if root ~= 0 then
            next_idx = LeftmostFrom(root)
        end
    end

    return function()
        if next_idx == 0 then
            return nil
        end
        local idx = next_idx
        next_idx = NextIndex(idx)
        local ability = AbilityList.GetAbilityByIndex(idx)
        -- If the record became unreachable mid-iteration (e.g. list unloaded),
        -- end the loop instead of yielding a nil ability.
        if ability == nil then
            return nil
        end
        return idx, ability
    end
end

--- Find an ability by its id.
--- @param id integer The ability id to search for.
--- @return table|nil ability Matching Ability object, or nil if not found.
function AbilityList.GetAbilityById(id)
    for _, ability in AbilityList.Abilities() do
        if ability:GetId() == id then
            return ability
        end
    end
    return nil
end

--- Find an ability by its spellbook display index. This is the key the server
--- addresses abilities by, so it is what cooldown events arrive under.
--- @param display_index integer Spellbook position, 0-based.
--- @return table|nil ability Matching Ability object, or nil if not found.
function AbilityList.GetAbilityByDisplayIndex(display_index)
    for _, ability in AbilityList.Abilities() do
        if ability:GetDisplayIndex() == display_index then
            return ability
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Cooldown lockout capture
--------------------------------------------------------------------------------

-- Server opcode 0xCD is the cooldown message. Its handler scans the ability
-- list for the record whose display index matches, then stores the new lockout
-- to that record's +0x24, unconditionally, so the same message carries both the
-- start of a cooldown and its clear. It is the only thing that writes that
-- field for an ability the list already holds.
--
-- The hook sits on the dispatcher's call into that handler rather than on the
-- store itself, because the store lives in a branch delay slot and cannot be
-- patched. At the call the two values are already in registers, a1 holding the
-- display index and a2 the new lockout, so the cave reads no memory at all.
--
-- Opcode 0xB3 (a full record push) was the earlier guess and is wrong for this
-- purpose. Its handler only inserts abilities the list does not already have,
-- so it never fires for a cooldown on a known ability.

local UPDATE_CALL_SITE = 0x0062EF2C -- the jal into the 0xCD handler, in the dump

-- The three instructions bracketing the call site. All are position independent
-- so they hold no matter where the overlay loaded. The call itself is not in
-- the list, since a jal encodes an absolute target and so moves with the slide.
local SITE_SIGNATURE = {
    [-2] = 0x93A50855, -- lbu  a1,0x855(sp)   display index, the message's key
    [-1] = 0x0280202D, -- move a0,s4          client context
    [1]  = 0x8FA6088C, -- _lw  a2,0x88c(sp)   delay slot, the new lockout in ms
}

local SCAN_START = 0x00300000
local SCAN_END   = 0x01800000

-- 0x000F8000 continues the cave block that combat (0xF5000), input (0xF6000)
-- and chat (0xF7000) occupy. Verified all-zero before install.
local CAVE_CODE_OFFSET = 0x000F8000
local BUF_OFFSET       = 0x000F8080
-- Buffer header: +0x0 total update counter (u32), +0x4 magic, +0x8 ring size,
-- +0xC reserved. Entries start at +0x10, stride 0x10:
--   +0x0 display index (u32), +0x4 new lockout ms (u32), +0x8 sequence number (u32)
local BUF_MAGIC   = 0x4646424C -- "LBFF" (lockout buffer frontiersforge)
local RING_SIZE   = 64         -- must be a power of two
local RING_MASK   = RING_SIZE - 1
local ENTRY_SIZE  = 0x10
local ENTRIES_OFFSET = BUF_OFFSET + 0x10
local CAVE_REGION_END = ENTRIES_OFFSET + RING_SIZE * ENTRY_SIZE

-- Cave code. Clobbers t0 and t3-t5 only, which are caller-saved and so dead
-- across the call we are standing in for. a0/a1/a2 must survive untouched
-- because they are the handler's arguments, and ra must survive because the
-- handler's own jr ra is what returns to the dispatcher.
--
-- Nothing is displaced. Patching the jal leaves its delay slot in place, so the
-- lockout load into a2 still runs before we are entered, and ra already points
-- at the instruction after it. The cave therefore ends with a plain j into the
-- real handler rather than a return, and the handler returns for us.
local function BuildCaveCode(update_call_target)
    local hi = bit.rshift(BUF_OFFSET, 16)
    local lo = bit.band(BUF_OFFSET, 0xFFFF)
    return {
        bit.bor(0x3C080000, hi),        -- lui   t0,hi(buffer)
        bit.bor(0x35080000, lo),        -- ori   t0,t0,lo(buffer)
        0x8D0B0000,                     -- lw    t3,0x0(t0)     total update counter
        bit.bor(0x316C0000, RING_MASK), -- andi  t4,t3,RING_MASK   slot within the ring
        0x000C6900,                     -- sll   t5,t4,0x4      slot * ENTRY_SIZE
        0x01A86821,                     -- addu  t5,t5,t0       address of the entry
        0xADA50010,                     -- sw    a1,0x10(t5)    entry.display_index
        0xADA60014,                     -- sw    a2,0x14(t5)    entry.lockout
        0xADAB0018,                     -- sw    t3,0x18(t5)    entry.seq
        0x256B0001,                     -- addiu t3,t3,0x1
        0xAD0B0000,                     -- sw    t3,0x0(t0)     publish the new count
        bit.bor(0x08000000, bit.rshift(update_call_target, 2)), -- j the real handler
        0x00000000,                     -- _nop
    }
end

local JAL_CAVE = bit.bor(0x0C000000, bit.rshift(CAVE_CODE_OFFSET, 2))

local function IsJal(word)
    return bit.band(word, 0xFC000000) == 0x0C000000
end

local function JumpTarget(word)
    -- Everything involved sits below 0x10000000, so the pc-region bits are zero.
    return bit.lshift(bit.band(word, 0x03FFFFFF), 2)
end

-- The real updater our installed cave jumps to, recovered from the j at the
-- cave's tail. This is how the original call target survives a script reload.
local function FindCaveJumpTarget()
    local words = (BUF_OFFSET - CAVE_CODE_OFFSET) / 4
    for i = 0, words - 1 do
        local word = Util.ReadFromOffset(CAVE_CODE_OFFSET + i * 4, "uint32_t")
        if bit.band(word, 0xFC000000) == 0x08000000 then
            return JumpTarget(word)
        end
    end
    return nil
end

-- Classifies a candidate call site. Returns a table describing the install, or
-- nil when the surrounding instructions do not match:
--   site    the call word to patch with our jal
--   target  the real updater to jump to from the cave tail, also what the site
--           is restored to on uninstall
--   already true when the site already holds our jal
local function ClassifySite(site)
    for delta, want in pairs(SITE_SIGNATURE) do
        if Util.ReadFromOffset(site + delta * 4, "uint32_t") ~= want then
            return nil
        end
    end

    local word = Util.ReadFromOffset(site, "uint32_t")
    if not IsJal(word) then
        return nil
    end

    if word == JAL_CAVE then
        -- Already ours, so the original target is only recoverable from the
        -- cave tail. Without it we cannot restore the site, so refuse.
        local target = FindCaveJumpTarget()
        if target == nil then
            return nil
        end
        return { site = site, target = target, already = true }
    end

    -- A vanilla call. Reading the target here rather than sliding the dump
    -- address means the overlay slide is handled for free.
    return { site = site, target = JumpTarget(word), already = false }
end

local function ScanForSite()
    local mem = ffi.cast("uint32_t*", Util.EEmem() + SCAN_START)
    local words = (SCAN_END - SCAN_START) / 4
    for i = 2, words - 2 do
        if mem[i - 2] == SITE_SIGNATURE[-2] and mem[i - 1] == SITE_SIGNATURE[-1]
            and mem[i + 1] == SITE_SIGNATURE[1] then
            local info = ClassifySite(SCAN_START + i * 4)
            if info ~= nil then
                return info
            end
        end
    end
    return nil
end

-- Resolves the call site and how to install there, or nil plus a reason. The
-- overlay slide is taken from the ability list base pointer, which the 0xB3
-- path itself uses, so a resolvable list means a resolvable site.
local function ResolvePatchSite()
    local info = ClassifySite(UPDATE_CALL_SITE)
    if info ~= nil then
        return info
    end
    info = ScanForSite()
    if info ~= nil then
        return info
    end
    return nil, "0xCD cooldown handler call not found"
end

-- Defined with the dispatch code below, but the installer needs it.
local SeedLockoutCache

local hook_state = {
    installed = false,
    patch_site = nil,
    restore_word = nil,
    last_seq = 0,
    dropped = 0,
}

--- @return boolean installed True if the lockout hook is currently installed.
function AbilityList.IsHookInstalled()
    return hook_state.installed
end

--- Installs the hook. Never writes to game memory unless the call site resolved
--- and signature-matched and the cave region is free.
--- @return boolean success True if the hook is installed (or already was).
--- @return string|nil error Present only when success is false.
function AbilityList.InstallHook()
    if hook_state.installed then
        return true
    end

    local info, err = ResolvePatchSite()
    if info == nil then
        return false, "ability lockout hook: " .. err
    end

    -- The region must be all zeros or carry our own magic, the latter meaning a
    -- previous session left it behind. Anything else is somebody else's memory.
    local magic = Util.ReadFromOffset(BUF_OFFSET + 4, "uint32_t")
    if magic ~= BUF_MAGIC then
        for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
            if Util.ReadFromOffset(offset, "uint32_t") ~= 0 then
                return false, "ability lockout hook: cave region at 0xF8000 is not free"
            end
        end
    end

    -- Cave and header first, so the branch target is valid code before anything
    -- can reach it.
    local code = BuildCaveCode(info.target)
    for i, word in ipairs(code) do
        Util.WriteToOffset(CAVE_CODE_OFFSET + (i - 1) * 4, "uint32_t", word)
    end
    Util.WriteToOffset(BUF_OFFSET, "uint32_t", 0)
    Util.WriteToOffset(BUF_OFFSET + 4, "uint32_t", BUF_MAGIC)
    Util.WriteToOffset(BUF_OFFSET + 8, "uint32_t", RING_SIZE)
    Util.WriteToOffset(BUF_OFFSET + 12, "uint32_t", 0)

    if not info.already then
        Util.WriteToOffset(info.site, "uint32_t", JAL_CAVE)
    end

    hook_state.installed = true
    hook_state.patch_site = info.site
    hook_state.restore_word = bit.bor(0x0C000000, bit.rshift(info.target, 2))
    hook_state.last_seq = Util.ReadFromOffset(BUF_OFFSET, "uint32_t")
    hook_state.dropped = 0
    -- Best effort only. Seeding walks live records, and a throw here would
    -- leave the site patched with the hook never marked installed, which
    -- UninstallHook could then not find from state.
    pcall(SeedLockoutCache)
    return true
end

--- Puts the original call back and zeroes the cave region. Safe to call even if
--- the hook is not installed.
--- @return boolean success True on success (including when there is nothing to clean up).
function AbilityList.UninstallHook()
    local site = hook_state.patch_site
    local restore = hook_state.restore_word
    if site == nil then
        -- A previous session may have left the hook in place.
        local info = ResolvePatchSite()
        if info == nil or not info.already then
            return true
        end
        site = info.site
        restore = bit.bor(0x0C000000, bit.rshift(info.target, 2))
    end

    if Util.ReadFromOffset(site, "uint32_t") == JAL_CAVE and restore ~= nil then
        Util.WriteToOffset(site, "uint32_t", restore)
    end

    -- Nothing can reach the cave now, so it is safe to clear.
    for offset = CAVE_CODE_OFFSET, CAVE_REGION_END - 4, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end

    hook_state.installed = false
    hook_state.patch_site = nil
    hook_state.restore_word = nil
    hook_state.last_seq = 0
    return true
end

--- A snapshot of what the hook resolved, for diagnosing capture problems in
--- game. Fields: installed, patch_site, site_word, restore_word, update_target,
--- update_count, dropped.
--- @return table info
function AbilityList.GetHookInfo()
    local info = {
        installed = hook_state.installed,
        patch_site = hook_state.patch_site,
        restore_word = hook_state.restore_word,
        update_count = hook_state.installed
            and Util.ReadFromOffset(BUF_OFFSET, "uint32_t") or 0,
        dropped = hook_state.dropped,
    }
    if hook_state.patch_site ~= nil then
        info.site_word = Util.ReadFromOffset(hook_state.patch_site, "uint32_t")
    end
    if hook_state.installed then
        info.update_target = FindCaveJumpTarget()
    end
    return info
end

--- @return integer dropped Number of record updates lost to ring-buffer overruns.
function AbilityList.GetDroppedCount()
    return hook_state.dropped
end

-- Drains the ring, returning the cooldown messages captured since the previous
-- call. Destructive, so only AbilityList.Update may call it.
local function PollUpdatesInternal()
    local updates = {}
    if not hook_state.installed then
        return updates
    end

    local count = Util.ReadFromOffset(BUF_OFFSET, "uint32_t")
    if count == hook_state.last_seq then
        return updates
    end

    local first = hook_state.last_seq
    if count - first > RING_SIZE then
        hook_state.dropped = hook_state.dropped + (count - first - RING_SIZE)
        first = count - RING_SIZE
    end

    for seq = first, count - 1 do
        local entry = ENTRIES_OFFSET + bit.band(seq, RING_MASK) * ENTRY_SIZE
        -- The seq stamp catches an entry overwritten between the count read and now.
        if Util.ReadFromOffset(entry + 0x8, "uint32_t") == seq then
            updates[#updates + 1] = {
                display_index = Util.ReadFromOffset(entry, "uint32_t"),
                lockout_ms = Util.ReadFromOffset(entry + 0x4, "uint32_t"),
                seq = seq,
            }
        else
            hook_state.dropped = hook_state.dropped + 1
        end
    end

    hook_state.last_seq = count
    return updates
end

--------------------------------------------------------------------------------
-- Hook ownership
--------------------------------------------------------------------------------

-- Shared hook, refcounted by owner, so one mod dropping its claim cannot tear
-- the patch out from under everyone else still listening.
local hook_owners = {}
local hook_owner_count = 0

--- Claims the lockout hook, installing it on the first claim. Every caller must
--- pair this with Release, normally from its DisableScript callback.
--- @param owner string Stable name identifying the caller, e.g. "wereoxxs_ui".
--- @return boolean success True if the hook is up (or already was).
--- @return string|nil error Present only when success is false.
function AbilityList.Acquire(owner)
    if hook_owners[owner] then
        return true
    end
    local ok, err = AbilityList.InstallHook()
    if not ok then
        return false, err
    end
    hook_owners[owner] = true
    hook_owner_count = hook_owner_count + 1
    return true
end

--- Drops one owner's claim, uninstalling the hook once the last owner is gone.
--- @param owner string The same name passed to Acquire.
function AbilityList.Release(owner)
    if not hook_owners[owner] then
        return
    end
    hook_owners[owner] = nil
    hook_owner_count = hook_owner_count - 1
    if hook_owner_count <= 0 then
        hook_owner_count = 0
        AbilityList.UninstallHook()
    end
end

--- @return integer count How many owners currently hold the hook.
function AbilityList.GetOwnerCount()
    return hook_owner_count
end

--- Whether one specific owner holds a claim. The hook being installed says
--- nothing about whether this caller is one of the owners keeping it up.
--- @param owner string The name passed to Acquire.
--- @return boolean held
function AbilityList.HasClaim(owner)
    return hook_owners[owner] == true
end

--------------------------------------------------------------------------------
-- Event bus
--------------------------------------------------------------------------------

-- Only the two lockout edges are reported. Remaining time is deliberately
-- absent, since lockout_ms is a constant duration rather than a countdown and
-- turning it into a live timer means picking a clock and a tick rate, which is
-- the consuming mod's call to make.
--
-- Payloads carry the display index the server addressed, not an Ability object,
-- for the same reason. Resolving one is a list walk that most handlers do not
-- need, and GetAbilityByDisplayIndex is there for the ones that do.
AbilityList.Events = {
    OnLockoutStart = "OnLockoutStart", -- ability went on cooldown
    OnLockoutEnd   = "OnLockoutEnd",   -- ability came off cooldown
}

local subscribers = {}
local subscriber_errors = {}

--- Subscribes to one lockout event. Subscribing the same owner and event again
--- replaces the previous handler, so a hot reload cannot stack duplicates.
--- @param owner string Stable name identifying the caller.
--- @param event_name string One of AbilityList.Events.
--- @param fn function Receives { display_index, lockout_ms, seq }.
function AbilityList.On(owner, event_name, fn)
    if AbilityList.Events[event_name] == nil then
        return false, "unknown ability event: " .. tostring(event_name)
    end
    subscribers[event_name] = subscribers[event_name] or {}
    subscribers[event_name][owner] = fn
    return true
end

--- Unsubscribes an owner. Drops every subscription it holds when event_name is nil.
function AbilityList.Off(owner, event_name)
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

-- A handler that errors is dropped rather than left to fail on every update.
-- The error is kept so the mod that broke can be identified.
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
function AbilityList.GetSubscriberErrors()
    return subscriber_errors
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

-- 0xCD carries an absolute lockout value, not an edge, and the server repeats
-- the current value in cases that are not transitions. Only a change in whether
-- the value is zero is an edge worth reporting, so the last seen value per
-- display index is kept to compare against.
local lockout_cache = {}

-- Seeded from the live records at install, so a mod that loads mid-cooldown
-- still gets the OnLockoutEnd when that cooldown finishes. Without this the
-- first message for an ability would look like a first sighting and be
-- swallowed. Reads +0x24 directly, which the 0xCD handler is the only writer of.
SeedLockoutCache = function()
    lockout_cache = {}
    for _, ability in AbilityList.Abilities() do
        lockout_cache[ability:GetDisplayIndex()] = ability:GetCooldownLockoutMs()
    end
end

-- A display index still unseen after seeding is recorded silently. That happens
-- when the list was not loaded at install, and its first message tells us the
-- current state rather than a transition.
local function DispatchUpdate(update)
    local previous = lockout_cache[update.display_index]
    lockout_cache[update.display_index] = update.lockout_ms
    if previous == nil then
        return
    end
    if previous == 0 and update.lockout_ms > 0 then
        Emit(AbilityList.Events.OnLockoutStart, update)
    elseif previous > 0 and update.lockout_ms == 0 then
        Emit(AbilityList.Events.OnLockoutEnd, update)
    end
end

--- Drains the ring once and dispatches to subscribers. Safe to call from every
--- subscriber's frame, since a second call in the same frame finds it empty.
function AbilityList.Update()
    if not hook_state.installed then
        return
    end
    for _, update in ipairs(PollUpdatesInternal()) do
        DispatchUpdate(update)
    end
end

return AbilityList
