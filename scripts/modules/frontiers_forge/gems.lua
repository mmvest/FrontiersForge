-- frontiers_forge/gems.lua
local Gems = {}

-- Hardcoded EQOA gem list (Gem | Rarity | Type | Stat)
local LOOKUP = {
    ["Achroite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "AR" },
    ["Amblygonite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "PR" },
    ["Apatite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "WIS" },
    ["Dravite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "LR" },
    ["Idocrase"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "CHA" },
    ["Indicolite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "CR" },
    ["Leucite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "INT" },
    ["Pectolite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "AGI" },
    ["Rhodizite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "STA" },
    ["Rubellite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "FR" },
    ["Schorl"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "DR" },
    ["Sinhalite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "STR" },
    ["Zoisite"] = { type = "Armorsmithing/Tailoring", rarity = "Common", stat = "DEX" },

    ["Enstatite"] = { type = "Armorsmithing", rarity = "Uncommon", stat = "STR STA" },
    ["Lazulite"] = { type = "Armorsmithing", rarity = "Uncommon", stat = "AGI, STA" },
    ["Takish Ivory"] = { type = "Armorsmithing", rarity = "Uncommon", stat = "DEX, AGI" },
    ["Marr's Blessed Alloy"] = { type = "Armorsmithing", rarity = "Uncommon", stat = "WIS, STA" },

    ["Takish Ivory Studs"] = { type = "Tailoring", rarity = "Uncommon", stat = "INT, AGI" },
    ["Rallosian Studs"] = { type = "Tailoring", rarity = "Uncommon", stat = "DEX, STA" },
    ["Marr's Blessed Studs"] = { type = "Tailoring", rarity = "Uncommon", stat = "WIS, CHA" },
    ["Tunare Hair Thread"] = { type = "Tailoring", rarity = "Uncommon", stat = "DEX, WIS" },

    ["Mana Infused Alloy"] = { type = "Armorsmithing", rarity = "Rare", stat = "POW" },
    ["Nephrite"] = { type = "Armorsmithing", rarity = "Rare", stat = "HP, POW" },
    ["Titan Alloy"] = { type = "Armorsmithing", rarity = "Rare", stat = "HP" },

    ["Ancient Treant Sap"] = { type = "Tailoring", rarity = "Rare", stat = "HP, PWR MAX" },
    ["Mana Infused Thread"] = { type = "Tailoring", rarity = "Rare", stat = "POW" },
    ["Titan Alloy Studs"] = { type = "Tailoring", rarity = "Rare", stat = "HP" },

    ["Heartsblood Alloy"] = { type = "Armorsmithing", rarity = "Ultra Rare", stat = "HP, STA, AR" },
    ["Mindflow Crystals"] = { type = "Armorsmithing", rarity = "Ultra Rare", stat = "POW, WIS, AR" },

    ["Heartsblood Alloy Studs"] = { type = "Tailoring", rarity = "Ultra Rare", stat = "HP, STA, AR" },
    ["Mindflow Thread"] = { type = "Tailoring", rarity = "Ultra Rare", stat = "POW, WIS, AR" },

    ["Ametrine"] = { type = "Weaponsmithing", rarity = "Common", stat = "DEX" },
    ["Bloodstone"] = { type = "Weaponsmithing", rarity = "Common", stat = "STR" },
    ["Citrine"] = { type = "Weaponsmithing", rarity = "Common", stat = "STA" },
    ["Erollite"] = { type = "Weaponsmithing", rarity = "Common", stat = "CHA" },
    ["Heliodore"] = { type = "Weaponsmithing", rarity = "Common", stat = "WIS" },
    ["Moonstone"] = { type = "Weaponsmithing", rarity = "Common", stat = "INT" },
    ["Tsavorite"] = { type = "Weaponsmithing", rarity = "Common", stat = "AGI" },

    ["Ethereal Mists"] = { type = "Weaponsmithing", rarity = "Rare", stat = "Power DoT" },
    ["Magnesium Alloy"] = { type = "Weaponsmithing", rarity = "Rare", stat = "Fire Proc" },
    ["Malign Alloy"] = { type = "Weaponsmithing", rarity = "Rare", stat = "Disease Proc" },
    ["Rogue Metal"] = { type = "Weaponsmithing", rarity = "Rare", stat = "Poison Proc" },
    ["Volatile Mana Crystals"] = { type = "Weaponsmithing", rarity = "Rare", stat = "Arcane DoT" },

    ["Negative Energy Stone"] = { type = "Weaponsmithing", rarity = "Ultra Rare", stat = "Mana Tap" },
    ["Viscious Vampire Blood"] = { type = "Weaponsmithing", rarity = "Ultra Rare", stat = "Blood Tap" },

    ["Dervish Ice Crystals"] = { type = "Weaponsmithing", rarity = "Uncommon", stat = "Cold Proc" },
    ["Ectoplasmic Crystals"] = { type = "Weaponsmithing", rarity = "Uncommon", stat = "Cursed Proc" },
    ["Intellect Spores"] = { type = "Weaponsmithing", rarity = "Uncommon", stat = "Arcane Power Dmg" },

    ["Amber"] = { type = "Jewelcrafting", rarity = "Common", stat = "STR" },
    ["Aquamarine"] = { type = "Jewelcrafting", rarity = "Common", stat = "PWR MINOR" },
    ["Black Bloodstone"] = { type = "Jewelcrafting", rarity = "Common", stat = "STA" },
    ["Carnelian"] = { type = "Jewelcrafting", rarity = "Common", stat = "AGI" },
    ["Cat's Eye Agate"] = { type = "Jewelcrafting", rarity = "Common", stat = "CHA" },
    ["Clear Quartz"] = { type = "Jewelcrafting", rarity = "Common", stat = "LR" },
    ["Hematite"] = { type = "Jewelcrafting", rarity = "Common", stat = "FR" },
    ["Jasper"] = { type = "Jewelcrafting", rarity = "Common", stat = "WIS" },
    ["Lapis Lazuli"] = { type = "Jewelcrafting", rarity = "Common", stat = "DR" },
    ["Malachite"] = { type = "Jewelcrafting", rarity = "Common", stat = "PR" },
    ["Onyx"] = { type = "Jewelcrafting", rarity = "Common", stat = "DEX" },
    ["Pyrite"] = { type = "Jewelcrafting", rarity = "Common", stat = "AC" },
    ["Star Rose Quartz"] = { type = "Jewelcrafting", rarity = "Common", stat = "INT" },
    ["Tourmaline"] = { type = "Jewelcrafting", rarity = "Common", stat = "HP MINOR" },
    ["Turquoise"] = { type = "Jewelcrafting", rarity = "Common", stat = "CR" },
    ["Wolf's Eye Agate"] = { type = "Jewelcrafting", rarity = "Common", stat = "AR" },

    ["Diamond"] = { type = "Jewelcrafting", rarity = "Rare", stat = "CHA, HP, AC" },
    ["Emerald"] = { type = "Jewelcrafting", rarity = "Rare", stat = "PWR MAJOR" },
    ["Fire Emerald"] = { type = "Jewelcrafting", rarity = "Rare", stat = "DEX, PWR, FR" },
    ["Ruby"] = { type = "Jewelcrafting", rarity = "Rare", stat = "HP MAJOR" },
    ["Sapphire"] = { type = "Jewelcrafting", rarity = "Rare", stat = "HP, PWR MAJOR" },
    ["Star Ruby"] = { type = "Jewelcrafting", rarity = "Rare", stat = "STR, PR, HP" },

    ["Black Sapphire"] = { type = "Jewelcrafting", rarity = "Ultra Rare", stat = "STA, HP, PWR, AR" },
    ["Blue Diamond"] = { type = "Jewelcrafting", rarity = "Ultra Rare", stat = "HP, PWR, AC" },

    ["Black Pearl"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "DEX, CHA" },
    ["Fire Opal"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "AGI, WIS" },
    ["Jacinth"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "STR, INT" },
    ["Jade"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "HP, PWR MINOR" },
    ["Opal"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "STA, CHA" },
    ["Pearl"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "PR, DR" },
    ["Peridot"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "FR, CR" },
    ["Topaz"] = { type = "Jewelcrafting", rarity = "Uncommon", stat = "LR, AR" },
}

function Gems.IsGem(name)
    return name and LOOKUP[name] ~= nil
end

-- Returns a reference to the gem descriptor (type/rarity/stat) or nil
function Gems.Get(name)
    return name and LOOKUP[name] or nil
end

-- Formats: "Name (amt) - Stat - Rarity"
function Gems.Format(name, amount, fmt_name_amt_fn)
    local g = Gems.get(name)
    if not g then return nil end

    local display_name
    if fmt_name_amt_fn then
        display_name = fmt_name_amt_fn(name, amount)
    else
        display_name = name
        if amount and amount > 1 then
            display_name = ("%s (%d)"):format(name, amount)
        end
    end

    return ("%s - %s - %s"):format(display_name, g.stat or "", g.rarity or "")
end

return Gems