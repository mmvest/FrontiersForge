local ffi = require("ffi")
local util = require("frontiers_forge.util")

-- A quest log entry is nothing but a fixed-size UTF-16 title string. The client
-- keeps no other quest data, everything else is server-side dialogue text.
ffi.cdef[[
    typedef struct {
        wchar_t name[128];  // +0x00  quest title, UTF-16, null terminated
    } Quest;
]]

local Quest = {}
Quest.__index = Quest

Quest.size = 0x100

--- Wraps a raw quest record address in a Quest object.
--- @param address integer|ffi.cdata* Host address of the record, either a number or a Quest pointer.
--- @return table quest New Quest object backed by the record at the given address.
function Quest.new(address)
    if type(address) == "number" then
        address = ffi.cast("Quest*", address)
    elseif not ffi.istype("Quest*", address) then
        error("Invalid pointer type for Quest")
    end

    local self = setmetatable({}, Quest)
    self.ptr = address  -- Store the FFI pointer
    return self
end

--- @return string name The quest title converted to UTF-8.
function Quest:GetName()
    return util.utf16_to_utf8(self.ptr.name)
end

return Quest
