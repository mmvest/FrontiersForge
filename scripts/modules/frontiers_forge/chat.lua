local ffi = require("ffi")
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

local chat_log_offset       = 0xA7AF28
local chat_log_size         = 32
local chat_log = ffi.cast("chat_log*", Util.EEmem() + chat_log_offset)

local function GetHeadIndex()
    return chat_log.head_index
end

local function GetMessageID(index)
    return chat_log.messages[index].id
end

local function GetMessageDataAsString(index)
    return Util.utf16_to_utf8(chat_log.messages[index].data)
end

local function GetMessageType(index)
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
    Party = nil,
    Tell = nil,
    Guild = nil,
}

-- NEW: track last-returned message id so GetNextMessage() is non-blocking
local last_returned_id = 0

function Chat.GetNextMessage()
    -- Get the current head index.
    local head_index = GetHeadIndex()

    -- Go to the previous index since head index points to the next
    -- slot to write over.
    local last_msg_index = AdjustIndex(head_index, -1)

    -- Grab the message ID
    local last_msg_id = GetMessageID(last_msg_index)

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
        temp_msg_id = GetMessageID(temp_msg_index)
        steps = steps + 1
    end

    -- If we never found a differing id (buffer full of same id), just treat
    -- last_msg_index as the start to avoid freezing.
    if steps >= chat_log_size then
        temp_msg_index = AdjustIndex(last_msg_index, -1)
    end

    -- Move to the first struct of the current message
    last_msg_index = AdjustIndex(temp_msg_index, 1)
    local msg_type = GetMessageType(last_msg_index)

    -- Concatenate message chunks up to head_index, but cap again for safety
    local msg_contents = ""
    steps = 0
    while last_msg_index ~= head_index and steps < chat_log_size do
        msg_contents = msg_contents .. GetMessageDataAsString(last_msg_index)
        last_msg_index = AdjustIndex(last_msg_index, 1)
        steps = steps + 1
    end

    last_returned_id = last_msg_id
    return msg_contents, msg_type
end

function Chat.GetMessageTypeString(msg_type)
    if msg_type == Chat.MsgType.Shout   then return "Shout" end
    if msg_type == Chat.MsgType.Say     then return "Say"   end
    if msg_type == Chat.MsgType.Party   then return "Party" end
    if msg_type == Chat.MsgType.Tell    then return "Tell"  end
    if msg_type == Chat.MsgType.Guild   then return "Guild" end
    return "Unknown Message Type"
end

return Chat
