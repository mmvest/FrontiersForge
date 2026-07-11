local Util = require("frontiers_forge.util")
local Icon = require("frontiers_forge.icon")

-- Base of the 9VIWndGame render code-block (compass, health, power, experience,
-- target nameplate). Its draw calls all sit strictly between VIWindow_BeginDraw and
-- VIWindow_EndDraw, so NOP'ing them individually is safe. The block is an overlay
-- that can relocate, so it is resolved lazily through a pointer chain (nil until the
-- window is loaded).
local function wnd_game_offset()
    return Util.GetOffsetFromPointerChain(0x14E200, {0x190 , 0x53C, 0x20, 0x1C})
end

-- This offset is the base of the UI Rendering code-block for 9VIWndChat window.
-- This window handles the chat pop-up for typing, the players active effects (buffs),
-- the ability bar, and the chat window in the bottom right.
local function wnd_chat_offset()
    return Util.GetOffsetFromPointerChain(0x4E37F4, {0x14, 0x688, 0x20, 0x1C})
end

local NOP = 0x00000000

-- The chat window can't be disabled by NOP'ing a single draw call, because its
-- BeginDraw installs a 2D overlay transform that its EndDraw must restore. NOP'ing
-- just the draw would leave the disabled box rendering under whatever transform is
-- live (e.g. rotating around the target ring on R1). Instead we branch from the
-- BeginDraw call straight to the epilogue, skipping BeginDraw, the draws, and EndDraw
-- together, so scratchpad state is left untouched.
local CHAT_WINDOW_DISABLE_BRANCH = 0x100000FE

-- The hotbars and active effects are child windows with their own draw
-- functions, drawn by the generic window walk, so there is no per window call
-- to NOP. Their draws use the same BeginDraw/EndDraw bracket as the chat
-- window, so each gets the same treatment, a branch from the BeginDraw call
-- over the whole bracket to the epilogue.
local HOTBAR_COMPACT_DISABLE_BRANCH  = 0x10000134
local HOTBAR_EXPANDED_DISABLE_BRANCH = 0x10000104
local ACTIVE_EFFECTS_DISABLE_BRANCH  = 0x1000005E

-- These element offsets are offsets away from base_offset
local ui_elements = {
    -- base_offset and steps are used to find the opcode,
    -- opcode = a place to store the original opcode that will get overwritten
    -- disable_opcode = a replacement opcode if you don't want to just NOP it out.
    compass_back        = { type = "opcode", base_offset = wnd_game_offset, steps = {0x00C8}, opcode = NOP},
    compass_face        = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0104}, opcode = NOP},
    health_bar          = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0184}, opcode = NOP},
    power_bar           = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0208}, opcode = NOP},
    secondary_exp_bar   = { type = "opcode", base_offset = wnd_game_offset, steps = {0x03C0}, opcode = NOP},
    main_exp_bar        = { type = "opcode", base_offset = wnd_game_offset, steps = {0x03EC}, opcode = NOP},
    target_nameplate    = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0514}, opcode = NOP},
    group_member_panel  = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0418}, opcode = NOP},
    group_compass_marks = { type = "opcode", base_offset = wnd_game_offset, steps = {0x010C}, opcode = NOP},
    pet_panel           = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0464}, opcode = NOP},
    chat_window         = { type = "opcode", base_offset = wnd_chat_offset, steps = {0xE8}, opcode = NOP, disable_opcode = CHAT_WINDOW_DISABLE_BRANCH},
    -- All three hotbar windows share these two draw functions (VIWndHUDMenu_Draw
    -- and its expanded variant), so one pair of patches hides every bar.
    hotbar_draw_compact  = { type = "opcode", base_offset = wnd_game_offset, steps = {0xD5D8}, opcode = NOP, disable_opcode = HOTBAR_COMPACT_DISABLE_BRANCH},
    hotbar_draw_expanded = { type = "opcode", base_offset = wnd_game_offset, steps = {0xDB44}, opcode = NOP, disable_opcode = HOTBAR_EXPANDED_DISABLE_BRANCH},
    active_effects       = { type = "opcode", base_offset = wnd_game_offset, steps = {0x118A8}, opcode = NOP, disable_opcode = ACTIVE_EFFECTS_DISABLE_BRANCH},
}

local UI = {}

local function WriteInstruction(offset, opcode)
    Util.WriteToOffset(offset, "uint32_t", opcode)
end

-- Resolves an element's final offset, or nil if the underlying window/chain
-- isn't loaded. base_offset may be a number (static) or a function that lazily
-- resolves an overlay window base (and may itself return nil).
local function ResolveElementOffset(ui_element)
    local base = ui_element.base_offset
    if type(base) == "function" then
        base = base()
    end
    if base == nil then
        return nil
    end
    return Util.GetOffsetFromPointerChain(base, ui_element.steps)
end

-- Both appliers return whether the write actually landed. They cannot land
-- before the game UI exists (login screen, character select, a script's own
-- Load callback), so a caller that runs once at startup should keep calling
-- until this comes back true.
local function DisableUIElement(ui_element)
    local offset = ResolveElementOffset(ui_element)
    if offset == nil then
        return false
    end
    if(ui_element.type == "opcode") then
        -- Most elements are disabled by NOP'ing their draw instruction; some (e.g. chat_window)
        -- need a specific replacement opcode instead.
        local disable_opcode = ui_element.disable_opcode or NOP
        local curr_opcode = Util.ReadFromOffset(offset, "uint32_t")
        -- Only capture the original opcode if we're not already looking at a disabled state,
        -- otherwise re-disabling would overwrite the saved original with our patch opcode.
        if(curr_opcode ~= NOP and curr_opcode ~= disable_opcode) then
            ui_element.opcode = curr_opcode
        end
        WriteInstruction(offset, disable_opcode)
        -- Remembered so Enable can restore even when the chain cannot be
        -- resolved at that moment, e.g. a chain anchored on the focused
        -- window goes elsewhere while the pause menu is up.
        ui_element.patched_offset = offset
    end
    return true
end

local function EnableUIElement(ui_element)
    if(ui_element.type ~= "opcode") then
        return ResolveElementOffset(ui_element) ~= nil
    end
    -- Restore at the address the patch actually landed at, falling back to a
    -- fresh resolve only when that address no longer holds our patch.
    local disable_opcode = ui_element.disable_opcode or NOP
    local offset = ui_element.patched_offset
    if offset == nil or Util.ReadFromOffset(offset, "uint32_t") ~= disable_opcode then
        offset = ResolveElementOffset(ui_element)
    end
    if offset == nil then
        return false
    end
    if(ui_element.opcode ~= NOP) then
        WriteInstruction(offset, ui_element.opcode)
    end
    ui_element.patched_offset = nil
    return true
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                Health Bar                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Stops the health bar from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableHealthBar()
    return DisableUIElement(ui_elements.health_bar)
end

--- Restores the health bar after DisableHealthBar.
function UI.EnableHealthBar()
    return EnableUIElement(ui_elements.health_bar)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                Power Bar                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Stops the power bar from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisablePowerBar()
    return DisableUIElement(ui_elements.power_bar)
end

--- Restores the power bar after DisablePowerBar.
function UI.EnablePowerBar()
    return EnableUIElement(ui_elements.power_bar)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                              Experience Bars                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Stops the main experience bar from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableMainExpBar()
    return DisableUIElement(ui_elements.main_exp_bar)
end

--- Restores the main experience bar after DisableMainExpBar.
function UI.EnableMainExpBar()
    return EnableUIElement(ui_elements.main_exp_bar)
end

--- Stops the secondary experience bar from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableSecondaryExpBar()
    return DisableUIElement(ui_elements.secondary_exp_bar)
end

--- Restores the secondary experience bar after DisableSecondaryExpBar.
function UI.EnableSecondaryExpBar()
    return EnableUIElement(ui_elements.secondary_exp_bar)
end

--- Disables both experience bars at once.
--- @return boolean applied False when the game UI is not loaded yet, call again once in game.
function UI.DisableExperienceBars()
    local main = UI.DisableMainExpBar()
    local secondary = UI.DisableSecondaryExpBar()
    return main and secondary
end

--- Enables both experience bars at once.
--- @return boolean applied
function UI.EnableExperienceBars()
    local main = UI.EnableMainExpBar()
    local secondary = UI.EnableSecondaryExpBar()
    return main and secondary
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                 Compass                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
--- Stops the compass (face and backing) from rendering.
--- @return boolean applied False when the game UI is not loaded yet, call again once in game.
function UI.DisableCompass()
    local face = DisableUIElement(ui_elements.compass_face)
    local back = DisableUIElement(ui_elements.compass_back)
    return face and back
end

--- Restores the compass after DisableCompass.
--- @return boolean applied
function UI.EnableCompass()
    local face = EnableUIElement(ui_elements.compass_face)
    local back = EnableUIElement(ui_elements.compass_back)
    return face and back
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                             Target Nameplate                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
--- Stops the target nameplate from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableTargetNameplate()
    return DisableUIElement(ui_elements.target_nameplate)
end

--- Restores the target nameplate after DisableTargetNameplate.
function UI.EnableTargetNameplate()
    return EnableUIElement(ui_elements.target_nameplate)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Group Display                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Stops the panel listing group member names and health bars from rendering.
--- Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableGroupMemberPanel()
    return DisableUIElement(ui_elements.group_member_panel)
end

--- Restores the group member panel after DisableGroupMemberPanel.
function UI.EnableGroupMemberPanel()
    return EnableUIElement(ui_elements.group_member_panel)
end

--- Stops the colored group member position markers around the compass from rendering.
--- Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableGroupCompassMarkers()
    return DisableUIElement(ui_elements.group_compass_marks)
end

--- Restores the group compass markers after DisableGroupCompassMarkers.
function UI.EnableGroupCompassMarkers()
    return EnableUIElement(ui_elements.group_compass_marks)
end

--- Disables all group UI (member panel and compass markers) at once.
--- @return boolean applied False when the game UI is not loaded yet, call again once in game.
function UI.DisableGroupDisplay()
    local panel = UI.DisableGroupMemberPanel()
    local marks = UI.DisableGroupCompassMarkers()
    return panel and marks
end

--- Enables all group UI (member panel and compass markers) at once.
--- @return boolean applied
function UI.EnableGroupDisplay()
    local panel = UI.EnableGroupMemberPanel()
    local marks = UI.EnableGroupCompassMarkers()
    return panel and marks
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                 Pet Panel                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Stops the pet panel from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisablePetPanel()
    return DisableUIElement(ui_elements.pet_panel)
end

--- Restores the pet panel after DisablePetPanel.
function UI.EnablePetPanel()
    return EnableUIElement(ui_elements.pet_panel)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                              Active Effects                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Hides the active effects (buff) display. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableActiveEffectsDisplay()
    return DisableUIElement(ui_elements.active_effects)
end

--- Restores the active effects display after DisableActiveEffectsDisplay.
function UI.EnableActiveEffectsDisplay()
    return EnableUIElement(ui_elements.active_effects)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Ability Bar                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Hides all three hotbar windows, compact and expanded views both.
--- @return boolean applied False when the game UI is not loaded yet, call again once in game.
function UI.DisableAbilityBar()
    local compact = DisableUIElement(ui_elements.hotbar_draw_compact)
    local expanded = DisableUIElement(ui_elements.hotbar_draw_expanded)
    return compact and expanded
end

--- Restores the ability bar after DisableAbilityBar.
--- @return boolean applied
function UI.EnableAbilityBar()
    local compact = EnableUIElement(ui_elements.hotbar_draw_compact)
    local expanded = EnableUIElement(ui_elements.hotbar_draw_expanded)
    return compact and expanded
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Chat Window                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

--- Stops the chat window from rendering. Returns false when the game UI is not loaded yet, call again once in game.
function UI.DisableChatWindow()
    return DisableUIElement(ui_elements.chat_window)
end

--- Restores the chat window after DisableChatWindow.
function UI.EnableChatWindow()
    return EnableUIElement(ui_elements.chat_window)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                            Disposition Faces                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- The game's target nameplate maps disposition to three face textures
-- (built-in UI texture ids): 0-1 hostile, 4-6 friendly, everything else neutral.
local DISPOSITION_FACE_HOSTILE  = 0x73
local DISPOSITION_FACE_NEUTRAL  = 0x74
local DISPOSITION_FACE_FRIENDLY = 0x75

--- UI texture id of the face icon the game shows for a disposition value.
--- @param disposition integer Disposition value (e.g. entity disposition).
--- @return integer|nil tex_id UI texture id for Icon.GetUITexture, or nil for a nil disposition.
function UI.GetDispositionFaceTexId(disposition)
    disposition = tonumber(disposition)
    if disposition == nil then
        return nil
    end
    if disposition <= 1 then
        return DISPOSITION_FACE_HOSTILE
    elseif disposition >= 4 and disposition <= 6 then
        return DISPOSITION_FACE_FRIENDLY
    end
    return DISPOSITION_FACE_NEUTRAL
end

--- Draws the disposition face for a disposition value at the current ImGui cursor.
--- @param disposition integer Disposition value.
--- @param scale number|nil Size multiplier, default 1.
--- @return boolean drawn False when the texture is unavailable (nothing drawn).
function UI.DrawDispositionIcon(disposition, scale)
    local texture, w, h = Icon.GetUITexture(UI.GetDispositionFaceTexId(disposition))
    if texture == nil then
        return false
    end
    scale = scale or 1
    ImGui.Image(texture, w * scale, h * scale)
    return true
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Class Icons                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

local CLASS_ICON_TEX_IDS = {
    [0]  = 0x17, -- Warrior
    [1]  = 0x13, -- Ranger
    [2]  = 0x12, -- Paladin
    [3]  = 0x15, -- Shadowknight
    [4]  = 0x10, -- Monk
    [5]  = 0x0B, -- Bard
    [6]  = 0x14, -- Rogue
    [7]  = 0x0D, -- Druid
    [8]  = 0x16, -- Shaman
    [9]  = 0x0C, -- Cleric
    [10] = 0x0F, -- Magician
    [11] = 0x11, -- Necromancer
    [12] = 0x0E, -- Enchanter
    [13] = 0x18, -- Wizard
    [14] = 0xFB, -- Alchemist
}

--- UI texture id of a class's emblem.
--- @param class_id integer Class id from 0 to 14 (see Player.classes).
--- @return integer|nil tex_id UI texture id for Icon.GetUITexture, or nil for an unknown class.
function UI.GetClassIconTexId(class_id)
    return CLASS_ICON_TEX_IDS[class_id]
end

--- The class emblem texture, decoded out of the game on first use and cached by
--- the icon cache. The emblems are not square, they run 29 to 92 pixels wide
--- over a common 44 tall, so keep the returned aspect ratio when drawing one.
--- @param class_id integer Class id from 0 to 14. Pass Player.GetClassId() for the local player.
--- @return userdata|nil texture
--- @return integer|nil width
--- @return integer|nil height
function UI.GetClassIconTexture(class_id)
    local tex_id = CLASS_ICON_TEX_IDS[class_id]
    if tex_id == nil then
        return nil
    end
    return Icon.GetUITexture(tex_id)
end

--- Draws the class emblem for a class id at the current ImGui cursor.
--- @param class_id integer Class id from 0 to 14.
--- @param scale number|nil Size multiplier, default 1.
--- @return boolean drawn False when the texture is unavailable (nothing drawn).
function UI.DrawClassIcon(class_id, scale)
    local texture, w, h = UI.GetClassIconTexture(class_id)
    if texture == nil then
        return false
    end
    scale = scale or 1
    ImGui.Image(texture, w * scale, h * scale)
    return true
end

--- Disables every UI element this module knows about.
--- @return boolean applied False when any element could not be reached yet, call again once in game.
function UI.DisableUI()
    local all = true
    all = UI.DisableHealthBar() and all
    all = UI.DisablePowerBar() and all
    all = UI.DisableExperienceBars() and all
    all = UI.DisableCompass() and all
    all = UI.DisableTargetNameplate() and all
    all = UI.DisableGroupDisplay() and all
    all = UI.DisablePetPanel() and all
    all = UI.DisableActiveEffectsDisplay() and all
    all = UI.DisableAbilityBar() and all
    all = UI.DisableChatWindow() and all
    return all
end

--- Enables every UI element this module knows about.
--- @return boolean applied
function UI.EnableUI()
    local all = true
    all = UI.EnableHealthBar() and all
    all = UI.EnablePowerBar() and all
    all = UI.EnableExperienceBars() and all
    all = UI.EnableCompass() and all
    all = UI.EnableTargetNameplate() and all
    all = UI.EnableGroupDisplay() and all
    all = UI.EnablePetPanel() and all
    all = UI.EnableActiveEffectsDisplay() and all
    all = UI.EnableAbilityBar() and all
    all = UI.EnableChatWindow() and all
    return all
end

return UI