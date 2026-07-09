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
        int32_t  cooldown_lockout_ms;   // +0x24  total lockout duration in ms while the ability is on
                                        //        cooldown, 0 when ready. Equals (cast_time + cooldown)
                                        //        * 1000 + 300. Server sent, constant while set (NOT a
                                        //        countdown). Drives the dim overlay icon on the
                                        //        hotbar slot.
        uint32_t unknown_28;            // +0x28
        uint32_t level;                 // +0x2C
        float    range;                 // +0x30
        uint32_t cast_time;             // +0x34
        uint32_t pwr_cost;              // +0x38
        uint32_t icon_bkgrnd_ref;       // +0x3C  resource hash into the UI texture dictionary
        uint32_t icon_foregrnd_ref;     // +0x40  resource hash into the UI texture dictionary
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

--- Wraps a raw ability record address in an Ability object.
--- @param address integer|ffi.cdata* Host address of the record, either a number or an Ability pointer.
--- @return table ability New Ability object backed by the record at the given address.
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

--- @return boolean valid True when this record holds a real ability.
function Ability:IsValid()
    return self.ptr.valid ~= 0
end

--- @return integer id The ability id, which is also the tree key.
function Ability:GetId()
    return self.ptr.id
end

--- @return integer category Category code. Values 0xFC and above appear to be special or inventory entries.
function Ability:GetCategory()
    return self.ptr.category
end

--- @return integer slot Spellbook sort position. Values 0xFC to 0xFF are items placed in hotbar slots 5 to 8.
function Ability:GetSpellbookSlot()
    return self.ptr.spellbook_slot
end

--- @return integer level Level required to use the ability.
function Ability:GetLevel()
    return self.ptr.level
end

--- @return number range The ability range as a float.
function Ability:GetRange()
    return self.ptr.range
end

--- @return integer cast_time Cast time in seconds.
function Ability:GetCastTime()
    return self.ptr.cast_time
end

--- @return integer pwr_cost Power cost to use the ability.
function Ability:GetPwrCost()
    return self.ptr.pwr_cost
end

--- The icon refs are 32 bit resource hashes the game looks up in its texture
--- dictionary when drawing the spellbook and hotbar.
--- @return integer icon_ref Resource hash for the icon background texture.
function Ability:GetIconBackgroundRef()
    return self.ptr.icon_bkgrnd_ref
end

--- @return integer icon_ref Resource hash for the icon foreground texture.
function Ability:GetIconForegroundRef()
    return self.ptr.icon_foregrnd_ref
end

--- @return integer scope Target scope value, see Ability.Scope for known values.
function Ability:GetScope()
    return self.ptr.scope
end

--- @return integer cooldown Recast time in seconds.
function Ability:GetCooldown()
    return self.ptr.cooldown
end

--- @return integer equip_req Equipment requirement bitmask.
function Ability:GetEquipRequirements()
    return self.ptr.equip_req
end

--- Whether the ability is currently on cooldown (its hotbar icon is dimmed).
--- Cooldowns are server authoritative. The flag is set the moment the cast
--- starts and cleared when the server sends the ability ready message, the
--- client never tracks the remaining time itself.
--- @return boolean on_cooldown True while the ability is on cooldown.
function Ability:IsOnCooldown()
    return self.ptr.cooldown_lockout_ms > 0
end

--- Total lockout duration of the current cooldown in milliseconds, equal to
--- (cast time + recast time) * 1000 + 300. The value is constant while the
--- ability is on cooldown (it is NOT a live countdown). Modders wanting
--- remaining time should record when IsOnCooldown flips true and count down
--- from this value.
--- @return integer lockout_ms Total lockout in ms, or 0 when the ability is ready.
function Ability:GetCooldownLockoutMs()
    return self.ptr.cooldown_lockout_ms
end

--- @return string name The ability name converted to UTF-8.
function Ability:GetName()
    return util.utf16_to_utf8(self.ptr.name)
end

--- @return string description The ability description converted to UTF-8.
function Ability:GetDescription()
    return util.utf16_to_utf8(self.ptr.description)
end

return Ability
