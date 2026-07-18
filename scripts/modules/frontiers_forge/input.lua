local ffi = require("ffi")
local bit = require("bit")
local Util = require("frontiers_forge.util")

-- Controller 01
local Controller_01 =
{
    button_bitfield_ptr  = ffi.cast("uint16_t*", Util.EEmem() + 0x4F3AC2),
    right_analog_ptr    = ffi.cast("uint8_t*",  Util.EEmem() + 0x4F3AC4),
    left_analog_ptr     = ffi.cast("uint8_t*",  Util.EEmem() + 0x4F3AC6)
}

-- TODO: Add controller 02

local Input = {}

Input.button_mask =
{
    square      = 0x8000,
    x           = 0x4000,
    circle      = 0x2000,
    triangle    = 0x1000,

    r1          = 0x0800,
    l1          = 0x0400,
    r2          = 0x0200,
    l2          = 0x0100,

    dpad_up     = 0x0080,
    dpad_right  = 0x0040,
    dpad_down   = 0x0020,
    dpad_left   = 0x0010,

    start       = 0x0008,
    r3          = 0x0004,
    l3          = 0x0002,
    select      = 0x0001
}



function Input.IsButtonPressed(button_mask)
    return Util.IsBitZero(Controller_01.button_bitfield_ptr[0], button_mask)
end

--  7f 7f = analog stick not moving, 7f 00 for pushing up, 7F FF for down, 00 7F for left, FF 7F for right
function Input.GetRawAnalogStickState()
    local analog_stick_state =
    {
        right_x = Controller_01.right_analog_ptr[0],
        right_y = Controller_01.right_analog_ptr[1],
        left_x = Controller_01.left_analog_ptr[0],
        left_y = Controller_01.left_analog_ptr[1]
    }

    return analog_stick_state
end

function Input.GetNormalizedAnalogStickState()
    local raw_state = Input.GetRawAnalogStickState()
    local normalized_state = {}
    for key, value in pairs(raw_state) do
        -- Normalize the raw values between -1 and 1. Doing this "ternary" check to fix some rounding errors so that
        -- the numbers are from -1 to 1, instead of going slightly under or over the min/max
        normalized_state[key] = (value - (value <= 0x7F and 0x7F or 0x80)) / 0x7F

    end

    return normalized_state
end

-- Every keystroke passes through Input_DispatchKeyToFocusedWindow before the game
-- acts on it, so that is where we hook. The cave copies {key_char, is_down, seq}
-- into a ring buffer Lua polls, then consults a 256-byte suppression table (indexed
-- by key character): a suppressed key returns via jr ra so the dispatcher never runs,
-- otherwise the displaced instruction runs and control jumps back into the dispatcher.
-- The patch site is resolved from the VIWndGame overlay slide, same as combat.lua.

local KEY_PATCH_SITE_STATIC = 0x0062C740    -- Input_DispatchKeyToFocusedWindow, in the dump

-- First four instructions at the patch site. All are position independent (no absolute or
-- PC relative fields), so they are identical wherever the overlay loads.
local KEY_SITE_SIGNATURE = {
    0x27BDFFC0, -- addiu sp,sp,-0x40   <- the instruction we replace
    0x34028000, -- ori   v0,zero,0x8000
    0x7FB00000, -- sq    s0,0x0(sp)
    0x7FB20020, -- sq    s2,0x20(sp)
}
local KEY_ORIGINAL_OPCODE = KEY_SITE_SIGNATURE[1]

-- Slide sources, identical to combat.lua so both hooks agree on where the overlay loaded.
local WND_GAME_STATIC_PTR = 0x14E200
local WND_GAME_DRAW_STEPS = { 0x190, 0x53C, 0x20, 0x1C }
local WND_GAME_DRAW_STATIC = 0x006AD8D8
local SCAN_START = 0x00300000
local SCAN_END   = 0x01800000

-- Cave + buffers. Kept well clear of combat.lua's region (0xF5000..0xF58B0) so both hooks
-- can be installed at once. Same EE kernel-reserved gap below the ELF load address.
local KEY_CAVE_OFFSET = 0x000F6000
local KEYBUF_OFFSET   = 0x000F6200
-- Buffer header: +0x0 event counter (u32), +0x4 magic, +0x8 ring size, +0xC reserved.
-- Ring entries start at +0x10, stride 8: +0x0 key char (u8), +0x1 is_down (u8),
--   +0x2 pad (u16), +0x4 sequence number (u32).
-- Suppression table: 256 bytes at KEYBUF + 0x600, one byte per key character.
local KEY_BUF_MAGIC     = 0x4642424B -- "KBBF" (keyboard buffer frontiersforge)
local KEY_RING_SIZE     = 128        -- must be a power of two
local KEY_RING_MASK     = KEY_RING_SIZE - 1
local KEY_ENTRY_SIZE    = 0x8
local KEY_ENTRIES_OFFSET = KEYBUF_OFFSET + 0x10
local KEY_SUPPRESS_TABLE_REL = 0x600 -- relative to KEYBUF_OFFSET
local KEY_SUPPRESS_OFFSET = KEYBUF_OFFSET + KEY_SUPPRESS_TABLE_REL
local KEY_CAVE_REGION_END = KEY_SUPPRESS_OFFSET + 0x100

-- Key characters as translated by the game. Printable keys map to their ASCII value.
-- The dispatcher also delivers controller buttons as codes 0x80 + button_index, which
-- never collide with keyboard characters (always below 0x80).
Input.Key = {
    Enter       = 0x0D,
    Backspace    = 0x08,
    Tab         = 0x09,
    Escape       = 0x1B,
    Space        = 0x20,
}

-- Builds the cave. `back_jump` is the pre-encoded `j site+4` for the non-suppressed path
-- (computed once the runtime site is known). Clobbers t0-t5, t1, t2; leaves a0-a2 intact
-- so the dispatcher still gets its arguments on the non-suppressed path.
local function BuildKeyCaveCode(back_jump)
    local hi = bit.rshift(KEYBUF_OFFSET, 16)
    local lo = bit.band(KEYBUF_OFFSET, 0xFFFF)
    return {
        bit.bor(0x3C080000, hi),            -- lui   t0,hi(keybuf)
        bit.bor(0x35080000, lo),            -- ori   t0,t0,lo(keybuf)
        0x8D0B0000,                         -- lw    t3,0x0(t0)        event counter
        bit.bor(0x316C0000, KEY_RING_MASK), -- andi  t4,t3,RING_MASK   ring slot
        0x000C68C0,                         -- sll   t5,t4,0x3         slot * 8
        0x01A86821,                         -- addu  t5,t5,t0          entry address
        0xA1A50010,                         -- sb    a1,0x10(t5)       entry.key
        0xA1A60011,                         -- sb    a2,0x11(t5)       entry.is_down
        0xADAB0014,                         -- sw    t3,0x14(t5)       entry.seq
        0x256B0001,                         -- addiu t3,t3,0x1         counter + 1
        0xAD0B0000,                         -- sw    t3,0x0(t0)        store counter
        0x30A900FF,                         -- andi  t1,a1,0xFF        key index 0-255
        0x01095021,                         -- addu  t2,t0,t1          &suppress_table[key] - 0x600
        bit.bor(0x914A0000, KEY_SUPPRESS_TABLE_REL), -- lbu t2,0x600(t2)  suppress_table[key]
        0x15400004,                         -- bne   t2,zero,+4        suppressed -> jr ra
        0x00000000,                         -- _nop                    (branch delay slot)
        KEY_ORIGINAL_OPCODE,                -- addiu sp,sp,-0x40        displaced instruction
        back_jump,                          -- j     site+4            back into the dispatcher
        0x00000000,                         -- _nop                    (jump delay slot)
        0x03E00008,                         -- jr    ra                suppress: skip dispatcher
        0x00000000,                         -- _nop                    (jump delay slot)
    }
end

local function KeySignatureMatchesAt(offset)
    for i, word in ipairs(KEY_SITE_SIGNATURE) do
        if Util.ReadFromOffset(offset + (i - 1) * 4, "uint32_t") ~= word then
            return false
        end
    end
    return true
end

local function ScanForKeySignature()
    local mem = ffi.cast("uint32_t*", Util.EEmem() + SCAN_START)
    local words = (SCAN_END - SCAN_START) / 4
    local s1, s2, s3, s4 = KEY_SITE_SIGNATURE[1], KEY_SITE_SIGNATURE[2], KEY_SITE_SIGNATURE[3], KEY_SITE_SIGNATURE[4]
    for i = 0, words - 4 do
        if mem[i] == s1 and mem[i + 1] == s2 and mem[i + 2] == s3 and mem[i + 3] == s4 then
            return SCAN_START + i * 4
        end
    end
    return nil
end

-- Resolves the runtime patch site. Second return is true when the site already holds our
-- jump (e.g. the script reloaded without uninstalling first).
local function ResolveKeyPatchSite()
    local jal_or_j_present = bit.bor(0x08000000, bit.rshift(KEY_CAVE_OFFSET, 2))

    local draw_ptr_offset = Util.GetOffsetFromPointerChain(WND_GAME_STATIC_PTR, WND_GAME_DRAW_STEPS)
    if draw_ptr_offset ~= nil then
        local draw_runtime = Util.ReadFromOffset(draw_ptr_offset, "uint32_t")
        if draw_runtime ~= 0 and draw_runtime < 0x02000000 then
            local site = KEY_PATCH_SITE_STATIC + (draw_runtime - WND_GAME_DRAW_STATIC)
            if site > 0 and site < 0x02000000 - 0x10 then
                local first = Util.ReadFromOffset(site, "uint32_t")
                if first == jal_or_j_present then
                    return site, true, nil
                end
                if KeySignatureMatchesAt(site) then
                    return site, false, nil
                end
            end
        end
    end

    local site = ScanForKeySignature()
    if site ~= nil then
        return site, false, nil
    end
    return nil, nil, "keyboard dispatcher signature not found (are you in game?)"
end

local key_hook_state = {
    installed = false,
    patch_site = nil,
    last_seq = 0,
    dropped = 0,
}

--- @return boolean installed True if the keyboard hook is currently installed.
function Input.IsKeyHookInstalled()
    return key_hook_state.installed
end

--- Installs the keyboard hook. Never touches game memory unless the patch site resolves
--- and signature matches and the cave region is free.
--- @return boolean success True if the hook is installed (or already was).
--- @return string|nil error Present only on failure, a human readable reason.
function Input.InstallKeyHook()
    if key_hook_state.installed then
        return true
    end

    local site, already_patched, err = ResolveKeyPatchSite()
    if site == nil then
        return false, "keyboard hook: " .. err
    end

    -- Cave region must be all zeros, or already hold our magic from a previous session.
    local magic = Util.ReadFromOffset(KEYBUF_OFFSET + 4, "uint32_t")
    if magic ~= KEY_BUF_MAGIC then
        for offset = KEY_CAVE_OFFSET, KEY_CAVE_REGION_END - 4, 4 do
            if Util.ReadFromOffset(offset, "uint32_t") ~= 0 then
                return false, "keyboard hook: cave region at 0xF6000 is not free"
            end
        end
    end

    -- Back jump lands on the instruction after the one we replace (site + 4).
    local back_jump = bit.bor(0x08000000, bit.band(bit.rshift(site + 4, 2), 0x03FFFFFF))

    -- Write the cave and header first so the jump target is valid code before we patch.
    local code = BuildKeyCaveCode(back_jump)
    for i, word in ipairs(code) do
        Util.WriteToOffset(KEY_CAVE_OFFSET + (i - 1) * 4, "uint32_t", word)
    end
    Util.WriteToOffset(KEYBUF_OFFSET, "uint32_t", 0)                -- event counter
    Util.WriteToOffset(KEYBUF_OFFSET + 4, "uint32_t", KEY_BUF_MAGIC)
    Util.WriteToOffset(KEYBUF_OFFSET + 8, "uint32_t", KEY_RING_SIZE)
    Util.WriteToOffset(KEYBUF_OFFSET + 12, "uint32_t", 0)
    -- Leave the suppression table as it is when reattaching to our own magic, otherwise
    -- zero it so no key is suppressed until the caller asks.
    if magic ~= KEY_BUF_MAGIC then
        for offset = KEY_SUPPRESS_OFFSET, KEY_SUPPRESS_OFFSET + 0xFF, 4 do
            Util.WriteToOffset(offset, "uint32_t", 0)
        end
    end

    if not already_patched then
        local j_cave = bit.bor(0x08000000, bit.band(bit.rshift(KEY_CAVE_OFFSET, 2), 0x03FFFFFF))
        Util.WriteToOffset(site, "uint32_t", j_cave)
    end

    key_hook_state.installed = true
    key_hook_state.patch_site = site
    key_hook_state.last_seq = Util.ReadFromOffset(KEYBUF_OFFSET, "uint32_t")
    key_hook_state.dropped = 0
    return true
end

--- Restores the original dispatcher instruction and zeroes the cave region. Safe to call
--- even when the hook is not installed.
--- @return boolean success True on success, including when there is nothing to clean up.
function Input.UninstallKeyHook()
    local site = key_hook_state.patch_site
    if site == nil then
        local resolved, already_patched = ResolveKeyPatchSite()
        if resolved == nil or not already_patched then
            return true
        end
        site = resolved
    end

    local j_cave = bit.bor(0x08000000, bit.band(bit.rshift(KEY_CAVE_OFFSET, 2), 0x03FFFFFF))
    if Util.ReadFromOffset(site, "uint32_t") == j_cave then
        Util.WriteToOffset(site, "uint32_t", KEY_ORIGINAL_OPCODE)
    end

    -- Patch is gone, so nothing can reach the cave. Zero the whole region including the
    -- suppression table so a future install starts clean.
    for offset = KEY_CAVE_OFFSET, KEY_CAVE_REGION_END - 4, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end

    key_hook_state.installed = false
    key_hook_state.patch_site = nil
    key_hook_state.last_seq = 0
    return true
end

--- Suppress (or stop suppressing) a key so the game never acts on it. For example, suppress
--- Input.Key.Enter to stop the default EQOA typing window from opening, then drive your own
--- chat entry from the polled events. Requires the hook to be installed.
--- @param key_char integer Key character code, e.g. Input.Key.Enter. Only 0-255 is stored.
--- @param suppressed boolean True to swallow the key, false to let it through.
function Input.SetKeySuppressed(key_char, suppressed)
    if not key_hook_state.installed then return end
    key_char = bit.band(key_char, 0xFF)
    Util.WriteToOffset(KEY_SUPPRESS_OFFSET + key_char, "uint8_t", suppressed and 1 or 0)
end

--- @param key_char integer Key character code.
--- @return boolean suppressed True if the key is currently being swallowed.
function Input.IsKeySuppressed(key_char)
    if not key_hook_state.installed then return false end
    key_char = bit.band(key_char, 0xFF)
    return Util.ReadFromOffset(KEY_SUPPRESS_OFFSET + key_char, "uint8_t") ~= 0
end

--- Stops suppressing every key.
function Input.ClearAllSuppressedKeys()
    if not key_hook_state.installed then return end
    for offset = KEY_SUPPRESS_OFFSET, KEY_SUPPRESS_OFFSET + 0xFF, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end
end

--- Returns key events captured since the previous poll. Each event table has fields:
---   key      key character code (Input.Key.Enter is 0x0D, printable keys are ASCII)
---   is_down  true when the key was pressed, false when released
---   seq      monotonically increasing event number
--- Events are returned whether or not the key was suppressed, so a suppressed key still
--- shows up here for you to handle.
--- @return table[] events Array of event tables, oldest first. Empty if none or not hooked.
function Input.PollKeyEvents()
    local events = {}
    if not key_hook_state.installed then
        return events
    end

    local count = Util.ReadFromOffset(KEYBUF_OFFSET, "uint32_t")
    if count == key_hook_state.last_seq then
        return events
    end

    local first = key_hook_state.last_seq
    if count - first > KEY_RING_SIZE then
        key_hook_state.dropped = key_hook_state.dropped + (count - first - KEY_RING_SIZE)
        first = count - KEY_RING_SIZE
    end

    for seq = first, count - 1 do
        local entry = KEY_ENTRIES_OFFSET + bit.band(seq, KEY_RING_MASK) * KEY_ENTRY_SIZE
        if Util.ReadFromOffset(entry + 0x4, "uint32_t") == seq then
            events[#events + 1] = {
                key = Util.ReadFromOffset(entry, "uint8_t"),
                is_down = Util.ReadFromOffset(entry + 0x1, "uint8_t") ~= 0,
                seq = seq,
            }
        else
            key_hook_state.dropped = key_hook_state.dropped + 1
        end
    end

    key_hook_state.last_seq = count
    return events
end

--- @return integer dropped Number of key events lost to ring-buffer overruns.
function Input.GetDroppedKeyCount()
    return key_hook_state.dropped
end


return Input