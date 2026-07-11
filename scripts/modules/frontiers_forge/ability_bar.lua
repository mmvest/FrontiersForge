local Util = require("frontiers_forge.util")
local AbilityList = require("frontiers_forge.ability_list")
local Item = require("frontiers_forge.item")
local ffi = require("ffi")

-- Note that source_index is the RAW index into the source container. For the
-- ability list, index 0 is the list's null sentinel, so real abilities are
-- always index >= 1. For item slots it is a zero based index into the item
-- record array.
ffi.cdef[[
    typedef struct {
        int32_t  unknown_00;        // +0x00  always -1
        int32_t  ability_icon_ref;  // +0x04  icon foreground resource hash (copied from ability +0x40), -1 if empty
        int32_t  overlay_icon_ref;  // +0x08  0x3d dim overlay when the ability is on cooldown
                                    //        (ability cooldown_lockout_ms > 0), else -1
        int32_t  unknown_0C;        // +0x0C  always -1
        int32_t  unknown_10;        // +0x10  always -1
        uint32_t unknown_14;        // +0x14  always 0
        uint32_t source_type;       // +0x18  type tag: 0x8060000 = ability list, 0x2030000 = item records, 0 = empty
        uint32_t source_index;      // +0x1C  raw index into the source container
    } AbilityBarSlot;
]]

local ABILITY_SOURCE_TAG = 0x8060000
local ITEM_SOURCE_TAG    = 0x2030000

-- Item slots index the player's item record array, the same records the
-- inventory reads. UI_GetSlotSourceName (0x6266e8) resolves them as
-- singleton + 0xC428 + 8 + index * 0x2FC.
local ITEM_RECORDS_BASE = 0x1FAF730 + 0xC428 + 8
local ITEM_RECORD_STRIDE = 0x2FC
local MAX_ITEM_RECORDS = 40

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

--- Raw item record index this slot points at.
--- @return integer|nil index Zero based index into the item records, or nil when the slot is not item sourced.
function AbilityBarSlot:GetItemIndex()
    if self.ptr.source_type ~= ITEM_SOURCE_TAG then
        return nil
    end
    return self.ptr.source_index
end

--- Resolves the slot into a full Item object, for the item hotbar's slots.
--- @return table|nil item Item object for this slot, or nil when the slot is empty or not item sourced.
function AbilityBarSlot:GetItem()
    local item_index = self:GetItemIndex()
    if item_index == nil or item_index >= MAX_ITEM_RECORDS then
        return nil
    end
    local record = ITEM_RECORDS_BASE + item_index * ITEM_RECORD_STRIDE
    -- An empty record has slot id 0, so a stale index resolves to nothing
    -- rather than to a blank item.
    if Item.GetSlotId(record) == 0 then
        return nil
    end
    return Item.new(record)
end

--- @return integer icon_ref Icon reference drawn in this slot, or -1 when empty.
function AbilityBarSlot:GetIconRef()
    return self.ptr.ability_icon_ref
end

local AbilityBar = {}
AbilityBar.__index = AbilityBar

AbilityBar.num_bars = 3
AbilityBar.slot_size = 0x20         -- 32 bytes

local bar_window_offsets = { [0] = 0x6B0, [1] = 0x6B4, [2] = 0x6B8 }

local MAX_SLOT_COUNT = 5

-- Resolves the game-UI root window. Returns nil when the UI is not loaded or a
-- read fails validation.
local function GetGameUIRootOffset()
    if Util.IsInGame() == 0 then
        return nil
    end
    local root = Util.ReadFromPointerChain(0x4E37F0, {0x2BB74}, "uint32_t", 0)
    if not Util.IsValidEEPointer(root) or root + 0x720 > Util.EE_RAM_SIZE then
        return nil
    end
    return root
end

-- Resolves a bar's VIWndHUDMenu window, or nil when unavailable.
local function GetBarWindowOffset(bar_index)
    if bar_index < 0 or bar_index >= AbilityBar.num_bars then
        error("Invalid bar index: " .. tostring(bar_index))
    end
    local root = GetGameUIRootOffset()
    if root == nil then
        return nil
    end
    local bar_window = Util.ReadFromOffset(root + bar_window_offsets[bar_index], "uint32_t")
    if not Util.IsValidEEPointer(bar_window) or bar_window + 0x1D0 > Util.EE_RAM_SIZE then
        return nil
    end
    if Util.ReadFromOffset(bar_window + 0x28, "uint32_t") ~= bar_index then
        return nil
    end
    return bar_window
end

-- Resolves the offset of a bar's config block, or nil when unavailable.
local function GetBarConfigOffset(bar_index)
    local bar_window = GetBarWindowOffset(bar_index)
    if bar_window == nil then
        return nil
    end
    local config_offset = Util.ReadFromOffset(bar_window + 0x24, "uint32_t")
    if not Util.IsValidEEPointer(config_offset) then
        return nil
    end
    return config_offset
end

--- Index of the hotbar the player currently has selected.
--- @return integer|nil bar_index Bar index from 0 to AbilityBar.num_bars - 1, or nil when the UI is not loaded.
function AbilityBar.GetSelectedBarIndex()
    local root = GetGameUIRootOffset()
    if root == nil then
        return nil
    end
    local index = Util.ReadFromOffset(root + 0x54, "uint32_t")
    if index >= AbilityBar.num_bars then
        return nil
    end
    return index
end

--- Slot the player currently has selected on a bar.
--- @param bar_index integer Bar index from 0 to AbilityBar.num_bars - 1.
--- @return integer|nil slot_index Slot index from 0 to GetSlotCount(bar_index) - 1, or nil when the UI is not loaded.
function AbilityBar.GetSelectedSlotIndex(bar_index)
    local bar_window = GetBarWindowOffset(bar_index)
    if bar_window == nil then
        return nil
    end
    local slot_index = Util.ReadFromOffset(bar_window + 0x1C8, "uint32_t")
    if slot_index > MAX_SLOT_COUNT then
        return nil
    end
    return slot_index
end

-- Slide sources, identical to chat.lua / combat.lua / input.lua.
local WND_GAME_STATIC_PTR  = 0x14E200
local WND_GAME_DRAW_STEPS  = { 0x190, 0x53C, 0x20, 0x1C }
local WND_GAME_DRAW_STATIC = 0x006AD8D8

-- The compact hotbar draw pulls each slot's glyph from a static texture id table
-- (0x7466E0 in the dump), indexed by slot position — not from the slot data.
local SLOT_GLYPH_TABLE_STATIC = 0x7466E0

--- Built-in UI texture id of a slot position's glyph (what the compact HUD draws
--- in that slot, e.g. the special-items bar's bottle/gem/sword icons).
--- Resolve it to a texture with Icon.GetUITexture.
--- @param slot_index integer Slot index from 0 to MAX_SLOT_COUNT - 1.
--- @return integer|nil tex_id UI texture id, or nil when the UI is not loaded.
function AbilityBar.GetSlotUITexId(slot_index)
    if slot_index < 0 or slot_index >= MAX_SLOT_COUNT then
        error("Invalid slot index: " .. tostring(slot_index))
    end
    local draw_ptr_offset = Util.GetOffsetFromPointerChain(WND_GAME_STATIC_PTR, WND_GAME_DRAW_STEPS)
    if draw_ptr_offset == nil then
        return nil
    end
    local draw_runtime = Util.ReadFromOffset(draw_ptr_offset, "uint32_t")
    if not Util.IsValidEEPointer(draw_runtime) then
        return nil
    end
    local table_offset = SLOT_GLYPH_TABLE_STATIC + (draw_runtime - WND_GAME_DRAW_STATIC)
    if not Util.IsValidEEPointer(table_offset) then
        return nil
    end
    return Util.ReadFromOffset(table_offset + slot_index * 4, "uint32_t")
end

--- Number of slots currently on a bar.
--- @param bar_index integer Bar index from 0 to AbilityBar.num_bars - 1.
--- @return integer count Live slot count, or 0 when the UI windows are not loaded (e.g. not in game).
function AbilityBar.GetSlotCount(bar_index)
    local config = GetBarConfigOffset(bar_index)
    if config == nil then
        return 0
    end
    local count = Util.ReadFromOffset(config + 0xC, "uint32_t")
    if count > MAX_SLOT_COUNT then
        return 0
    end
    return count
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
    local slot_offset = slots_offset + (AbilityBar.slot_size * slot_index)
    if not Util.IsValidEEPointer(slots_offset)
        or slot_offset + AbilityBar.slot_size > Util.EE_RAM_SIZE then
        return nil
    end

    return AbilityBarSlot.new(Util.EEmem() + slot_offset)
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

--- Convenience wrapper resolving a bar slot straight to an Item object, for the
--- item hotbar's slots.
--- @param bar_index integer Bar index from 0 to AbilityBar.num_bars - 1.
--- @param slot_index integer Slot index from 0 to GetSlotCount(bar_index) - 1.
--- @return table|nil item Item object, or nil when the slot is empty, not item sourced, or the UI is not loaded.
function AbilityBar.GetItem(bar_index, slot_index)
    local slot = AbilityBar.GetAbilitySlot(bar_index, slot_index)
    if slot == nil then
        return nil
    end
    return slot:GetItem()
end

return AbilityBar
