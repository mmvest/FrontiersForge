local Util = require("frontiers_forge.util")

-- This offset is the base of the UI rendering code-block for the 9VIWndGame window.
-- This window handles compass, health, power, experience, and target nameplate.
-- Since the code is an overlay, it can be written anywhere in memory.
-- Due to this, we have to use a pointer chain to get the location.
--
-- For future reference, all seven element offsets we nop that are based in this window
-- are plain draw calls that sit strictly between this function's VIWindow_BeginDraw (+0x5C)
-- and VIWindow_EndDraw (+0x57C), so NOP'ing them individually is safe as the draw-context
-- save/restore stays balanced and no state leaks into other UI.
local wnd_game_offset = Util.GetOffsetFromPointerChain(0x14E200, {0x190 , 0x53C, 0x20, 0x1C})

-- This offset is the base of the UI Rendering code-block for 9VIWndChat window.
-- This window handles the chat pop-up for typing, the players active effects (buffs),
-- the ability bar, and the chat window in the bottom right.
local wnd_chat_offset = Util.GetOffsetFromPointerChain(0x4E37F4, {0x14, 0x688, 0x20, 0x1C})

local NOP = 0x00000000

-- The chat window can't be disabled by NOP'ing its draw instruction like the other elements.
-- At chat_offset+0xE8 the game calls VIWindow_BeginDraw, which saves the global scratchpad
-- matrices and installs the chat window's own 2D overlay transform. The matching VIWindow_EndDraw
-- at +0x470 restores them.
--
-- Instead we replace the BeginDraw call with a PC-relative branch straight to the function's
-- epilogue at +0x4E4, skipping BeginDraw, every chat draw call, AND EndDraw together. Scratchpad
-- state is left completely untouched, so nothing leaks and other UI windows are unaffected.
--
-- This fixes a bug caused by NOP'ing the original instruction where the disabled chat box would
-- render under whatever transform is currently live. For example, when the player presses R1 to
-- select a target, the chat box appears next to the target indicator and rotates around the target.
--
-- Opcode: beq zero, zero, +0x3FC  ->  0x100000FE
--   offset = (0x4E4 - 0xE8 - 4) / 4 = 0xFE.
local CHAT_WINDOW_DISABLE_BRANCH = 0x100000FE

-- These element offsets are offsets away from base_offset
local ui_elements = {
    -- element_name     = {opcode_offset, original_opcode}
    compass_back        = { type = "opcode", base_offset = wnd_game_offset, steps = {0x00C8}, opcode = NOP},
    compass_face        = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0104}, opcode = NOP},
    health_bar          = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0184}, opcode = NOP},
    power_bar           = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0208}, opcode = NOP},
    secondary_exp_bar   = { type = "opcode", base_offset = wnd_game_offset, steps = {0x03C0}, opcode = NOP},
    main_exp_bar        = { type = "opcode", base_offset = wnd_game_offset, steps = {0x03EC}, opcode = NOP},
    target_nameplate    = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0514}, opcode = NOP},
    group_member_panel  = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0418}, opcode = NOP},
    group_compass_marks = { type = "opcode", base_offset = wnd_game_offset, steps = {0x010C}, opcode = NOP},
    -- The pet/henchman panel (name + health bar) drawn below the group member panel
    pet_panel           = { type = "opcode", base_offset = wnd_game_offset, steps = {0x0464}, opcode = NOP},
    chat_window         = { type = "opcode", base_offset = wnd_chat_offset, steps = {0xE8}, opcode = NOP, disable_opcode = CHAT_WINDOW_DISABLE_BRANCH},
    active_effects      = { type = "flag", base_offset = 0x4E37F4, steps = {0x14, 0x74C}},
    ability_bar         = { type = "flag", base_offset = 0x4E37F4, steps = {0x1C}}
}

local UI = {}

local function WriteInstruction(offset, opcode)
    Util.WriteToOffset(offset, "uint32_t", opcode)
end

local function DisableFlag(offset)
    Util.WriteToOffset(offset, "uint8_t", 0)
end

local function EnableFlag(offset)
    Util.WriteToOffset(offset, "uint8_t", 1)
end

local function DisableUIElement(ui_element)
    local offset = Util.GetOffsetFromPointerChain(ui_element.base_offset, ui_element.steps)
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
    elseif(ui_element.type == "flag") then
        DisableFlag(offset)
    end
end

local function EnableUIElement(ui_element)
    local offset = Util.GetOffsetFromPointerChain(ui_element.base_offset, ui_element.steps)
    if(ui_element.type == "opcode" and ui_element.opcode ~= NOP) then
        WriteInstruction(offset, ui_element.opcode)
    elseif(ui_element.type == "flag") then
        EnableFlag(offset)
    end
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                Health Bar                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisableHealthBar()
    DisableUIElement(ui_elements.health_bar)
end

function UI.EnableHealthBar()
    EnableUIElement(ui_elements.health_bar)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                Power Bar                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisablePowerBar()
    DisableUIElement(ui_elements.power_bar)
end

function UI.EnablePowerBar()
    EnableUIElement(ui_elements.power_bar)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                              Experience Bars                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisableMainExpBar()
    DisableUIElement(ui_elements.main_exp_bar)
end

function UI.EnableMainExpBar()
    EnableUIElement(ui_elements.main_exp_bar)
end

function UI.DisableSecondaryExpBar()
    DisableUIElement(ui_elements.secondary_exp_bar)
end

function UI.EnableSecondaryExpBar()
    EnableUIElement(ui_elements.secondary_exp_bar)
end

function UI.DisableExperienceBars()
    UI.DisableMainExpBar()
    UI.DisableSecondaryExpBar()
end

function UI.EnableExperienceBars()
    UI.EnableMainExpBar()
    UI.EnableSecondaryExpBar()
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                 Compass                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
function UI.DisableCompass()
    DisableUIElement(ui_elements.compass_face)
    DisableUIElement(ui_elements.compass_back)
end

function UI.EnableCompass()
    EnableUIElement(ui_elements.compass_face)
    EnableUIElement(ui_elements.compass_back)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                             Target Nameplate                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
function UI.DisableTargetNameplate()
    DisableUIElement(ui_elements.target_nameplate)
end

function UI.EnableTargetNameplate()
    EnableUIElement(ui_elements.target_nameplate)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Group Display                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- The panel listing group member names and health bars
function UI.DisableGroupMemberPanel()
    DisableUIElement(ui_elements.group_member_panel)
end

function UI.EnableGroupMemberPanel()
    EnableUIElement(ui_elements.group_member_panel)
end

-- The colored group member position markers drawn around the compass
function UI.DisableGroupCompassMarkers()
    DisableUIElement(ui_elements.group_compass_marks)
end

function UI.EnableGroupCompassMarkers()
    EnableUIElement(ui_elements.group_compass_marks)
end

-- Convenience wrappers to toggle all group UI at once
function UI.DisableGroupDisplay()
    UI.DisableGroupMemberPanel()
    UI.DisableGroupCompassMarkers()
end

function UI.EnableGroupDisplay()
    UI.EnableGroupMemberPanel()
    UI.EnableGroupCompassMarkers()
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                                 Pet Panel                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisablePetPanel()
    DisableUIElement(ui_elements.pet_panel)
end

function UI.EnablePetPanel()
    EnableUIElement(ui_elements.pet_panel)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                              Active Effects                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisableActiveEffectsDisplay()
    DisableUIElement(ui_elements.active_effects)
end

function UI.EnableActiveEffectsDisplay()
    EnableUIElement(ui_elements.active_effects)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Ability Bar                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisableAbilityBar()
    DisableUIElement(ui_elements.ability_bar)
end

function UI.EnableAbilityBar()
    EnableUIElement(ui_elements.ability_bar)
end

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║                               Chat Window                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

function UI.DisableChatWindow()
    DisableUIElement(ui_elements.chat_window)
end

function UI.EnableChatWindow()
    EnableUIElement(ui_elements.chat_window)
end

function UI.DisableUI()
    UI.DisableHealthBar()
    UI.DisablePowerBar()
    UI.DisableExperienceBars()
    UI.DisableCompass()
    UI.DisableTargetNameplate()
    UI.DisableGroupDisplay()
    UI.DisablePetPanel()
    UI.DisableActiveEffectsDisplay()
    UI.DisableAbilityBar()
    UI.DisableChatWindow()
end

function UI.EnableUI()
    UI.EnableHealthBar()
    UI.EnablePowerBar()
    UI.EnableExperienceBars()
    UI.EnableCompass()
    UI.EnableTargetNameplate()
    UI.EnableGroupDisplay()
    UI.EnablePetPanel()
    UI.EnableActiveEffectsDisplay()
    UI.EnableAbilityBar()
    UI.EnableChatWindow()
end

return UI