--[[
json.lua

A minimal JSON decoder and encoder, enough to read the entity database shipped
with the world map and to write the player's journal. Numbers, strings,
booleans, null, arrays, and objects are supported. Encoding sorts object keys
so the output is stable and diff friendly.
]]

local Json = {}

local escape_map = {
    ["\""] = "\"", ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function SkipWhitespace(str, pos)
    local _, stop = str:find("^[ \t\r\n]*", pos)
    return stop + 1
end

local ParseValue

local function ParseString(str, pos)
    -- pos points at the opening quote.
    local buffer = {}
    local index = pos + 1
    local length = #str
    while index <= length do
        local char = str:sub(index, index)
        if char == "\"" then
            return table.concat(buffer), index + 1
        elseif char == "\\" then
            local next_char = str:sub(index + 1, index + 1)
            if next_char == "u" then
                -- Decode a \uXXXX escape into UTF-8. Surrogate pairs are left as
                -- separate code points, which is fine for the ASCII-heavy names here.
                local hex = str:sub(index + 2, index + 5)
                local code = tonumber(hex, 16) or 0
                if code < 0x80 then
                    buffer[#buffer + 1] = string.char(code)
                elseif code < 0x800 then
                    buffer[#buffer + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
                else
                    buffer[#buffer + 1] = string.char(
                        0xE0 + math.floor(code / 0x1000),
                        0x80 + (math.floor(code / 0x40) % 0x40),
                        0x80 + (code % 0x40))
                end
                index = index + 6
            else
                buffer[#buffer + 1] = escape_map[next_char] or next_char
                index = index + 2
            end
        else
            buffer[#buffer + 1] = char
            index = index + 1
        end
    end
    error("unterminated string in JSON")
end

local function ParseNumber(str, pos)
    local number_text = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    return tonumber(number_text), pos + #number_text
end

local function ParseArray(str, pos)
    local result = {}
    local index = SkipWhitespace(str, pos + 1)
    if str:sub(index, index) == "]" then return result, index + 1 end
    while true do
        local value
        value, index = ParseValue(str, index)
        result[#result + 1] = value
        index = SkipWhitespace(str, index)
        local char = str:sub(index, index)
        if char == "]" then return result, index + 1 end
        if char ~= "," then error("expected ',' or ']' in JSON array") end
        index = SkipWhitespace(str, index + 1)
    end
end

local function ParseObject(str, pos)
    local result = {}
    local index = SkipWhitespace(str, pos + 1)
    if str:sub(index, index) == "}" then return result, index + 1 end
    while true do
        index = SkipWhitespace(str, index)
        local key
        key, index = ParseString(str, index)
        index = SkipWhitespace(str, index)
        if str:sub(index, index) ~= ":" then error("expected ':' in JSON object") end
        local value
        value, index = ParseValue(str, SkipWhitespace(str, index + 1))
        result[key] = value
        index = SkipWhitespace(str, index)
        local char = str:sub(index, index)
        if char == "}" then return result, index + 1 end
        if char ~= "," then error("expected ',' or '}' in JSON object") end
        index = index + 1
    end
end

ParseValue = function(str, pos)
    pos = SkipWhitespace(str, pos)
    local char = str:sub(pos, pos)
    if char == "{" then return ParseObject(str, pos) end
    if char == "[" then return ParseArray(str, pos) end
    if char == "\"" then return ParseString(str, pos) end
    if char == "t" then return true, pos + 4 end
    if char == "f" then return false, pos + 5 end
    if char == "n" then return nil, pos + 4 end
    return ParseNumber(str, pos)
end

--- Decode a JSON string into Lua tables. Returns nil plus an error message on failure.
function Json.Decode(text)
    if type(text) ~= "string" then return nil, "expected string" end
    local ok, value = pcall(function()
        local result = ParseValue(text, 1)
        return result
    end)
    if not ok then return nil, value end
    return value
end

local string_escape_map = {
    ["\""] = "\\\"", ["\\"] = "\\\\",
    ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function EncodeString(str)
    return "\"" .. str:gsub("[%z\1-\31\"\\]", function(char)
        return string_escape_map[char] or string.format("\\u%04x", char:byte())
    end) .. "\""
end

-- A table encodes as an array when its keys are exactly 1..n.
local function IsArray(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then return false end
        count = count + 1
    end
    return count == #value
end

local function EncodeValue(value, buffer, indent)
    local value_type = type(value)
    if value_type == "nil" then
        buffer[#buffer + 1] = "null"
    elseif value_type == "boolean" then
        buffer[#buffer + 1] = value and "true" or "false"
    elseif value_type == "number" then
        buffer[#buffer + 1] = string.format("%.10g", value)
    elseif value_type == "string" then
        buffer[#buffer + 1] = EncodeString(value)
    elseif value_type == "table" then
        local child_indent = indent .. "  "
        if IsArray(value) then
            if #value == 0 then buffer[#buffer + 1] = "[]" return end
            buffer[#buffer + 1] = "["
            for index = 1, #value do
                if index > 1 then buffer[#buffer + 1] = "," end
                buffer[#buffer + 1] = "\n" .. child_indent
                EncodeValue(value[index], buffer, child_indent)
            end
            buffer[#buffer + 1] = "\n" .. indent .. "]"
        else
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = key end
            if #keys == 0 then buffer[#buffer + 1] = "{}" return end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            buffer[#buffer + 1] = "{"
            for index, key in ipairs(keys) do
                if index > 1 then buffer[#buffer + 1] = "," end
                buffer[#buffer + 1] = "\n" .. child_indent .. EncodeString(tostring(key)) .. ": "
                EncodeValue(value[key], buffer, child_indent)
            end
            buffer[#buffer + 1] = "\n" .. indent .. "}"
        end
    else
        error("cannot encode a " .. value_type .. " as JSON")
    end
end

--- Encode a Lua table into pretty printed JSON text.
--- Returns nil plus an error message on failure (functions, mixed keys, ...).
function Json.Encode(value)
    local buffer = {}
    local ok, err = pcall(EncodeValue, value, buffer, "")
    if not ok then return nil, err end
    return table.concat(buffer)
end

return Json
