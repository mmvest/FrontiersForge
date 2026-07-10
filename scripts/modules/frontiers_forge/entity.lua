local ffi  = require("ffi")
local Util = require("frontiers_forge.util")

-- You may see a term that I call a "record". This is the byte offset of an
-- entity's data block from the start of EE RAM. Essentially reads look like
-- EEmem + record + field.
local Entity = {}

-- Disposition is a 0-6 scale the game buckets into hostile (0-1), neutral (2-3),
-- and friendly (4-6). It is only known for the current target, nil otherwise.
Entity.Disposition = {
    HOSTILE_MIN  = 0,
    HOSTILE_MAX  = 1,
    NEUTRAL_MIN  = 2,
    NEUTRAL_MAX  = 3,
    FRIENDLY_MIN = 4,
    FRIENDLY_MAX = 6,
}

-- The static pointer at 0x4E37F0 points at the client singleton + 4, so each
-- singleton-relative offset below is a single chain step of (offset - 4). The
-- cached disposition has no entity id of its own, so it is paired with the
-- current target id at singleton+0xC140.
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
function Entity.GetDispositionName(disposition)
    if disposition == nil then
        return "Unknown"
    end
    if disposition >= Entity.Disposition.HOSTILE_MIN and disposition <= Entity.Disposition.HOSTILE_MAX then
        return "Hostile"
    end
    if disposition >= Entity.Disposition.NEUTRAL_MIN and disposition <= Entity.Disposition.NEUTRAL_MAX then
        return "Neutral"
    end
    if disposition >= Entity.Disposition.FRIENDLY_MIN and disposition <= Entity.Disposition.FRIENDLY_MAX then
        return "Friendly"
    end
    return "Unknown"
end

-- ===============================
-- Field getters (record offset in)
-- ===============================

--- Entity id.
--- @param record integer Entity record offset in EE memory.
--- @return integer id
function Entity.GetId(record)
    return Util.ReadFromOffset(record + 0x0C, "uint32_t")
end

--- Health as a fraction from 0.0 to 1.0.
--- @param record integer Entity record offset in EE memory.
--- @return number percent_hp
function Entity.GetHealthPercent(record)
    return Util.ReadFromOffset(record + 0x19, "uint8_t") / 0xFF
end

--- World position.
--- @param record integer Entity record offset in EE memory.
--- @return number x, number y, number z
function Entity.GetPosition(record)
    local float_ptr = ffi.cast("float*", Util.EEmem() + record + 0x40)
    return float_ptr[0], float_ptr[1], float_ptr[2]
end

--- Entity name.
--- @param record integer Entity record offset in EE memory.
--- @return string name
function Entity.GetName(record)
    return ffi.string(ffi.cast("char*", Util.EEmem() + record + 0x58))
end

--- Entity level.
--- @param record integer Entity record offset in EE memory.
--- @return integer level
function Entity.GetLevel(record)
    return Util.ReadFromOffset(record + 0x70, "uint8_t")
end

--- Straight line 3D distance from this entity to a world point.
--- @param record integer Entity record offset in EE memory.
--- @param x number World x of the other point.
--- @param y number World y of the other point.
--- @param z number World z of the other point.
--- @return number distance
function Entity.GetDistanceTo(record, x, y, z)
    local ex, ey, ez = Entity.GetPosition(record)
    local dx, dy, dz = ex - x, ey - y, ez - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Id of the entity this entity is targeting.
--- @param record integer Entity record offset in EE memory.
--- @return integer target_id
function Entity.GetTargetId(record)
    return Util.ReadFromOffset(record + 0x74, "uint8_t")
end

--- Disposition towards the player. Only known when this entity is the
--- current target, nil otherwise.
--- @param record integer Entity record offset in EE memory.
--- @return integer|nil disposition
function Entity.GetDisposition(record)
    local cached_target_id, cached_disposition = GetTargetDisposition()
    if cached_target_id ~= nil and cached_target_id == Entity.GetId(record) then
        return cached_disposition
    end
    return nil
end

-- ===============================
-- Entity objects
-- ===============================

local methods = {}

function methods:GetId()            return Entity.GetId(self.record) end
function methods:GetHealthPercent() return Entity.GetHealthPercent(self.record) end
function methods:GetPosition()      return Entity.GetPosition(self.record) end
function methods:GetName()          return Entity.GetName(self.record) end
function methods:GetLevel()         return Entity.GetLevel(self.record) end
function methods:GetTargetId()      return Entity.GetTargetId(self.record) end
function methods:GetDistanceTo(x, y, z) return Entity.GetDistanceTo(self.record, x, y, z) end
function methods:GetDisposition()   return Entity.GetDisposition(self.record) end

--- True while the record still holds the same entity this object was created
--- from. Slots are reused on spawn/despawn, so check this before trusting a
--- held reference.
function methods:IsValid()
    return Entity.GetId(self.record) == self._id
end

-- Property access (entity.name, entity.level, ...) also reads live memory
local properties = {
    id               = Entity.GetId,
    percent_hp       = Entity.GetHealthPercent,
    name             = Entity.GetName,
    level            = Entity.GetLevel,
    target_id        = Entity.GetTargetId,
    disposition      = Entity.GetDisposition,
    x                = function(record) return (Entity.GetPosition(record)) end,
    y                = function(record) local _, y = Entity.GetPosition(record) return y end,
    z                = function(record) local _, _, z = Entity.GetPosition(record) return z end,
    disposition_name = function(record) return Entity.GetDispositionName(Entity.GetDisposition(record)) end,
}

local entity_mt = {
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

--- Creates an entity object backed by a record offset.
--- @param record integer Entity record offset in EE memory.
--- @return table entity Object with methods (entity:GetName() etc.) and live properties (entity.name, entity.level, entity.x, ...).
function Entity.new(record)
    return setmetatable({
        record = record,
        _id    = Entity.GetId(record),
    }, entity_mt)
end

return Entity
