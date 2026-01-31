local ffi  = require("ffi")
local Util = require("frontiers_forge.util")

local Bank = {}

-- ===============================
-- Constants (LOCAL)
-- ===============================

local BANK_OFFSET = 0x1FF6AB8

local STRIDE    = 0x02FC
local NUM_SLOTS = 40

-- ===============================
-- Base offsets (slot 1)
-- ===============================

local BASE = {
    ["Slot"]   = 0x0024,
    ["Level"]  = 0x0044,
    ["Name"]   = 0x006C, -- UTF-16 string
    ["Amount"] = 0x02F4, -- uint32
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
    return BANK_OFFSET + Offsets[slot][field]
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

local function read_slot_id(slot)
    return read_uint(slot, "Slot", "uint32_t")
end

local function read_level(slot)
    return read_uint(slot, "Level", "uint32_t")
end

local function read_amount(slot)
    return read_uint(slot, "Amount", "uint32_t")
end

-- ===============================
-- Public API
-- ===============================

function Bank.SlotsUsed()
    return Util.ReadFromOffset(BANK_OFFSET + 0x08, "uint32_t")
end

-- Returns:
-- { idx = i, slot = <slot_id>, level = <level>, name = "...", amount = N }
-- Stops at SlotsUsed (clamped to 40). Skips entries with empty name.
function Bank.GetItems()
    local items = {}

    local used = Bank.SlotsUsed() or 0
    if used < 0 then used = 0 end
    if used > NUM_SLOTS then used = NUM_SLOTS end

    for i = 1, used do
        local name = read_name(i)
        if name ~= "" then
            items[#items + 1] = {
                idx    = i,
                slot   = read_slot_id(i),
                level  = read_level(i),
                name   = name,
                amount = read_amount(i),
            }
        end
    end

    return items
end

return Bank