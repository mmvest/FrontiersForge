local ffi = require("ffi")
local Util = require("frontiers_forge.util")

-- The player's active effects (buffs/debuffs), the icon row right of the
-- health/power/experience bars. The server sends up to 8 entries, each an icon
-- hash plus a display name.

local Effects = {}

Effects.max_effects = 8

local SINGLETON_OFFSET   = 0x1FAF730
local COUNT_OFFSET       = SINGLETON_OFFSET + 0x2C170  -- u32, clamped to 8 by the game
local ICON_ARRAY_OFFSET  = SINGLETON_OFFSET + 0x2C174  -- u32 icon hash per effect
local NAME_ARRAY_OFFSET  = SINGLETON_OFFSET + 0x2C194  -- wchar_t[64] per effect
local NAME_STRIDE        = 0x80

--- Number of active effects on the player.
--- @return integer count Effect count from 0 to max_effects, or 0 when not in game.
function Effects.GetCount()
    if Util.IsInGame() == 0 then
        return 0
    end
    local count = Util.ReadFromOffset(COUNT_OFFSET, "uint32_t")
    if count > Effects.max_effects then
        return 0
    end
    return count
end

--- Icon resource hash of an active effect, usable with Icon.GetTexture.
--- @param index integer Effect index from 0 to GetCount() - 1.
--- @return integer|nil icon_ref Icon hash, or nil when the index is out of range.
function Effects.GetIconRef(index)
    if index < 0 or index >= Effects.GetCount() then
        return nil
    end
    return Util.ReadFromOffset(ICON_ARRAY_OFFSET + index * 4, "uint32_t")
end

--- Display name of an active effect (what the pause menu status page shows).
--- @param index integer Effect index from 0 to GetCount() - 1.
--- @return string|nil name Effect name in UTF-8, or nil when the index is out of range.
function Effects.GetName(index)
    if index < 0 or index >= Effects.GetCount() then
        return nil
    end
    local name_ptr = ffi.cast("wchar_t*", Util.EEmem() + NAME_ARRAY_OFFSET + index * NAME_STRIDE)
    return Util.utf16_to_utf8(name_ptr)
end

--- Both fields of an active effect at once.
--- @param index integer Effect index from 0 to GetCount() - 1.
--- @return table|nil effect { index, icon_ref, name }, or nil when the index is out of range.
function Effects.GetEffect(index)
    local icon_ref = Effects.GetIconRef(index)
    if icon_ref == nil then
        return nil
    end
    return { index = index, icon_ref = icon_ref, name = Effects.GetName(index) }
end

--- Iterator over all active effects: for index, effect in Effects.All() do ... end
function Effects.All()
    local index = -1
    return function()
        index = index + 1
        local effect = Effects.GetEffect(index)
        if effect == nil then
            return nil
        end
        return index, effect
    end
end

return Effects
