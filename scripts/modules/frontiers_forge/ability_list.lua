local Util = require("frontiers_forge.util")
local Ability = require("frontiers_forge.ability")

-- The player's ability list is owned by the client-state singleton. Rather
-- than hardcoding the singleton's address, we resolve it the same way the
-- game does: the static pointer at 0x4E37F0 (VIWnd's GUI-context pointer) points at singleton + 4.
-- Relative to the singleton:
--   +0x2BB2C = entry count, INCLUDING the index-0 sentinel
--   +0x2BB34 = pointer to the record array (stride 0x1D8)
--   +0x2BB38 = index of the binary-search-tree root
--
-- Records double as tree nodes linked by index (see ability.lua); index 0 is a
-- null sentinel, so real abilities occupy indices 1 .. count-1.
local AbilityList = {}

local GUI_CONTEXT_PTR_OFFSET = 0x4E37F0

local function GetCountOffset()
    return Util.GetOffsetFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB28})
end

local function GetRootIdxOffset()
    return Util.GetOffsetFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB34})
end

local function GetBaseOffset()
    local base_ptr_offset = Util.GetOffsetFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB30})
    return Util.ReadFromOffset(base_ptr_offset, "uint32_t")
end

-- Number of real abilities (we exclude the 0 sentinel)
function AbilityList.GetCount()
    local count = Util.ReadFromOffset(GetCountOffset(), "uint32_t")
    if count == 0 then
        return 0
    end
    return count - 1
end

-- Get the ability record at a raw array index. Index 0 is the sentinel; real
-- abilities live at indices 1 .. GetCount(). This raw index is the same one
-- the game stores in hotbar slots (see ability_bar.lua).
function AbilityList.GetAbilityByIndex(index)
    if index < 1 or index > AbilityList.GetCount() then
        return nil
    end
    local address = Util.EEmem() + GetBaseOffset() + (index * Ability.size)
    return Ability.new(address)
end

-- Tree traversal
local function LeftmostFrom(index)
    while true do
        local node = AbilityList.GetAbilityByIndex(index)
        local left = node.ptr.left_index
        if left == 0 then
            return index
        end
        index = left
    end
end

local function NextIndex(index)
    local node = AbilityList.GetAbilityByIndex(index)
    local right = node.ptr.right_index
    if right ~= 0 then
        return LeftmostFrom(right)
    end

    -- No right subtree so climb until we come up from a left child
    local parent = node.ptr.parent_index
    while parent ~= 0 do
        local parent_node = AbilityList.GetAbilityByIndex(parent)
        if parent_node.ptr.left_index == index then
            return parent
        end
        index = parent
        parent = parent_node.ptr.parent_index
    end
    return 0
end

-- Iterator over all abilities in id-sorted (in-order tree) order
function AbilityList.Abilities()
    local next_idx = 0
    if AbilityList.GetCount() > 0 then
        local root = Util.ReadFromOffset(GetRootIdxOffset(), "uint32_t")
        if root ~= 0 then
            next_idx = LeftmostFrom(root)
        end
    end

    return function()
        if next_idx == 0 then
            return nil
        end
        local idx = next_idx
        next_idx = NextIndex(idx)
        return idx, AbilityList.GetAbilityByIndex(idx)
    end
end

-- Find an ability by its id.
function AbilityList.GetAbilityById(id)
    for _, ability in AbilityList.Abilities() do
        if ability:GetId() == id then
            return ability
        end
    end
    return nil
end

return AbilityList
