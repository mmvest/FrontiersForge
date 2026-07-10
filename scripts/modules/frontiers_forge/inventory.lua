local Util = require("frontiers_forge.util")
local Item = require("frontiers_forge.item")

local Inventory = {}

-- ===============================
-- Constants (LOCAL)
-- ===============================

local PLAYER_OFFSET = 0x1FBBA0C

-- Item records start at PLAYER_OFFSET + 0x154, per-field reads live in item.lua
local RECORD_BASE = PLAYER_OFFSET + 0x154
local STRIDE      = 0x02FC
local NUM_SLOTS   = 40

Inventory.max_slots = NUM_SLOTS

local function record_offset(slot)
    return RECORD_BASE + (slot - 1) * STRIDE
end

-- ===============================
-- Slot translation + ordering (PUBLIC)
-- ===============================

local SLOT_LABEL = {
    [1]  = "Head",
    [2]  = "Robe",
    [3]  = "Earring",
    [4]  = "Neck",
    [5]  = "Torso",
    [6]  = "Bracelet",
    [7]  = "2 Forearm",
    [8]  = "Ring",
    [9]  = "Waist",
    [10] = "Legs",
    [11] = "Boots",
    [12] = "Weapon",
    [13] = "Shield",
    [14] = "Weapon",
    [15] = "Weapon",
    [16] = "Weapon",
    [17] = "Weapon",
    [18] = "Weapon",
    [19] = "Gloves",
}

-- Returns: (label, order_key)
function Inventory.GetSlotLabelAndOrder(slot_id)
    local base = SLOT_LABEL[slot_id]
    if not base then
        return ("Slot " .. tostring(slot_id)), 9999
    end

    if base == "Weapon" then return "Weapon", 1 end
    if base == "Shield" then return "Shield", 2 end
    if base == "Head" then return "Head", 3 end
    if base == "Robe" then return "Robe", 4 end
    if base == "Torso" then return "Torso", 5 end
    if base == "Waist" then return "Waist", 6 end
    if base == "Gloves" then return "Gloves", 7 end
    if base == "2 Forearm" then return "2 Forearm", 8 end
    if base == "Bracelet" then return "Bracelet", 9 end
    if base == "Legs" then return "Legs", 10 end
    if base == "Boots" then return "Boots", 11 end
    if base == "Neck" then return "Neck", 12 end
    if base == "Earring" then return "Earring", 13 end
    if base == "Ring" then return "Ring", 14 end

    return base, 999
end

-- ===============================
-- Inventory metadata (PUBLIC)
-- ===============================

function Inventory.GetTunar()
    return Util.ReadFromOffset(PLAYER_OFFSET + 0x0034, "uint32_t")
end

function Inventory.InventoryUsed()
    return Util.ReadFromOffset(PLAYER_OFFSET + 0x014C, "uint32_t")
end

-- Bank-style alias
function Inventory.SlotsUsed()
    return Inventory.InventoryUsed()
end

--- Number of free inventory slots.
--- @return integer remaining Slots left from 0 to max_slots.
function Inventory.SlotsRemaining()
    local used = Inventory.SlotsUsed() or 0
    if used < 0 then used = 0 end
    if used > NUM_SLOTS then used = NUM_SLOTS end
    return NUM_SLOTS - used
end

--- Icon resource hash for an inventory slot, usable with Icon.GetTexture.
--- @param slot integer Inventory index from 1 to 40 (same idx as GetItems entries).
--- @return integer|nil icon_ref Icon hash, or nil when the slot is empty or out of range.
function Inventory.GetIconRef(slot)
    if slot < 1 or slot > NUM_SLOTS then
        return nil
    end
    local record = record_offset(slot)
    if Item.GetSlotId(record) == 0 then
        return nil
    end
    return Item.GetIconRef(record)
end

--- Item object for one inventory slot (see Item.new), with idx set.
--- @param slot integer Inventory index from 1 to 40.
--- @return table|nil item Item object with live methods and properties, or nil when the slot is empty or out of range.
function Inventory.GetItem(slot)
    if slot < 1 or slot > NUM_SLOTS then
        return nil
    end
    local record = record_offset(slot)
    if Item.GetSlotId(record) == 0 or Item.GetName(record) == "" then
        return nil
    end
    local item = Item.new(record)
    item.idx = slot
    return item
end

-- ===============================
-- Public API: GetItems()
-- ===============================

function Inventory.GetItems()
    local items = {}

    local used = Inventory.SlotsUsed() or 0
    if used < 0 then used = 0 end
    if used > NUM_SLOTS then used = NUM_SLOTS end

    for i = 1, used do
        local item = Inventory.GetItem(i)
        if item ~= nil then
            items[#items + 1] = item
        end
    end

    return items
end

return Inventory
