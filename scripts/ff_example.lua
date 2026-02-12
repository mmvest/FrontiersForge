local Util = require("frontiers_forge.util")         -- Access utility functions
local UI = require("frontiers_forge.ui")           -- Access UI elements
local Player = require("frontiers_forge.player")     -- Access Player variables
local EntityList = require("frontiers_forge.entity_list") -- Access Entity List Variables
local Input = require("frontiers_forge.input")       -- Access input variables
local Camera = require("frontiers_forge.camera")     -- Access camera variables
local Chat = require("frontiers_forge.chat")                -- Access chat messages
local AbilityList = require("frontiers_forge.ability_list") -- Access abilities list
local AbilityBar = require("frontiers_forge.ability_bar")   -- Access ability bar

local function DisplayUtilFunctions()
    if ImGui.CollapsingHeader("Util Functions") then
        ImGui.Text(string.format("EEmem: 0x%08X", Util.EEmem()))
        ImGui.Text("GetExpRequiredForLevel:" .. tostring(Util.GetExpRequiredForLevel(Player.GetLevel())))
        ImGui.Text("IsInGame: " .. tostring(Util.IsInGame()))
        ImGui.Text("IsStartMenuOpen: " .. tostring(Util.IsStartMenuOpen()))
    end
end

local function DisplayUiFunctions()
    if ImGui.CollapsingHeader("UI Functions") then
        
        ImGui.Text("Health Bar")
        if ImGui.Button("Disable Health Bar") then
            UI.DisableHealthBar()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Health Bar") then
            UI.EnableHealthBar()
        end

        ImGui.Text("Power Bar")
        if ImGui.Button("Disable Power Bar") then
            UI.DisablePowerBar()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Power Bar") then
            UI.EnablePowerBar()
        end

        ImGui.Text("Experience Bars")
        if ImGui.Button("Disable Main Experience Bar") then
            UI.DisableMainExpBar()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Main Experience Bar") then
            UI.EnableMainExpBar()
        end
        if ImGui.Button("Disable Secondary Experience Bar") then
            UI.DisableSecondaryExpBar()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Secondary Experience Bar") then
            UI.EnableSecondaryExpBar()
        end
        if ImGui.Button("Disable Experience Bars") then
            UI.DisableExperienceBars()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Experience Bars") then
            UI.EnableExperienceBars()
        end

        ImGui.Text("Compass")
        if ImGui.Button("Disable Compass") then
            UI.DisableCompass()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Compass") then
            UI.EnableCompass()
        end

        ImGui.Text("Target Nameplate")
        if ImGui.Button("Disable Target Nameplate") then
            UI.DisableTargetNameplate()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Target Nameplate") then
            UI.EnableTargetNameplate()
        end

        ImGui.Text("Active Effects Display")
        if ImGui.Button("Disable Active Effects Display") then
            UI.DisableActiveEffectsDisplay()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Active Effects Display") then
            UI.EnableActiveEffectsDisplay()
        end

        ImGui.Text("Ability Bar")
        if ImGui.Button("Disable Ability Bar") then
            UI.DisableAbilityBar()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Ability Bar") then
            UI.EnableAbilityBar()
        end
        
        ImGui.Text("Chat Window")
        if ImGui.Button("Disable Chat Window") then
            UI.DisableChatWindow()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Chat Window") then
            UI.EnableChatWindow()
        end

        ImGui.Text("General")
        if ImGui.Button("Disable UI") then
            UI.DisableUI()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable UI") then
            UI.EnableUI()
        end
    end
end

local function DisplayPlayerFunctions()
    if ImGui.CollapsingHeader("Player Functions") then
        ImGui.Text("GetName: " .. Player.GetName())
        ImGui.Text("GetLevel: " .. Player.GetLevel())
        ImGui.Text("GetExp: " .. Player.GetExp())
        ImGui.Text("GetExpDebt: " .. Player.GetExpDebt())
        ImGui.Text("GetTotalStr: " .. Player.GetTotalStr())
        ImGui.Text("GetTotalSta: " .. Player.GetTotalSta())
        ImGui.Text("GetTotalAgi: " .. Player.GetTotalAgi())
        ImGui.Text("GetTotalDex: " .. Player.GetTotalDex())
        ImGui.Text("GetTotalWis: " .. Player.GetTotalWis())
        ImGui.Text("GetTotalInt: " .. Player.GetTotalInt())
        ImGui.Text("GetTotalCha: " .. Player.GetTotalCha())
        ImGui.Text("GetBaseStr: " .. Player.GetBaseStr())
        ImGui.Text("GetBaseSta: " .. Player.GetBaseSta())
        ImGui.Text("GetBaseAgi: " .. Player.GetBaseAgi())
        ImGui.Text("GetBaseDex: " .. Player.GetBaseDex())
        ImGui.Text("GetBaseWis: " .. Player.GetBaseWis())
        ImGui.Text("GetBaseInt: " .. Player.GetBaseInt())
        ImGui.Text("GetBaseCha: " .. Player.GetBaseCha())
        ImGui.Text("GetCurrentHp: " .. Player.GetCurrentHp())
        ImGui.Text("GetMaxHp: " .. Player.GetMaxHp())
        ImGui.Text("GetBaseHp: " .. Player.GetBaseHp())
        ImGui.Text("GetCurrentPwr: " .. Player.GetCurrentPwr())
        ImGui.Text("GetMaxPwr: " .. Player.GetMaxPwr())
        ImGui.Text("GetBasePwr: " .. Player.GetBasePwr())
        ImGui.Text("GetAc: " .. Player.GetAc())
        ImGui.Text("GetBaseResist: " .. Player.GetBaseResist())
        ImGui.Text("GetPoisonResistBuff: " .. Player.GetPoisonResistBuff())
        ImGui.Text("GetDiseaseResistBuff: " .. Player.GetDiseaseResistBuff())
        ImGui.Text("GetFireResistBuff: " .. Player.GetFireResistBuff())
        ImGui.Text("GetColdResistBuff: " .. Player.GetColdResistBuff())
        ImGui.Text("GetLightningResistBuff: " .. Player.GetLightningResistBuff())
        ImGui.Text("GetArcaneResistBuff: " .. Player.GetArcaneResistBuff())
        ImGui.Text("GetCMs: " .. Player.GetCMs())
        ImGui.Text("GetCMsSpent: " .. Player.GetCMsSpent())
        ImGui.Text("GetCMPct: " .. Player.GetCMPct())
        
        local coords = Player.GetCoordinates()
        ImGui.Text(string.format("GetCoordinates: x = %.2f, y = %.2f, z = %.2f", coords.x, coords.y, coords.z))
        
        ImGui.Text("GetTargetEntityId: " .. Player.GetTargetEntityId())
    end
end

local function DisplayEntityListFunctions()
    if ImGui.CollapsingHeader("Entity List Functions") then
        local entity = EntityList.GetEntityById(Player.GetTargetEntityId())
        if entity == nil then
            entity = { id = 0, percent_hp = 0, x = 0, y = 0, z = 0, name = "No entity selected", level = 0 }
        end
        if ImGui.TreeNode("GetEntityById: " .. entity.name .. " (ID: " .. entity.id .. ")") then
            -- Inside the tree node, show the entity stats
            ImGui.Text("Name: " .. entity.name)
            ImGui.Text("ID: " .. entity.id)
            ImGui.Text("Level: " .. entity.level)
            ImGui.Text("HP: " .. entity.percent_hp .. "%")
            ImGui.Text(string.format("Coordinates: x = %.2f, y = %.2f, z = %.2f", entity.x, entity.y, entity.z))

            -- End the tree node
            ImGui.TreePop()
        end
        
        entity = EntityList.GetEntityByIndex(0)
        if entity == nil then
            entity = { id = 0, percent_hp = 0, x = 0, y = 0, z = 0, name = "No entity", level = 0 }
        end
        if ImGui.TreeNode("GetEntityByIndex: " .. entity.name .. " (ID: " .. entity.id .. ")") then
            -- Inside the tree node, show the entity stats
            ImGui.Text("Name: " .. entity.name)
            ImGui.Text("ID: " .. entity.id)
            ImGui.Text("Level: " .. entity.level)
            ImGui.Text("HP: " .. entity.percent_hp .. "%")
            ImGui.Text(string.format("Coordinates: x = %.2f, y = %.2f, z = %.2f", entity.x, entity.y, entity.z))

            -- End the tree node
            ImGui.TreePop()
        end

        local entities = EntityList.GetAllEntities()
        if entities == nil then
            entities = {{ id = 0, percent_hp = 0, x = 0, y = 0, z = 0, name = "No entities around", level = 0 }}
        end
        for index = 1, #entities do
            entity = entities[index]
            -- Display the tree node with the entity name and ID
            if ImGui.TreeNode(index .. ". " ..entity.name .. " (ID: " .. entity.id .. ")") then
                -- Inside the tree node, show the entity stats
                ImGui.Text("Name: " .. entity.name)
                ImGui.Text("ID: " .. entity.id)
                ImGui.Text("Level: " .. entity.level)
                ImGui.Text("HP: " .. entity.percent_hp .. "%")
                ImGui.Text(string.format("Coordinates: x = %.2f, y = %.2f, z = %.2f", entity.x, entity.y, entity.z))

                -- End the tree node
                ImGui.TreePop()
            end
        end
    end
end

local function DisplayInputFunctions()
    if ImGui.CollapsingHeader("Input Functions") then
        local raw_analog = Input.GetRawAnalogStickState()
        ImGui.Text(string.format("GetRawAnalogStickState: right_x: 0x%02X right_y: 0x%02X left_x: 0x%02X left_y: 0x%02X", raw_analog.right_x, raw_analog.right_y, raw_analog.left_x, raw_analog.left_y))
        
        local normalized_analog = Input.GetNormalizedAnalogStickState()
        ImGui.Text(string.format("GetNormalizedAnalogStickState: right_x: %3.2f right_y: %3.2f left_x: %3.2f left_y: %3.2f", normalized_analog.right_x, normalized_analog.right_y, normalized_analog.left_x, normalized_analog.left_y))
        
        for button, mask in pairs(Input.button_mask) do
            ImGui.Text("IsButtonPressed(" .. button .. "): " .. tostring(Input.IsButtonPressed(mask)))
        end
    end
end

local function DisplayCameraFunctions()
    if ImGui.CollapsingHeader("Camera Functions") then
        local camera = Camera.GetCoordinates()
        ImGui.Text(string.format("GetCoordinates: x: %.2f y: %.2f z: %.2f", camera.x, camera.y, camera.z))
        ImGui.Text(string.format("GetFacingRadians: %.04f (North = 0, West = pi/2, South = pi, East = -pi/2)", Camera.GetFacingRadians()))
        ImGui.Text(string.format("GetFacingDegrees: %.04f", tostring(Camera.GetFacingDegrees())))
        ImGui.Text("[+] I hope to add more -- specifically unlocking/changing the cameras anchor point (Maybe get vertical camera movement??) ")
    end
end

demo_chat_state = demo_chat_state or {
    last_contents = nil,
    last_type = nil
}

local function DisplayChatFunctions()
    if ImGui.CollapsingHeader("Chat Functions") then
        local msg_contents, msg_type = Chat.GetNextMessage()
        if msg_contents ~= "" then
            demo_chat_state.last_contents = msg_contents
            demo_chat_state.last_type = msg_type
        end

        if demo_chat_state.last_contents == nil or demo_chat_state.last_contents == "" then
            ImGui.TextUnformatted("(no messages)")
        else
            ImGui.PushTextWrapPos(0.0)
            ImGui.Text("GetNextMessage.msg_contents: " .. demo_chat_state.last_contents)
            ImGui.PopTextWrapPos()
            ImGui.Text("GetNextMessage.msg_type: " .. demo_chat_state.last_type)
            ImGui.Text("GetMessageTypeString: " .. Chat.GetMessageTypeString(demo_chat_state.last_type))
        end
    end
end

local function DisplayAbilityListFunctions()
    if ImGui.CollapsingHeader("AbilityList and Ability Functions") then
        local index = 0 -- perhaps add functionality to be able to change which ability you get
        local selected_ability = AbilityList.GetAbilityByIndex(index)
        ImGui.Text("AbilityList.GetAbilityByIndex(" .. index .. "): ")
        ImGui.Text("    Ability Name: " .. selected_ability:GetName())
        ImGui.Text("    Description: " .. selected_ability:GetDescription())
        ImGui.Text("    Ability Index: " .. selected_ability:GetIndex())
        ImGui.Text("    Ability Level: " .. selected_ability:GetLevel())
        ImGui.Text("    Ability Range: " .. selected_ability:GetRange())
        ImGui.Text("    Cast Time: " .. selected_ability:GetCastTime())
        ImGui.Text("    Power Cost: " .. selected_ability:GetPwrCost())
        ImGui.Text("    Scope: " .. selected_ability:GetScope())
        ImGui.Text("    Cooldown: " .. selected_ability:GetCooldown())
        ImGui.Text("    Equip Requirements: " .. tostring(selected_ability:GetEquipRequirements()))
    end
end

local function DisplayToolbeltFunctions()
end

-- TODO: BROKEN
local function DisplayAbilityBarFunctions()
    if ImGui.CollapsingHeader("AbilityBar Functions") then
        for bar_index = 0, 1 do
            ImGui.Text("Ability Bar " .. bar_index .. ":")

            for slot_index = 0, AbilityBar.num_abilities - 1 do
                local ability_slot = AbilityBar.GetAbilitySlot(bar_index, slot_index)
                ImGui.Text("    AbilityBar.GetAbilitySlot(" .. slot_index .. "): ")
                ImGui.Text("        AbilitySlot:GetIconRef(): " .. tostring(ability_slot:GetIconRef()))
                ImGui.Text("        AbilitySlot:GetAbilityIndex(): " .. tostring(ability_slot:GetAbilityIndex()))

                local ability = ability_slot:GetAbility()
                if ability then
                    ImGui.Text("        AbilitySlot:GetAbility(): ")
                    ImGui.Text("            Ability:GetName(): " .. ability:GetName())
                else
                    ImGui.Text("            No Ability Found")
                end
            end
        end
    end
end


-- Begin a new ImGui window
if ImGui.Begin("Frontiers Forge Test Window") then

    DisplayUtilFunctions()

    DisplayUiFunctions()

    DisplayPlayerFunctions()

    DisplayEntityListFunctions()

    DisplayInputFunctions()

    DisplayCameraFunctions()

    DisplayChatFunctions()

    DisplayAbilityListFunctions()

    DisplayAbilityBarFunctions()
end
-- End the window
ImGui.End()
