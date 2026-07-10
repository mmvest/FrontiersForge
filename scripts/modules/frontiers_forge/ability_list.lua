local Util = require("frontiers_forge.util")
local Ability = require("frontiers_forge.ability")

-- The ability list is owned by the client-state singleton, resolved through the
-- static pointer at 0x4E37F0 which points at singleton + 4 (so each chain step is
-- offset - 4). The records double as binary-search-tree nodes linked by index,
-- with index 0 a null sentinel, so real abilities occupy indices 1 .. count-1.
local AbilityList = {}

local GUI_CONTEXT_PTR_OFFSET = 0x4E37F0

-- Base address of the record array, or nil if the ability list isn't loaded.
local function GetBaseOffset()
    return Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB30}, "uint32_t", nil)
end

--- Number of real abilities (excluding the 0 sentinel).
--- @return integer count Ability count, or 0 when the list is not loaded (e.g. not in game).
function AbilityList.GetCount()
    local count = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB28}, "uint32_t", 0)
    if count == 0 then
        return 0
    end
    return count - 1
end

--- Get the ability record at a raw array index. Index 0 is the sentinel. Real
--- abilities live at indices 1 .. GetCount(). This raw index is the same one
--- the game stores in hotbar slots (see ability_bar.lua).
--- @param index integer Raw index into the record array, valid from 1 to GetCount().
--- @return table|nil ability Ability object, or nil when the index is out of range or the list is not loaded.
function AbilityList.GetAbilityByIndex(index)
    if index < 1 or index > AbilityList.GetCount() then
        return nil
    end
    local base = GetBaseOffset()
    if base == nil or not Util.IsValidEEPointer(base) then
        return nil
    end
    local record_offset = base + (index * Ability.size)
    if record_offset + Ability.size > Util.EE_RAM_SIZE then
        return nil
    end
    return Ability.new(Util.EEmem() + record_offset)
end

-- Tree traversal. Both helpers treat an unresolvable node (list unloaded, or
-- a link index outside the valid range) as end-of-traversal (0) rather than
-- crashing on a nil node.
local function LeftmostFrom(index)
    while true do
        local node = AbilityList.GetAbilityByIndex(index)
        if node == nil then
            return 0
        end
        local left = node.ptr.left_index
        if left == 0 then
            return index
        end
        index = left
    end
end

local function NextIndex(index)
    local node = AbilityList.GetAbilityByIndex(index)
    if node == nil then
        return 0
    end
    local right = node.ptr.right_index
    if right ~= 0 then
        return LeftmostFrom(right)
    end

    -- No right subtree so climb until we come up from a left child
    local parent = node.ptr.parent_index
    while parent ~= 0 do
        local parent_node = AbilityList.GetAbilityByIndex(parent)
        if parent_node == nil then
            return 0
        end
        if parent_node.ptr.left_index == index then
            return parent
        end
        index = parent
        parent = parent_node.ptr.parent_index
    end
    return 0
end

--- Iterator over all abilities in id-sorted (in-order tree) order.
--- Usage looks like `for index, ability in AbilityList.Abilities() do ... end`.
--- @return function iterator Iterator producing raw index and Ability object pairs.
function AbilityList.Abilities()
    local next_idx = 0
    if AbilityList.GetCount() > 0 then
        local root = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {0x2BB34}, "uint32_t", 0)
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
        local ability = AbilityList.GetAbilityByIndex(idx)
        -- If the record became unreachable mid-iteration (e.g. list unloaded),
        -- end the loop instead of yielding a nil ability.
        if ability == nil then
            return nil
        end
        return idx, ability
    end
end

--- Find an ability by its id.
--- @param id integer The ability id to search for.
--- @return table|nil ability Matching Ability object, or nil if not found.
function AbilityList.GetAbilityById(id)
    for _, ability in AbilityList.Abilities() do
        if ability:GetId() == id then
            return ability
        end
    end
    return nil
end

return AbilityList
