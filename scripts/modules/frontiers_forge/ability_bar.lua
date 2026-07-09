local Util = require("frontiers_forge.util")
local AbilityList = require("frontiers_forge.ability_list")
local ffi = require("ffi")

-- Note that source_index is the RAW index into the ability list's record array.
-- Index 0 is the list's null sentinel, so real abilities are always index >= 1.
ffi.cdef[[
    typedef struct {
        int32_t  unknown_00;        // +0x00  always -1
        int32_t  ability_icon_ref;  // +0x04  icon foreground resource hash (copied from ability +0x40), -1 if empty
        int32_t  overlay_icon_ref;  // +0x08  0x3d dim overlay when the ability is on cooldown
                                    //        (ability cooldown_lockout_ms > 0), else -1
        int32_t  unknown_0C;        // +0x0C  always -1
        int32_t  unknown_10;        // +0x10  always -1
        uint32_t unknown_14;        // +0x14  always 0
        uint32_t source_type;       // +0x18  type tag: 0x8060000 = ability list, 0x2030000 = different container, 0 = empty
        uint32_t source_index;      // +0x1C  raw index into the ability list array
    } AbilityBarSlot;
]]

local ABILITY_SOURCE_TAG = 0x8060000

local AbilityBarSlot = {}
AbilityBarSlot.__index = AbilityBarSlot

function AbilityBarSlot.new(address)
    if type(address) == "number" then
        address = ffi.cast("AbilityBarSlot*", address)
    elseif not ffi.istype("AbilityBarSlot*", address) then
        error("Invalid pointer type for AbilityBarSlot")
    end

    local self = setmetatable({}, AbilityBarSlot)
    self.ptr = address  -- Store the FFI pointer
    return self
end

--- @return boolean empty True when nothing is assigned to this slot.
function AbilityBarSlot:IsEmpty()
    return self.ptr.source_type == 0
end

--- Raw ability list index this slot points at.
--- @return integer|nil index Raw index into the ability list, or nil when the slot does not reference the ability list.
function AbilityBarSlot:GetAbilityIndex()
    if self.ptr.source_type ~= ABILITY_SOURCE_TAG then
        return nil
    end
    return self.ptr.source_index
end

--- Resolves the slot into a full Ability object.
--- @return table|nil ability Ability object for this slot, or nil when the slot is empty or not ability sourced.
function AbilityBarSlot:GetAbility()
    local ability_index = self:GetAbilityIndex()
    if ability_index and ability_index >= 1 then
        return AbilityList.GetAbilityByIndex(ability_index)
    end
    return nil
end

--- @return integer icon_ref Icon reference drawn in this slot, or -1 when empty.
function AbilityBarSlot:GetIconRef()
    return self.ptr.ability_icon_ref
end

local AbilityBar = {}
AbilityBar.__index = AbilityBar

AbilityBar.num_bars = 3
AbilityBar.slot_size = 0x20         -- 32 bytes

local FOCUSED_WINDOW_PTR_OFFSET = 0x4E37F4
local bar_window_offsets = { [0] = 0x6B0, [1] = 0x6B4, [2] = 0x6B8 }

-- Resolves the offset of a bar's config block, or nil if the UI windows
-- aren't loaded yet (e.g. not in game).
local function GetBarConfigOffset(bar_index)
    if bar_index < 0 or bar_index >= AbilityBar.num_bars then
        error("Invalid bar index: " .. tostring(bar_index))
    end

    local config_offset = Util.ReadFromPointerChain(FOCUSED_WINDOW_PTR_OFFSET, {0x14, bar_window_offsets[bar_index], 0x24}, "uint32_t", 0)
    if config_offset == 0 then
        return nil
    end
    return config_offset
end

--- Number of slots currently on a bar.
--- @param bar_index integer Bar index from 0 to AbilityBar.num_bars - 1.
--- @return integer count Live slot count, or 0 when the UI windows are not loaded (e.g. not in game).
function AbilityBar.GetSlotCount(bar_index)
    local config = GetBarConfigOffset(bar_index)
    if config == nil then
        return 0
    end
    return Util.ReadFromOffset(config + 0xC, "uint32_t")
end

--- Get a slot object from a bar.
--- @param bar_index integer Bar index from 0 to AbilityBar.num_bars - 1.
--- @param slot_index integer Slot index from 0 to GetSlotCount(bar_index) - 1.
--- @return table|nil slot AbilityBarSlot object, or nil when the UI windows are not loaded.
function AbilityBar.GetAbilitySlot(bar_index, slot_index)
    local config = GetBarConfigOffset(bar_index)
    if config == nil then
        return nil
    end
    if slot_index < 0 or slot_index >= AbilityBar.GetSlotCount(bar_index) then
        error("Invalid slot index: " .. tostring(slot_index))
    end

    local slots_offset = Util.ReadFromOffset(config + 0x8, "uint32_t")
    local slot_address = Util.EEmem() + slots_offset + (AbilityBar.slot_size * slot_index)

    return AbilityBarSlot.new(slot_address)
end

--- Convenience wrapper resolving a bar slot straight to an Ability object.
--- @param bar_index integer Bar index from 0 to AbilityBar.num_bars - 1.
--- @param slot_index integer Slot index from 0 to GetSlotCount(bar_index) - 1.
--- @return table|nil ability Ability object, or nil when the slot is empty, not ability sourced, or the UI is not loaded.
function AbilityBar.GetAbility(bar_index, slot_index)
    local slot = AbilityBar.GetAbilitySlot(bar_index, slot_index)
    if slot == nil then
        return nil
    end
    return slot:GetAbility()
end

return AbilityBar
