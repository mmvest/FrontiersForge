local ffi = require("ffi")
local bit = require("bit")
local Util = require("frontiers_forge.util")

ffi.cdef[[
typedef struct {
    wchar_t data[64];       // 128 bytes
    uint32_t type;
    uint32_t unknown_00[3];
    uint32_t is_displayed;
    uint32_t unknown_01;
    uint32_t id;
    uint32_t unused;
} message;

typedef struct 
{
    uint32_t tail_index;
    uint32_t head_index;
    uint32_t unknown[2];
    message messages[32];
} chat_log;
]]

local Chat = {}

local chat_log_size         = 32

-- Resolve the chat log lazily. The chat log doesn't exist until in game, and the chain
-- will return nil until then. Returns a cast chat_log* or nil.
local function GetChatLog()
    local chat_log_offset = Util.GetOffsetFromPointerChain(0x14E200, {0x178, 0x654, 0x688, 0x1A8})
    if chat_log_offset == nil then
        return nil
    end
    return ffi.cast("chat_log*", Util.EEmem() + chat_log_offset)
end

local function GetHeadIndex(chat_log)
    return chat_log.head_index
end

local function GetMessageID(chat_log, index)
    return chat_log.messages[index].id
end

local function GetMessageDataAsString(chat_log, index)
    return Util.utf16_to_utf8(chat_log.messages[index].data)
end

local function GetMessageType(chat_log, index)
    return chat_log.messages[index].type
end

local function AdjustIndex(index, offset)
    local new_index = (index + offset) % chat_log_size
    if new_index < 0 then new_index = new_index + chat_log_size end
    return new_index
end

Chat.MsgType = {
    Say = 0x3F800000,
    Shout = 0x3E7CFCFD,
    Party = 0x3F000000,
    Tell = 0x3F008081,
    Guild = 0x3E800000,
}

-- track last-returned message id so GetNextMessage() is non-blocking
local last_returned_id = 0

--- Non-blocking poll for the newest chat message. Returns each message once,
--- then returns an empty string until a new message arrives.
--- @return string msg_contents Full message text, or an empty string when there is nothing new.
--- @return integer msg_type Message type value, see Chat.MsgType. 0 when there is nothing new.
function Chat.GetNextMessage()
    local chat_log = GetChatLog()
    if chat_log == nil then
        return "", 0
    end

    -- Get the current head index.
    local head_index = GetHeadIndex(chat_log)

    -- Go to the previous index since head index points to the next
    -- slot to write over.
    local last_msg_index = AdjustIndex(head_index, -1)

    -- Grab the message ID
    local last_msg_id = GetMessageID(chat_log, last_msg_index)

    -- If nothing has changed, return empty string (non-blocking)
    if last_msg_id == 0 or last_msg_id == last_returned_id then
        return "", 0
    end

    -- While the messages contain the same ID, keep going backward
    -- This is so we can find the start of the full message
    -- Find start of message by walking backwards WHILE IDs match,
    -- but NEVER loop forever: hard cap at chat_log_size steps.
    local temp_msg_index = last_msg_index
    local temp_msg_id = last_msg_id

    local steps = 0
    while last_msg_id == temp_msg_id and steps < chat_log_size do
        temp_msg_index = AdjustIndex(temp_msg_index, -1)
        temp_msg_id = GetMessageID(chat_log, temp_msg_index)
        steps = steps + 1
    end

    -- If we never found a differing id (buffer full of same id), just treat
    -- last_msg_index as the start to avoid freezing.
    if steps >= chat_log_size then
        temp_msg_index = AdjustIndex(last_msg_index, -1)
    end

    -- Move to the first struct of the current message
    last_msg_index = AdjustIndex(temp_msg_index, 1)
    local msg_type = GetMessageType(chat_log, last_msg_index)

    -- Concatenate message chunks up to head_index, but cap again for safety
    local msg_contents = ""
    steps = 0
    while last_msg_index ~= head_index and steps < chat_log_size do
        msg_contents = msg_contents .. GetMessageDataAsString(chat_log, last_msg_index)
        last_msg_index = AdjustIndex(last_msg_index, 1)
        steps = steps + 1
    end

    last_returned_id = last_msg_id
    return msg_contents, msg_type
end

--- Converts a message type value into a readable name.
--- @param msg_type integer Message type value as returned by GetNextMessage.
--- @return string name One of "Say", "Shout", "Party", "Tell", "Guild", or "Unknown Message Type".
function Chat.GetMessageTypeString(msg_type)
    if msg_type == Chat.MsgType.Shout   then return "Shout" end
    if msg_type == Chat.MsgType.Say     then return "Say"   end
    if msg_type == Chat.MsgType.Party   then return "Party" end
    if msg_type == Chat.MsgType.Tell    then return "Tell"  end
    if msg_type == Chat.MsgType.Guild   then return "Guild" end
    return "Unknown Message Type"
end


-- =====================================================================================
-- Sending chat messages as the game does
-- =====================================================================================
--
-- ChatInput_ProcessTypedText is the game's own handler for a submitted chat line. It
-- parses slash commands and routes to the right sender, so driving it makes our sends
-- byte-identical to typed chat, slash commands included. Lua cannot call it directly
-- (it must run on the game thread mid-frame), so we write the text into unused EE memory,
-- set a pending flag, and a per-frame trigger cave picks it up and clears the flag.

local SEND_PATCH_SITE_STATIC   = 0x00623574   -- `jal 0x623ea0` inside GameClient_InGameUpdate
local SEND_DISPLACED_TARGET    = 0x00623ea0   -- what that jal originally called
local SEND_FUNC_STATIC         = 0x0062CBF8   -- ChatInput_ProcessTypedText

-- Slide sources, identical to combat.lua / input.lua so every hook agrees on the overlay slide.
local WND_GAME_STATIC_PTR  = 0x14E200
local WND_GAME_DRAW_STEPS  = { 0x190, 0x53C, 0x20, 0x1C }
local WND_GAME_DRAW_STATIC = 0x006AD8D8

-- Cave + control block, clear of combat.lua (0xF5000) and input.lua (0xF6000) regions.
local SEND_CAVE_OFFSET = 0x000F7000
local SENDCTL_OFFSET   = 0x000F7100
-- Control block: +0x0 saved ra, +0x4 saved a0, +0x8 pending flag, +0xC magic.
-- UTF-16 text buffer starts at +0x20 (ChatInput_ProcessTypedText requires
-- strlen16(text) < 0x80 units, so 0x100 bytes including the terminator suffices).
local SEND_TEXT_OFFSET   = SENDCTL_OFFSET + 0x20
local SEND_MSG_MAX_BYTES = 0x100
local SEND_REGION_END    = SEND_TEXT_OFFSET + SEND_MSG_MAX_BYTES
local SEND_MAGIC         = 0x46464253 -- "SBFF" (send buffer frontiersforge)

-- Builds the trigger cave. jal_send / j_original are pre-encoded from the runtime addresses
-- (the send function and the displaced call both live in the relocatable overlay).
local function BuildSendCaveCode(jal_send, j_original)
    local hi = bit.rshift(SENDCTL_OFFSET, 16)
    local lo = bit.band(SENDCTL_OFFSET, 0xFFFF)
    local lui_t0 = bit.bor(0x3C080000, hi)
    local ori_t0 = bit.bor(0x35080000, lo)
    return {
        lui_t0,        -- lui   t0,hi(sendctl)
        ori_t0,        -- ori   t0,t0,lo(sendctl)
        0xAD1F0000,    -- sw    ra,0x0(t0)        save real return address
        0xAD040004,    -- sw    a0,0x4(t0)        save a0 (singleton)
        0x8D090008,    -- lw    t1,0x8(t0)        pending flag
        0x11200008,    -- beq   t1,zero,+8        nothing pending -> displaced call
        0x00000000,    -- _nop                    (branch delay slot)
        0x8D040004,    -- lw    a0,0x4(t0)         a0 = singleton (app)
        0x25050020,    -- addiu a1,t0,0x20         a1 = &utf16_text
        jal_send,      -- jal   ChatInput_ProcessTypedText
        0x00000000,    -- _nop                    (call delay slot)
        lui_t0,        -- lui   t0,hi(sendctl)     reload (call clobbered t0)
        ori_t0,        -- ori   t0,t0,lo(sendctl)
        0xAD000008,    -- sw    zero,0x8(t0)       clear pending flag
        lui_t0,        -- lui   t0,hi(sendctl)     SKIP: reload
        ori_t0,        -- ori   t0,t0,lo(sendctl)
        0x8D1F0000,    -- lw    ra,0x0(t0)         restore real return address
        0x8D040004,    -- lw    a0,0x4(t0)         restore a0 (singleton)
        j_original,    -- j     0x00623ea0         displaced call, returns via ra into the frame
        0x00000000,    -- _nop                    (jump delay slot)
    }
end

local function ResolveOverlaySlide()
    local draw_ptr_offset = Util.GetOffsetFromPointerChain(WND_GAME_STATIC_PTR, WND_GAME_DRAW_STEPS)
    if draw_ptr_offset == nil then
        return nil, "game UI not loaded (are you in game?)"
    end
    local draw_runtime = Util.ReadFromOffset(draw_ptr_offset, "uint32_t")
    if draw_runtime == 0 or draw_runtime >= 0x02000000 then
        return nil, "bad draw-function pointer"
    end
    return draw_runtime - WND_GAME_DRAW_STATIC, nil
end

local function EncodeJump(is_link, target)
    -- j / jal use the low 28 bits of the (word-aligned) target.
    local base = is_link and 0x0C000000 or 0x08000000
    return bit.bor(base, bit.band(bit.rshift(target, 2), 0x03FFFFFF))
end

local send_hook_state = {
    installed = false,
    patch_site = nil,
    original_word = nil,
}

--- @return boolean installed True if the chat-send hook is currently installed.
function Chat.IsSendHookInstalled()
    return send_hook_state.installed
end

--- Installs the chat-send hook. Never writes to game memory unless the patch site resolves to
--- the exact relocated `jal` we expect and the cave region is free.
--- @return boolean success True if the hook is installed (or already was).
--- @return string|nil error Present only on failure, a human readable reason.
function Chat.InstallSendHook()
    if send_hook_state.installed then
        return true
    end

    local slide, err = ResolveOverlaySlide()
    if slide == nil then
        return false, "chat send hook: " .. err
    end

    local site = SEND_PATCH_SITE_STATIC + slide
    local send_runtime = SEND_FUNC_STATIC + slide
    local displaced_runtime = SEND_DISPLACED_TARGET + slide

    -- The untouched site holds `jal displaced_runtime`. Our patch replaces it with a jal into
    -- the cave. Validate against the exact relocated encodings so we never patch the wrong word.
    local expected_original = EncodeJump(true, displaced_runtime)
    local jal_cave = EncodeJump(true, SEND_CAVE_OFFSET)

    local current = Util.ReadFromOffset(site, "uint32_t")
    local already_patched = (current == jal_cave)
    if not already_patched then
        if current ~= expected_original then
            return false, "chat send hook: patch site did not match expected jal"
        end
        -- Sanity co-check: the instruction two words on is `ori v0,zero,0x8000` (position
        -- independent), which the untouched update always has right after this call.
        if Util.ReadFromOffset(site + 8, "uint32_t") ~= 0x34028000 then
            return false, "chat send hook: patch site sanity check failed"
        end
    end

    -- Cave region must be all zeros, or already hold our magic from a previous session.
    local magic = Util.ReadFromOffset(SENDCTL_OFFSET + 0xC, "uint32_t")
    if magic ~= SEND_MAGIC then
        for offset = SEND_CAVE_OFFSET, SEND_REGION_END - 4, 4 do
            if Util.ReadFromOffset(offset, "uint32_t") ~= 0 then
                return false, "chat send hook: cave region at 0xF7000 is not free"
            end
        end
    end

    -- Write the cave and control header first so the jump target is valid before we patch.
    local jal_send = EncodeJump(true, send_runtime)
    local j_original = EncodeJump(false, displaced_runtime)
    local code = BuildSendCaveCode(jal_send, j_original)
    for i, word in ipairs(code) do
        Util.WriteToOffset(SEND_CAVE_OFFSET + (i - 1) * 4, "uint32_t", word)
    end
    Util.WriteToOffset(SENDCTL_OFFSET + 0x0, "uint32_t", 0)   -- saved ra
    Util.WriteToOffset(SENDCTL_OFFSET + 0x4, "uint32_t", 0)   -- saved a0
    Util.WriteToOffset(SENDCTL_OFFSET + 0x8, "uint32_t", 0)   -- pending flag
    Util.WriteToOffset(SENDCTL_OFFSET + 0xC, "uint32_t", SEND_MAGIC)

    if not already_patched then
        Util.WriteToOffset(site, "uint32_t", jal_cave)
    end

    send_hook_state.installed = true
    send_hook_state.patch_site = site
    send_hook_state.original_word = expected_original
    return true
end

--- Restores the original call instruction and zeroes the cave region. Safe to call even when
--- the hook is not installed.
--- @return boolean success True on success, including when there is nothing to clean up.
function Chat.UninstallSendHook()
    local site = send_hook_state.patch_site
    local original_word = send_hook_state.original_word
    if site == nil then
        local slide = ResolveOverlaySlide()
        if slide == nil then
            return true -- can't resolve, nothing we can safely do
        end
        site = SEND_PATCH_SITE_STATIC + slide
        original_word = EncodeJump(true, SEND_DISPLACED_TARGET + slide)
    end

    local jal_cave = EncodeJump(true, SEND_CAVE_OFFSET)
    if Util.ReadFromOffset(site, "uint32_t") == jal_cave then
        Util.WriteToOffset(site, "uint32_t", original_word)
    end

    -- Patch is gone, so nothing can reach the cave. Zero the whole region.
    for offset = SEND_CAVE_OFFSET, SEND_REGION_END - 4, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end

    send_hook_state.installed = false
    send_hook_state.patch_site = nil
    send_hook_state.original_word = nil
    return true
end

-- Writes a UTF-16 (null terminated) copy of `text` into guest memory at `offset`, never
-- exceeding max_bytes (including the terminator).
local function WriteWideString(offset, text, max_bytes)
    local units = math.floor(max_bytes / 2)
    if units <= 0 then return end
    local wide = Util.utf8_to_utf16(text)         -- wchar_t[] (UTF-16LE on Windows), null terminated
    local i = 0
    while i < units - 1 do
        local unit = wide[i]
        if unit == 0 then break end
        Util.WriteToOffset(offset + i * 2, "uint16_t", unit)
        i = i + 1
    end
    Util.WriteToOffset(offset + i * 2, "uint16_t", 0)  -- always null terminate in bounds
end

--- Slash-command prefixes understood by the typed-chat processor (string table at
--- 0x7376d0 in the dump). Pass one as the `mode` argument of Chat.SendChatText to route
--- a plain message. There is no persistent way to "set" the mode from a slash command —
--- the processor temporarily switches mode for the one send and then restores the sticky
--- mode (which only the game's own chat-mode UI changes) — so per-send prefixing IS the
--- mechanism the game itself uses.
Chat.ChatMode = {
    Default = "",        -- whatever the game's sticky chat mode currently is (usually say)
    Say     = "/say",
    Group   = "/group",
    Guild   = "/guild",
    Shout   = "/shout",
}

--- Sends chat text exactly as if the player had typed it into EQOA's chat entry box and
--- pressed Enter. The text goes through the game's own typed-chat processor
--- (ChatInput_ProcessTypedText, 0x62CBF8), so slash commands work: "/say hi",
--- "/shout hello", "/tell Name message", "/reply text", or plain text for the current
--- chat mode. Requires the send hook to be installed and the player to be in game.
--- @param text string The chat line to process, at most 127 characters (game limit).
--- @param mode string|nil Optional Chat.ChatMode prefix applied to plain text. Ignored
---   when the text already starts with "/" (explicit commands always win).
--- @return boolean success True if the text was queued.
--- @return string|nil error Present only on failure, a human readable reason.
function Chat.SendChatText(text, mode)
    if not send_hook_state.installed then
        return false, "chat send hook not installed"
    end
    if Util.IsInGame() == 0 then
        return false, "not in game"
    end

    -- One in-flight message at a time. The cave clears the flag once it has sent, so if it
    -- is still set the previous message has not gone out yet.
    if Util.ReadFromOffset(SENDCTL_OFFSET + 0x8, "uint32_t") ~= 0 then
        return false, "a previous message is still pending"
    end

    text = tostring(text or "")
    if text == "" then
        return false, "empty message"
    end
    mode = mode or ""
    if mode ~= "" and text:sub(1, 1) ~= "/" then
        text = mode .. " " .. text
    end
    -- The game's processor drops anything with strlen16 >= 0x80.
    if #text >= 0x80 then
        return false, "message too long (127 character max)"
    end

    for offset = SEND_TEXT_OFFSET, SEND_REGION_END - 4, 4 do
        Util.WriteToOffset(offset, "uint32_t", 0)
    end
    WriteWideString(SEND_TEXT_OFFSET, text, SEND_MSG_MAX_BYTES)

    -- Set the pending flag LAST so the cave never sees a half-built buffer.
    Util.WriteToOffset(SENDCTL_OFFSET + 0x8, "uint32_t", 1)
    return true
end

--- Backwards-compatible wrapper around Chat.SendChatText. channel_index/channel_type are
--- obsolete (the typed-chat processor handles channel routing itself) and are ignored; a
--- target_name turns the message into a "/tell target_name text".
--- @param channel_index integer Ignored, kept for compatibility.
--- @param text string The message text to send.
--- @param target_name string|nil Recipient name; when non-empty the message is sent as a tell.
--- @return boolean success True if the message was queued for send.
--- @return string|nil error Present only on failure, a human readable reason.
function Chat.SendMessage(channel_index, text, target_name)
    text = tostring(text or "")
    target_name = tostring(target_name or "")
    if target_name ~= "" then
        text = "/tell " .. target_name .. " " .. text
    end
    return Chat.SendChatText(text)
end

--- Whether a queued message is still waiting for the cave to pick it up. The cave clears
--- the flag the moment it calls the game's send function, so a flag that stays set for
--- more than a frame means the hooked per-frame call site is not executing at all —
--- the single most useful diagnostic when sends appear to vanish.
--- @return boolean pending True when a message is queued but not yet handed to the game.
function Chat.IsSendPending()
    if not send_hook_state.installed then
        return false
    end
    return Util.ReadFromOffset(SENDCTL_OFFSET + 0x8, "uint32_t") ~= 0
end

-- =====================================================================================
-- Channel-type discovery
-- =====================================================================================
--
-- NOTE: everything below concerns the 0x6c custom-CHANNEL send path only. Normal chat
-- (Chat.SendChatText) goes through the typed-chat processor and needs none of this. The
-- channel_type byte the 0x6c sender needs is per-character config carried by the game's
-- own chat window, so it is read from the live window rather than guessed. Open EQOA's
-- chat window (Enter) and call Chat.CaptureChannelTypeFromGameWindow().

local FOCUSED_WINDOW_PTR_OFFSET = 0x4E37F4
local VIUI_PTR_OFFSET           = 0x4E37F0   -- VIUI object at singleton+4 (see ability_bar.lua)
local ACTIVE_WINDOW_VIUI_OFFSET = 0x2BD3C    -- singleton+0x2BD40, shifted -4 for the VIUI anchor
local CHANNEL_TABLE_STATIC      = 0x751DC8
local CHANNEL_TABLE_SLOTS       = 0x100

-- Tests whether a window object looks like the game's chat window: a valid channel
-- config-array pointer at +0x2c AND a plausible selected-slot (0-3) at +0x44.
-- Returns channel_type byte + selected slot, or nil.
local function TryReadChatWindowType(wnd)
    if not Util.IsValidEEPointer(wnd) or wnd + 0x48 > Util.EE_RAM_SIZE then
        return nil
    end
    local arr = Util.ReadFromOffset(wnd + 0x2C, "uint32_t")
    local selected = Util.ReadFromOffset(wnd + 0x44, "uint32_t")
    if Util.IsValidEEPointer(arr) and selected < 4 then
        return Util.ReadFromOffset(arr, "uint8_t"), selected
    end
    return nil
end

--- Reads the channel-type byte out of the game's own chat window. The window (or its
--- text-entry child, which is what actually holds focus while typing) must be open.
--- Focus while typing sits on the text-entry child, so starting from each focus anchor
--- ([0x4E37F4] and the game's active window at singleton+0x2BD40) the parent chain
--- (VIWnd+0x14, set by AddChild) is walked upward testing every window on the way.
--- @return integer|nil channel_type The byte the game would pass to its send function.
--- @return string|nil error Present only on failure.
--- @return integer|nil selected_slot The channel slot (0-3) currently selected in the window.
function Chat.CaptureChannelTypeFromGameWindow()
    local starts = {}
    local focused = Util.ReadFromOffset(FOCUSED_WINDOW_PTR_OFFSET, "uint32_t")
    if Util.IsValidEEPointer(focused) then
        starts[#starts + 1] = focused
    end
    local active = Util.ReadFromPointerChain(VIUI_PTR_OFFSET, {ACTIVE_WINDOW_VIUI_OFFSET}, "uint32_t", 0)
    if Util.IsValidEEPointer(active) then
        starts[#starts + 1] = active
    end
    if #starts == 0 then
        return nil, "no focused/active window (are you in game?)"
    end

    local seen = {}
    for _, start in ipairs(starts) do
        local wnd = start
        for _ = 1, 4 do -- window, parent, grandparent, great-grandparent
            if not Util.IsValidEEPointer(wnd) or seen[wnd] then
                break
            end
            seen[wnd] = true
            local channel_type, selected = TryReadChatWindowType(wnd)
            if channel_type ~= nil then
                return channel_type, nil, selected
            end
            if wnd + 0x18 > Util.EE_RAM_SIZE then
                break
            end
            wnd = Util.ReadFromOffset(wnd + 0x14, "uint32_t")
        end
    end

    return nil, "chat window not found - open EQOA's own chat window (Enter) and try again"
end

--- Debug helper for locating the chat window: walks the parent chain (+0x14) from both
--- focus anchors and reports each window's address, vtable (raw and slide-adjusted back
--- to dump coordinates, so it can be looked up in Ghidra), and the two chat-window
--- signature fields (+0x2c array pointer, +0x44 selected slot).
--- @return string[] lines Human-readable dump, one line per window hop.
function Chat.DebugDumpFocusChain()
    local lines = {}
    local slide = ResolveOverlaySlide() or 0

    local function dump(start_name, wnd)
        for hop = 0, 3 do
            if not Util.IsValidEEPointer(wnd) or wnd + 0x48 > Util.EE_RAM_SIZE then
                lines[#lines + 1] = string.format("%s hop%d: invalid (0x%08X)", start_name, hop, wnd or 0)
                break
            end
            local vtbl = Util.ReadFromOffset(wnd + 0x20, "uint32_t")
            local arr  = Util.ReadFromOffset(wnd + 0x2C, "uint32_t")
            local sel  = Util.ReadFromOffset(wnd + 0x44, "uint32_t")
            lines[#lines + 1] = string.format(
                "%s hop%d: wnd=0x%08X vtbl=0x%08X (static 0x%08X) +2c=0x%08X +44=0x%08X",
                start_name, hop, wnd, vtbl, vtbl - slide, arr, sel)
            wnd = Util.ReadFromOffset(wnd + 0x14, "uint32_t")
        end
    end

    dump("focused", Util.ReadFromOffset(FOCUSED_WINDOW_PTR_OFFSET, "uint32_t"))
    dump("active ", Util.ReadFromPointerChain(VIUI_PTR_OFFSET, {ACTIVE_WINDOW_VIUI_OFFSET}, "uint32_t", 0))
    return lines
end

--- Dumps the live entries of the global channel table.
--- @return table[]|nil entries Array of { index, byte0, byte1 } for each non-null slot
---   (byte1 == 2 marks a channel the OnMessage send path auto-resubscribes), or nil on error.
--- @return string|nil error Present only on failure.
function Chat.GetChannelTableInfo()
    local slide, err = ResolveOverlaySlide()
    if slide == nil then
        return nil, "channel table: " .. err
    end
    local table_offset = CHANNEL_TABLE_STATIC + slide
    if table_offset < 0 or table_offset + CHANNEL_TABLE_SLOTS * 4 > Util.EE_RAM_SIZE then
        return nil, "channel table: slide-adjusted address out of range"
    end

    local entries = {}
    for i = 0, CHANNEL_TABLE_SLOTS - 1 do
        local ptr = Util.ReadFromOffset(table_offset + i * 4, "uint32_t")
        if Util.IsValidEEPointer(ptr) and ptr + 2 <= Util.EE_RAM_SIZE then
            entries[#entries + 1] = {
                index = i,
                byte0 = Util.ReadFromOffset(ptr, "uint8_t"),
                byte1 = Util.ReadFromOffset(ptr + 1, "uint8_t"),
            }
        end
    end
    return entries
end

return Chat
