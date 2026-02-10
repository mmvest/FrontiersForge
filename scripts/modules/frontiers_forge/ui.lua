local Util = require("frontiers_forge.util")

-- This offset is the base of the UI rendering code-block for the 9VIWndGame window.
-- This window handles compass, health, power, experience, and target nameplate.
-- Since the code is an overlay, it can be written anywhere in memory.
-- Due to this, we have to use a pointer chain to get the location.
local wnd_game_offset = Util.GetOffsetFromPointerChain(0x14E200, {0x190 , 0x53C, 0x20, 0x1C})

-- This offset is the base of the UI Rendering code-block for 9VIWndChat window.
-- This window handles the chat pop-up for typing, the players active effects (buffs),
-- the ability bar, and the chat window in the bottom right.
local wnd_chat_offset = Util.GetOffsetFromPointerChain(0x4E37F4, {0x14, 0x688, 0x20, 0x1C})

local NOP = 0x00000000

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
    chat_window         = { type = "opcode", base_offset = wnd_chat_offset, steps = {0xE8}, opcode = NOP},
    active_effects      = { type = "flag", base_offset = 0x4E37F4, steps = {0x14, 0x74C}},
    ability_bar         = { type = "flag", base_offset = 0x4E37F4, steps = {0x1C}}
}

local UI = {}

local function NopInstruction(offset)
    Util.WriteToOffset(offset, "uint32_t", NOP)
end

local function RestoreInstruction(offset, opcode)
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
        local curr_opcode = Util.ReadFromOffset(offset, "uint32_t")
        if(curr_opcode ~= NOP) then
            ui_element.opcode = curr_opcode
        end
        NopInstruction(offset)
    elseif(ui_element.type == "flag") then
        DisableFlag(offset)
    end
end

local function EnableUIElement(ui_element)
    local offset = Util.GetOffsetFromPointerChain(ui_element.base_offset, ui_element.steps)
    if(ui_element.type == "opcode" and ui_element.opcode ~= NOP) then
        RestoreInstruction(offset, ui_element.opcode)
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
    UI.EnableActiveEffectsDisplay()
    UI.EnableAbilityBar()
    UI.EnableChatWindow()
end

return UI