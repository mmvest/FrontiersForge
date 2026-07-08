local ffi = require("ffi")
local util = require("frontiers_forge.util")

-- The player's abilities appear to live in a single array of these records
-- with size 0x1D8. Index 0 is the null sentinel which is never a real ability.
ffi.cdef[[
    typedef struct {
        uint32_t tree_meta;             // +0x00  not really sure what this is
        uint32_t parent_index;          // +0x04  parent node index (0 = none)
        uint32_t left_index;            // +0x08  left child index (0 = none)
        uint32_t right_index;           // +0x0C  right child index (0 = none)
        uint32_t id;                    // +0x10  ability id (tree key)
        uint32_t unknown_14;            // +0x14
        uint32_t category;              // +0x18  0xFC and above = special/inventory?
        uint32_t valid;                 // +0x1C  nonzero when this record holds a real ability?
        uint32_t spellbook_slot;        // +0x20  spellbook position; 0-4 also appear on the hotbar,
                                        //        0xFC-0xFF are the specific items placed in hotbar slots 5-8
        int32_t  flag_24;               // +0x24  >0 draws an overlay icon (0x3d) on the hotbar slot?
        uint32_t unknown_28;            // +0x28
        uint32_t level;                 // +0x2C
        float    range;                 // +0x30
        uint32_t cast_time;             // +0x34
        uint32_t pwr_cost;              // +0x38
        uint32_t icon_bkgrnd_ref;       // +0x3C
        uint32_t icon_foregrnd_ref;     // +0x40
        uint32_t scope;                 // +0x44
        uint32_t cooldown;              // +0x48
        uint32_t equip_req;             // +0x4C  bitmask
        wchar_t name[64];               // +0x50
        wchar_t description[132];       // +0xD0
    } Ability;
]]

local Ability = {}
Ability.__index = Ability

-- Scope Enum
Ability.Scope = {
    SELF = 0,
    TARGET = 1,
    GROUP = 2,
    PET = 3,
    CORPSE = 4,
    UNKNOWN = 5
}

Ability.size = 0x1D8

function Ability.new(address)
    if type(address) == "number" then
        address = ffi.cast("Ability*", address)
    elseif not ffi.istype("Ability*", address) then
        error("Invalid pointer type for Ability")
    end

    local self = setmetatable({}, Ability)
    self.ptr = address  -- Store the FFI pointer
    return self
end

function Ability:IsValid()
    return self.ptr.valid ~= 0
end

function Ability:GetId()
    return self.ptr.id
end

function Ability:GetCategory()
    return self.ptr.category
end

function Ability:GetSpellbookSlot()
    return self.ptr.spellbook_slot
end

function Ability:GetLevel()
    return self.ptr.level
end

function Ability:GetRange()
    return self.ptr.range
end

function Ability:GetCastTime()
    return self.ptr.cast_time
end

function Ability:GetPwrCost()
    return self.ptr.pwr_cost
end

function Ability:GetIconBackgroundRef()
    return self.ptr.icon_bkgrnd_ref
end

function Ability:GetIconForegroundRef()
    return self.ptr.icon_foregrnd_ref
end

function Ability:GetScope()
    return self.ptr.scope
end

function Ability:GetCooldown()
    return self.ptr.cooldown
end

function Ability:GetEquipRequirements()
    return self.ptr.equip_req
end

function Ability:GetName()
    return util.utf16_to_utf8(self.ptr.name)
end

function Ability:GetDescription()
    return util.utf16_to_utf8(self.ptr.description)
end

return Ability
