--[[
    class_art.lua

    The game's own class emblems, for the party frames and the damage meter.

    The class to texture mapping and the decoding both live in the shared
    frontiers_forge UI module now, so this is a thin pass-through kept so the
    drawing modules keep a single seam for class art.
]]

local UI = require("frontiers_forge.ui")

local ClassArt = {}

--- The UI texture id of a class emblem.
--- @param class_id integer
--- @return integer|nil tex_id
function ClassArt.GetTexId(class_id)
    return UI.GetClassIconTexId(class_id)
end

--- The class emblem texture, decoded out of the game on first use and cached.
--- The emblems are not square, so keep the aspect ratio when drawing one.
--- @return userdata|nil texture
--- @return integer|nil width
--- @return integer|nil height
function ClassArt.GetTexture(class_id)
    return UI.GetClassIconTexture(class_id)
end

--- Kept for the script's cleanup path. The textures themselves are owned and
--- released by the icon cache, so there is nothing of our own to drop.
function ClassArt.Reset()
end

return ClassArt
