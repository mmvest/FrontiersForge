local ffi = require("ffi")
local Util = require("frontiers_forge.util")
local Entity = require("frontiers_forge.entity")

local EntityList = {}

-- Re-exported from entity.lua for backwards compatibility.
EntityList.Disposition = Entity.Disposition
EntityList.GetDispositionName = Entity.GetDispositionName

local entity_list_offset = 0x1FB6C30
local entities = ffi.cast("uint32_t*", Util.EEmem() + entity_list_offset)
local min_entity_list_idx = 0  -- 0th index is always the player
local max_entity_list_idx = 23 -- 24 total entities, including the player

--- Returns the entity object at a given entity list slot.
--- Errors when the index is outside the valid range.
--- @param index integer Entity list slot from 0 to 23. Slot 0 is always the player.
--- @return table entity Entity object (see Entity.new) with live methods and properties.
function EntityList.GetEntityByIndex(index)
    if index < min_entity_list_idx or index > max_entity_list_idx then
        error("Index out of bounds: Entity list index must be between " ..min_entity_list_idx.. " and " ..max_entity_list_idx)
    end

    return Entity.new(entities[index])
end

--- Finds the entity with the given entity id.
--- @param target_id integer Entity id to search for.
--- @return table|nil entity Entity table (see GetEntityByIndex), or nil when no entity has that id.
function EntityList.GetEntityById(target_id)
    for index = min_entity_list_idx, max_entity_list_idx do
        local entity = EntityList.GetEntityByIndex(index)
        if entity.id == target_id then
            return entity
        end
    end
    return nil
end

--- Collects every entity whose name matches exactly.
--- @param target_name string Entity name to search for.
--- @return table[]|nil entities Array of entity tables (see GetEntityByIndex), or nil when none match.
function EntityList.GetAllEntitiesWithName(target_name)
    local named_entities = {}

    for index = min_entity_list_idx, max_entity_list_idx do
        local entity = EntityList.GetEntityByIndex(index)
        if entity.name == target_name then
            table.insert( named_entities, entity)
        end
    end

    if #named_entities == 0 then
        return nil
    end

    return named_entities
end

--- Finds the first entity whose name matches exactly.
--- @param target_name string Entity name to search for.
--- @return table|nil entity Entity table (see GetEntityByIndex), or nil when none match.
function EntityList.GetFirstEntityWithName(target_name)

    for index = min_entity_list_idx, max_entity_list_idx do
        local entity = EntityList.GetEntityByIndex(index)
        if entity.name == target_name then
            return entity
        end
    end

    return nil
end

--- Reads every entity list slot.
--- @return table[] entities Array of all 24 entity tables (see GetEntityByIndex), including empty slots.
function EntityList.GetAllEntities()
    local all_entities = {}

    for index = min_entity_list_idx, max_entity_list_idx do
        local entity = EntityList.GetEntityByIndex(index)

        table.insert( all_entities, entity )
    end

    return all_entities
end

return EntityList
