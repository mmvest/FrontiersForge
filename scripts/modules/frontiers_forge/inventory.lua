local ffi  = require("ffi")
local Util = require("frontiers_forge.util")

local Inventory = {}

-- ===============================
-- Constants (LOCAL)
-- ===============================

local PLAYER_OFFSET = 0x1FBBA0C

local STRIDE    = 0x02FC
local NUM_SLOTS = 40

-- Equipped Flag meanings
local U32_NOT_EQUIPPED = 0xFFFFFFFF
local U32_ALT_INVALID  = 429496725  -- fallback

local function is_not_equipped_value(v)
    return v == U32_NOT_EQUIPPED or v == U32_ALT_INVALID
end

-- ===============================
-- Base offsets (slot 1)
-- ===============================

local BASE = {
    ["Slot"]          = 0x0168,
    ["Range"]         = 0x0184,
    ["Level Req"]     = 0x0188,
    ["Max Stack"]     = 0x018C,
    ["Max HP"]        = 0x0190,
    ["Dur"]           = 0x0194,
    ["Name"]          = 0x01B0,  -- UTF-16 string
    ["Amount"]        = 0x0438,  -- uint32
    ["Equipped Flag"] = 0x0444,  -- uint32
}

-- ===============================
-- Precompute per-slot offsets (LOCAL)
-- ===============================

local Offsets = {}
for i = 1, NUM_SLOTS do
    local t = {}
    local add = (i - 1) * STRIDE
    for k, v in pairs(BASE) do
        t[k] = v + add
    end
    Offsets[i] = t
end

local function addr(slot, field)
    return PLAYER_OFFSET + Offsets[slot][field]
end

-- ===============================
-- Internal low-level readers (LOCAL)
-- ===============================

local function read_uint(slot, field, ctype)
    return Util.ReadFromOffset(addr(slot, field), ctype or "uint32_t")
end

local function read_name(slot)
    local wptr = ffi.cast("const wchar_t*", Util.EEmem() + addr(slot, "Name"))
    local s = Util.utf16_to_utf8(wptr)
    if not s or s == "" then return "" end
    return s
end

local function read_amount(slot)
    return read_uint(slot, "Amount", "uint32_t")
end

local function read_slot_id(slot)
    return read_uint(slot, "Slot", "uint32_t")
end

local function read_equipped_status(slot)
    local slot_id = read_slot_id(slot)
    local v       = read_uint(slot, "Equipped Flag", "uint32_t")

    -- Empty detection: use Slot ID, not Equipped Flag
    if slot_id == 0 then
        return "Empty"
    end

    if is_not_equipped_value(v) then
        return "Not Equipped"
    end

    return "Equipped"
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

local function get_slot_label(slot_id)
    local label = SLOT_LABEL[slot_id]
    if not label then return ("Slot " .. tostring(slot_id)) end
    if label == "Weapon" then return "Weapon" end
    return label
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

-- ===============================
-- Public API: GetItems()
-- ===============================

function Inventory.GetItems()
    local items = {}

    local used = Inventory.SlotsUsed() or 0
    if used < 0 then used = 0 end
    if used > NUM_SLOTS then used = NUM_SLOTS end

    for i = 1, used do
        local slot_id = read_slot_id(i)
        if slot_id ~= 0 then
            local name = read_name(i)
            if name ~= "" then
                local equipped_status = read_equipped_status(i)

                items[#items + 1] = {
                    idx             = i,
                    slot            = slot_id,
                    name            = name,
                    amount          = read_amount(i),
                    level_req       = read_uint(i, "Level Req", "uint32_t"),
                    equipped        = (equipped_status == "Equipped"),
                    equipped_status = equipped_status,
                    range           = read_uint(i, "Range", "uint32_t"),
                    max_stack       = read_uint(i, "Max Stack", "uint32_t"),
                    max_hp          = read_uint(i, "Max HP", "uint32_t"),
                    dur             = read_uint(i, "Dur", "uint32_t"),
                }
            end
        end
    end

    return items
end

return Inventory
