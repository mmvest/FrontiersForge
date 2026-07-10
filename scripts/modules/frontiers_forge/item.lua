local ffi  = require("ffi")
local Util = require("frontiers_forge.util")

-- Accessors for a single inventory item record. Inventory owns the record
-- array and passes record offsets here. Item.new returns a live object, both
-- its methods (item:GetName()) and its properties (item.name) read memory at
-- access time through the record offset stored in item.record.

local Item = {}

-- Field offsets relative to a record base, record stride is 0x2FC
local OFFSET = {
    ["Icon"]           = 0x0C,   -- uint32 icon hash
    ["Icon Frontiers"] = 0x10,   -- uint32 icon hash, 0 when none
    ["Slot"]           = 0x14,
    ["Range"]          = 0x30,
    ["Level Req"]      = 0x34,
    ["Max Stack"]      = 0x38,
    ["Max HP"]         = 0x3C,
    ["Dur"]            = 0x40,
    ["Name"]           = 0x5C,   -- UTF-16 string
    ["Description"]    = 0xDC,   -- UTF-16 string
    ["Amount"]         = 0x2E4,  -- uint32
    ["Equipped Flag"]  = 0x2F0,  -- uint32
}

-- Equipped Flag meanings
local U32_NOT_EQUIPPED = 0xFFFFFFFF
local U32_ALT_INVALID  = 429496725  -- fallback

local function is_not_equipped_value(v)
    return v == U32_NOT_EQUIPPED or v == U32_ALT_INVALID
end

local function read_uint(record, field, ctype)
    return Util.ReadFromOffset(record + OFFSET[field], ctype or "uint32_t")
end

local function read_wstring(record, field)
    local wptr = ffi.cast("const wchar_t*", Util.EEmem() + record + OFFSET[field])
    local s = Util.utf16_to_utf8(wptr)
    if not s or s == "" then return "" end
    return s
end

-- ===============================
-- Field getters (record offset in)
-- ===============================

--- Equip slot type id, 0 when the record is empty.
--- @param record integer Item record offset in EE memory.
--- @return integer slot_id
function Item.GetSlotId(record)
    return read_uint(record, "Slot")
end

--- Item name.
--- @param record integer Item record offset in EE memory.
--- @return string name Name in UTF-8, empty string when unset.
function Item.GetName(record)
    return read_wstring(record, "Name")
end

--- Item description text.
--- @param record integer Item record offset in EE memory.
--- @return string description Description in UTF-8, empty string when unset.
function Item.GetDescription(record)
    return read_wstring(record, "Description")
end

--- Stack amount.
--- @param record integer Item record offset in EE memory.
--- @return integer amount
function Item.GetAmount(record)
    return read_uint(record, "Amount")
end

--- Required level to use the item.
--- @param record integer Item record offset in EE memory.
--- @return integer level_req
function Item.GetLevelReq(record)
    return read_uint(record, "Level Req")
end

--- Weapon range.
--- @param record integer Item record offset in EE memory.
--- @return integer range
function Item.GetRange(record)
    return read_uint(record, "Range")
end

--- Maximum stack size.
--- @param record integer Item record offset in EE memory.
--- @return integer max_stack
function Item.GetMaxStack(record)
    return read_uint(record, "Max Stack")
end

--- Max HP bonus.
--- @param record integer Item record offset in EE memory.
--- @return integer max_hp
function Item.GetMaxHp(record)
    return read_uint(record, "Max HP")
end

--- Durability.
--- @param record integer Item record offset in EE memory.
--- @return integer dur
function Item.GetDur(record)
    return read_uint(record, "Dur")
end

--- Icon resource hash, usable with Icon.GetTexture.
--- The Frontiers icon takes priority when present, matching the game's own draw.
--- @param record integer Item record offset in EE memory.
--- @return integer icon_ref
function Item.GetIconRef(record)
    local frontiers = read_uint(record, "Icon Frontiers")
    if frontiers ~= 0 then
        return frontiers
    end
    return read_uint(record, "Icon")
end

--- Equip state as a string.
--- @param record integer Item record offset in EE memory.
--- @return string status One of "Empty", "Not Equipped", or "Equipped".
function Item.GetEquippedStatus(record)
    -- Empty detection: use Slot ID, not Equipped Flag
    if Item.GetSlotId(record) == 0 then
        return "Empty"
    end

    if is_not_equipped_value(read_uint(record, "Equipped Flag")) then
        return "Not Equipped"
    end

    return "Equipped"
end

-- ===============================
-- Item objects
-- ===============================

local methods = {}

function methods:GetSlotId()         return Item.GetSlotId(self.record) end
function methods:GetName()           return Item.GetName(self.record) end
function methods:GetDescription()    return Item.GetDescription(self.record) end
function methods:GetAmount()         return Item.GetAmount(self.record) end
function methods:GetLevelReq()       return Item.GetLevelReq(self.record) end
function methods:GetRange()          return Item.GetRange(self.record) end
function methods:GetMaxStack()       return Item.GetMaxStack(self.record) end
function methods:GetMaxHp()          return Item.GetMaxHp(self.record) end
function methods:GetDur()            return Item.GetDur(self.record) end
function methods:GetIconRef()        return Item.GetIconRef(self.record) end
function methods:GetEquippedStatus() return Item.GetEquippedStatus(self.record) end

--- True while the record still holds the same item this object was created
--- from. Records shift as items are added/removed, so check this before
--- trusting a held reference.
function methods:IsValid()
    return Item.GetSlotId(self.record) ~= 0 and Item.GetName(self.record) == self._name
end

-- Property access (item.name, item.amount, ...) also reads live memory
local properties = {
    slot            = Item.GetSlotId,
    name            = Item.GetName,
    description     = Item.GetDescription,
    amount          = Item.GetAmount,
    level_req       = Item.GetLevelReq,
    range           = Item.GetRange,
    max_stack       = Item.GetMaxStack,
    max_hp          = Item.GetMaxHp,
    dur             = Item.GetDur,
    icon_ref        = Item.GetIconRef,
    equipped_status = Item.GetEquippedStatus,
    equipped        = function(record) return Item.GetEquippedStatus(record) == "Equipped" end,
}

local item_mt = {
    __index = function(self, key)
        local method = methods[key]
        if method ~= nil then
            return method
        end
        local property = properties[key]
        if property ~= nil then
            return property(self.record)
        end
        return nil
    end,
}

--- Creates an item object backed by a record offset.
--- @param record integer Item record offset in EE memory.
--- @return table item Object with methods (item:GetName() etc.) and live properties (item.name, item.amount, item.icon_ref, ...).
function Item.new(record)
    return setmetatable({
        record = record,
        _name  = Item.GetName(record),
    }, item_mt)
end

return Item
