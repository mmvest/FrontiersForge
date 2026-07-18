local ffi = require("ffi")
local Util = require("frontiers_forge.util")

-- Define player_offset
local player_offset = 0x1FBBA0C

-- Define Player functions
local Player = {}

function Player.GetName()
    local name_addr = ffi.cast("char*", Util.EEmem() + player_offset + 0x04)
    return ffi.string(name_addr)
end

function Player.GetLevel()
    return Util.ReadFromOffset(player_offset + 0x24, "uint32_t")
end

function Player.GetExp()
    return Util.ReadFromOffset(player_offset + 0x28, "uint32_t")
end

function Player.GetExpDebt()
    return Util.ReadFromOffset(player_offset + 0x2C, "uint32_t")
end

function Player.GetTotalStr()
    return Util.ReadFromOffset(player_offset + 0x64, "uint32_t")
end

function Player.GetTotalSta()
    return Util.ReadFromOffset(player_offset + 0x68, "uint32_t")
end

function Player.GetTotalAgi()
    return Util.ReadFromOffset(player_offset + 0x6C, "uint32_t")
end

function Player.GetTotalDex()
    return Util.ReadFromOffset(player_offset + 0x70, "uint32_t")
end

function Player.GetTotalWis()
    return Util.ReadFromOffset(player_offset + 0x74, "uint32_t")
end

function Player.GetTotalInt()
    return Util.ReadFromOffset(player_offset + 0x78, "uint32_t")
end

function Player.GetTotalCha()
    return Util.ReadFromOffset(player_offset + 0x7C, "uint32_t")
end

function Player.GetBaseStr()
    return Util.ReadFromOffset(player_offset + 0xD8, "uint32_t")
end

function Player.GetBaseSta()
    return Util.ReadFromOffset(player_offset + 0xDC, "uint32_t")
end

function Player.GetBaseAgi()
    return Util.ReadFromOffset(player_offset + 0xE0, "uint32_t")
end

function Player.GetBaseDex()
    return Util.ReadFromOffset(player_offset + 0xE4, "uint32_t")
end

function Player.GetBaseWis()
    return Util.ReadFromOffset(player_offset + 0xE8, "uint32_t")
end

function Player.GetBaseInt()
    return Util.ReadFromOffset(player_offset + 0xEC, "uint32_t")
end

function Player.GetBaseCha()
    return Util.ReadFromOffset(player_offset + 0xF0, "uint32_t")
end

function Player.GetCurrentHp()
    return Util.ReadFromOffset(player_offset + 0x80, "uint32_t")
end

function Player.GetMaxHp()
    return Util.ReadFromOffset(player_offset + 0x84, "uint32_t")
end

function Player.GetBaseHp()
    return Util.ReadFromOffset(player_offset + 0xF8, "uint32_t")
end

function Player.GetCurrentPwr()
    return Util.ReadFromOffset(player_offset + 0x88, "uint32_t")
end

function Player.GetMaxPwr()
    return Util.ReadFromOffset(player_offset + 0x8C, "uint32_t")
end

function Player.GetBasePwr()
    return Util.ReadFromOffset(player_offset + 0x100, "uint32_t")
end

function Player.GetAc()
    return Util.ReadFromOffset(player_offset + 0x9C, "uint32_t")
end

function Player.GetBaseResist()
    local wisdom = Player.GetTotalWis()

    -- Every 7 wisdom gives +1 resist
    local bonus = math.floor(wisdom / 7)

    -- Final resist = 40 + bonus
    local total = 40 + bonus

    return total
end

function Player.GetPoisonResistBuff()
    return Util.ReadFromOffset(player_offset + 0xBC, "uint32_t")
end

function Player.GetDiseaseResistBuff()
    return Util.ReadFromOffset(player_offset + 0xC0, "uint32_t")
end

function Player.GetFireResistBuff()
    return Util.ReadFromOffset(player_offset + 0xC4, "uint32_t")
end

function Player.GetColdResistBuff()
    return Util.ReadFromOffset(player_offset + 0xC8, "uint32_t")
end

function Player.GetLightningResistBuff()
    return Util.ReadFromOffset(player_offset + 0xCC, "uint32_t")
end

function Player.GetArcaneResistBuff()
    return Util.ReadFromOffset(player_offset + 0xD0, "uint32_t")
end

function Player.GetCMs()
    return Util.ReadFromOffset(0x1FFE394, "uint32_t")
end

function Player.GetCMsSpent()
    return Util.ReadFromOffset(0x1FFE398, "uint32_t")
end

function Player.GetCMPct()
    return Util.ReadFromOffset(0x1FFE390, "uint32_t")
end

function Player.GetCoordinates()
    local coordinate_address = Util.EEmem() + 0x1FB65B0
    local float_ptr = ffi.cast("float*", coordinate_address)

    local x = float_ptr[0]
    local y = float_ptr[1]
    local z = float_ptr[2]

    return { x = x, y = y, z = z }
end

--- The local player's own entity id.
--- @return integer entity_id
function Player.GetEntityId()
    return Util.ReadFromOffset(0x1FB6928, "uint32_t")
end

function Player.GetTargetEntityId()
    local current_target_offset = 0x1FBB870
    return Util.ReadFromOffset(current_target_offset, "uint32_t")
end

--- The player's pet entity id, or nil when the player has no pet.
--- The game clears the slot to -1 when the pet goes away.
--- @return integer|nil pet_entity_id
function Player.GetPetEntityId()
    local pet_id = Util.ReadFromOffset(0x1FDB580, "int32_t")
    if pet_id == nil or pet_id <= 0 then
        return nil
    end
    return pet_id
end

-- Class and race ids index the game's own tables, which is where these names
-- come from.
Player.classes = {
    [0] = "Warrior",
    [1] = "Ranger",
    [2] = "Paladin",
    [3] = "Shadowknight",
    [4] = "Monk",
    [5] = "Bard",
    [6] = "Rogue",
    [7] = "Druid",
    [8] = "Shaman",
    [9] = "Cleric",
    [10] = "Magician",
    [11] = "Necromancer",
    [12] = "Enchanter",
    [13] = "Wizard",
    [14] = "Alchemist",
}

Player.races = {
    [0] = "Human",
    [1] = "Elf",
    [2] = "Dark Elf",
    [3] = "Gnome",
    [4] = "Dwarf",
    [5] = "Troll",
    [6] = "Barbarian",
    [7] = "Halfling",
    [8] = "Erudite",
    [9] = "Ogre",
}

Player.max_class_id = 14
Player.max_race_id = 9

--- The player's class id. The game clamps anything above max_class_id to 0.
--- @return integer class_id Class id from 0 to 14.
function Player.GetClassId()
    return Util.ReadFromOffset(player_offset + 0x1C, "uint32_t")
end

--- The player's race id. The game clamps anything above max_race_id to 0.
--- @return integer race_id Race id from 0 to 9.
function Player.GetRaceId()
    return Util.ReadFromOffset(player_offset + 0x20, "uint32_t")
end

--- @return string|nil class_name Class name, or nil when the id is out of range.
function Player.GetClassName()
    return Player.classes[Player.GetClassId()]
end

--- @return string|nil race_name Race name, or nil when the id is out of range.
function Player.GetRaceName()
    return Player.races[Player.GetRaceId()]
end

return Player
