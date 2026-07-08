local ffi = require("ffi")
local Util = require("frontiers_forge.util")

local EntityList = {}

-- Disposition values, drawn next to the target's health bar.
-- The value is a 0-6 scale sent by the server (opcode 0x10) when you target
-- an entity. The game seems to bucket it into one of three face icons:
--   0-1 -> icon 0x73 (red frowny face, hostile)
--   2-3 -> icon 0x74 (white neutral face)
--   4-6 -> icon 0x75 (blue smiley face, friendly)
-- My in-game testing has only ever shown values 0, 2, and 4. The server may use just
-- one even value per bucket. The ranges above match the game's own switch, so
-- odd values are still bucketed correctly if they ever appear.
-- The server only sends this for the CURRENTLY TARGETED entity, and
-- the client caches just that one value (client singleton +0x2BB6C, valid flag
-- +0x2BB64, cleared on retarget). So essentially disposition is only known for the
-- current target and for every other entity it is nil.
EntityList.Disposition = {
    HOSTILE_MIN  = 0,
    HOSTILE_MAX  = 1,
    NEUTRAL_MIN  = 2,
    NEUTRAL_MAX  = 3,
    FRIENDLY_MIN = 4,
    FRIENDLY_MAX = 6,
}

-- The static pointer at 0x4E37F0 points at the client singleton + 4, so each
-- singleton-relative offset below is a single chain step of (offset - 4).
--
-- Note the game never stores WHICH entity the cached disposition belongs to —
-- selecting a new target clears the valid flag and the server's 0x10 response
-- refills the cache, so a set flag always means "this is the current target's
-- info". (Singleton+0x2BB68 is a request token echoed by the server as a
-- stale-response guard, NOT an entity id.) We therefore pair the cached
-- disposition with the current target id at singleton+0xC140.
local GUI_CONTEXT_PTR_OFFSET  = 0x4E37F0
local TARGET_INFO_VALID_STEP  = 0x2BB60 -- singleton+0x2BB64: nonzero when the cache is valid
local TARGET_ENTITY_ID_STEP   = 0xC13C  -- singleton+0xC140: current target entity id
local TARGET_DISPOSITION_STEP = 0x2BB68 -- singleton+0x2BB6C: disposition 0-6

-- Returns the current target's entity id and its disposition, or nil, nil when
-- no valid target info is cached (nothing targeted / not in game).
local function GetTargetDisposition()
    if Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {TARGET_INFO_VALID_STEP}, "uint32_t", 0) == 0 then
        return nil, nil
    end
    local target_id   = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {TARGET_ENTITY_ID_STEP}, "uint32_t", nil)
    local disposition = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {TARGET_DISPOSITION_STEP}, "uint32_t", nil)
    return target_id, disposition
end

--- Buckets a disposition value into the same three categories the game uses
--- to pick the face icon.
--- @param disposition integer|nil Disposition value from 0 to 6, or nil.
--- @return string name One of "Hostile", "Neutral", "Friendly", or "Unknown" for nil and out of range values.
function EntityList.GetDispositionName(disposition)
    if disposition == nil then
        return "Unknown"
    end
    if disposition >= EntityList.Disposition.HOSTILE_MIN and disposition <= EntityList.Disposition.HOSTILE_MAX then
        return "Hostile"
    end
    if disposition >= EntityList.Disposition.NEUTRAL_MIN and disposition <= EntityList.Disposition.NEUTRAL_MAX then
        return "Neutral"
    end
    if disposition >= EntityList.Disposition.FRIENDLY_MIN and disposition <= EntityList.Disposition.FRIENDLY_MAX then
        return "Friendly"
    end
    return "Unknown"
end

local entity_list_offset = 0x1FB6C30
local entities = ffi.cast("uint32_t*", Util.EEmem() + entity_list_offset)
local min_entity_list_idx = 0  -- 0th index is always the player
local max_entity_list_idx = 23 -- 24 total entities, including the player

--- Reads the entity record at a given entity list slot.
--- Errors when the index is outside the valid range.
--- @param index integer Entity list slot from 0 to 23. Slot 0 is always the player.
--- @return table entity Table with fields id, percent_hp, x, y, z, name, level, target_id, disposition, and disposition_name.
function EntityList.GetEntityByIndex(index)
    if index < min_entity_list_idx or index > max_entity_list_idx then
        error("Index out of bounds: Entity list index must be between " ..min_entity_list_idx.. " and " ..max_entity_list_idx)
    end

    -- Entity ID
    local id = Util.ReadFromOffset(entities[index] + 0x0C, "uint32_t")
    local percent_hp = Util.ReadFromOffset(entities[index] + 0x19, "uint8_t") / 0xFF

    -- Entity Coordinates
    local coordinate_addr = Util.EEmem() + entities[index] + 0x40
    local float_ptr = ffi.cast("float*", coordinate_addr)

    local x = float_ptr[0]
    local y = float_ptr[1]
    local z = float_ptr[2]

    -- Entity Name
    local name_addr = Util.EEmem() + entities[index] + 0x58
    local name_ptr = ffi.cast("char*", name_addr)
    local name = ffi.string(name_ptr)

    -- Entity Level
    local level = Util.ReadFromOffset(entities[index] + 0x70, "uint8_t")

    -- Target of entity
    local target_id = Util.ReadFromOffset(entities[index] + 0x74, "uint8_t")

    -- Disposition towards the player. Only known when this entity is the current target,
    -- nil otherwise. disposition_name is always set ("Unknown" when nil).
    local disposition = nil
    local cached_target_id, cached_disposition = GetTargetDisposition()
    if cached_target_id ~= nil and cached_target_id == id then
        disposition = cached_disposition
    end

    return { id = id, percent_hp = percent_hp, x = x, y = y, z = z, name = name, level = level, target_id = target_id,
             disposition = disposition, disposition_name = EntityList.GetDispositionName(disposition)}
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