local Util = require("frontiers_forge.util")         -- Access utility functions
local UI = require("frontiers_forge.ui")           -- Access UI elements
local Player = require("frontiers_forge.player")     -- Access Player variables
local EntityList = require("frontiers_forge.entity_list") -- Access Entity List Variables
local Input = require("frontiers_forge.input")       -- Access input variables
local Camera = require("frontiers_forge.camera")     -- Access camera variables
local Chat = require("frontiers_forge.chat")                -- Access chat messages
local Ability = require("frontiers_forge.ability")         -- Ability record accessors + Scope enum
local AbilityList = require("frontiers_forge.ability_list") -- Access abilities list
local AbilityBar = require("frontiers_forge.ability_bar")   -- Access ability bar
local Group = require("frontiers_forge.group")              -- Access group info
local Combat = require("frontiers_forge.combat")             -- Combat event hook (damage/heal capture)
local QuestLog = require("frontiers_forge.quest_log")        -- Access the quest log
local Icon = require("frontiers_forge.icon")                 -- Decode game icons into ImGui textures
local Effects = require("frontiers_forge.effects")           -- Player's active effects (buffs/debuffs)
local Inventory = require("frontiers_forge.inventory")       -- Access inventory items

local function NotInGameWarning()
    ImGui.Text("(not in game - load a character to see this section)")
end

local function DisplayUtilFunctions()
    if ImGui.CollapsingHeader("Util Functions") then
        ImGui.Text(string.format("EEmem: 0x%08X", Util.EEmem()))
        ImGui.Text("GetExpRequiredForLevel:" .. tostring(Util.GetExpRequiredForLevel(Player.GetLevel())))
        ImGui.Text("IsInGame: " .. tostring(Util.IsInGame()))
        ImGui.Text("IsStartMenuOpen: " .. tostring(Util.IsStartMenuOpen()))
        ImGui.Text("IsBattleMusicPlaying: " .. tostring(Util.IsBattleMusicPlaying()))
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

        ImGui.Text("Group Display")
        if ImGui.Button("Disable Group Member Panel") then
            UI.DisableGroupMemberPanel()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Group Member Panel") then
            UI.EnableGroupMemberPanel()
        end
        if ImGui.Button("Disable Group Compass Markers") then
            UI.DisableGroupCompassMarkers()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Group Compass Markers") then
            UI.EnableGroupCompassMarkers()
        end
        if ImGui.Button("Disable Group Display") then
            UI.DisableGroupDisplay()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Group Display") then
            UI.EnableGroupDisplay()
        end

        ImGui.Text("Pet Panel")
        if ImGui.Button("Disable Pet Panel") then
            UI.DisablePetPanel()
        end
        ImGui.SameLine()
        if ImGui.Button("Enable Pet Panel") then
            UI.EnablePetPanel()
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

local function DisplayEntityDetails(entity)
    ImGui.Text("Name: " .. entity:GetName())
    ImGui.Text("ID: " .. entity:GetId())
    ImGui.Text("Level: " .. entity:GetLevel())
    ImGui.Text("HP: " .. entity:GetHealthPercent() .. "%")
    local x, y, z = entity:GetPosition()
    ImGui.Text(string.format("Coordinates: x = %.2f, y = %.2f, z = %.2f", x, y, z))
    local player_coords = Player.GetCoordinates()
    ImGui.Text(string.format("Util.GetDistanceBetween(player, entity): %.2f", Util.GetDistanceBetween(player_coords, entity)))
    ImGui.Text("IsValid: " .. tostring(entity:IsValid()))

    -- Disposition towards the player. The server only sends this
    -- for the CURRENT TARGET, so every other entity shows nil / "Unknown".
    ImGui.Text("Disposition: " .. tostring(entity.disposition)
        .. " (" .. tostring(entity.disposition_name) .. ")")
    if entity.disposition ~= nil then
        -- UI.DrawDispositionIcon draws the same face icon the game's target
        -- nameplate uses for this disposition value.
        ImGui.SameLine()
        UI.DrawDispositionIcon(entity.disposition, 1.5)
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
        local target = EntityList.GetEntityById(Player.GetTargetEntityId())
        if target ~= nil then
            DisplayEntityDetails(target)
        else
            ImGui.Text("Current target: (nothing targeted)")
        end
    end
end

local function DisplayEntityListFunctions()
    if ImGui.CollapsingHeader("Entity List Functions") then
        local entity = EntityList.GetEntityById(Player.GetTargetEntityId())
        if entity ~= nil then
            if ImGui.TreeNode("GetEntityById: " .. entity.name .. " (ID: " .. entity.id .. ")") then
                DisplayEntityDetails(entity)

                ImGui.TreePop()
            end
        else
            ImGui.Text("GetEntityById: (no entity selected)")
        end

        entity = EntityList.GetEntityByIndex(0)
        if ImGui.TreeNode("GetEntityByIndex: " .. entity.name .. " (ID: " .. entity.id .. ")") then
            -- Inside the tree node, show the entity stats
            DisplayEntityDetails(entity)

            -- End the tree node
            ImGui.TreePop()
        end

        local entities = EntityList.GetAllEntities()
        for index = 1, #entities do
            entity = entities[index]
            -- Display the tree node with the entity name and ID
            if ImGui.TreeNode(index .. ". " ..entity.name .. " (ID: " .. entity.id .. ")") then
                -- Inside the tree node, show the entity stats
                DisplayEntityDetails(entity)

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

-- Reverse lookup for the Ability.Scope enum so we can show a friendly name
local function GetScopeName(scope)
    for name, value in pairs(Ability.Scope) do
        if value == scope then
            return name
        end
    end
    return "UNKNOWN (" .. tostring(scope) .. ")"
end

-- Shows every accessor an Ability object provides
local function DisplayAbilityDetails(ability)
    ImGui.Text("IsValid: " .. tostring(ability:IsValid()))
    ImGui.Text("GetId: " .. ability:GetId())
    ImGui.Text("GetName: " .. ability:GetName())
    ImGui.PushTextWrapPos(0.0)
    ImGui.Text("GetDescription: " .. ability:GetDescription())
    ImGui.PopTextWrapPos()
    ImGui.Text("GetDisplayIndex: " .. ability:GetDisplayIndex())
    ImGui.Text("GetSpellbookSlot: " .. ability:GetSpellbookSlot())
    ImGui.Text("GetLevel: " .. ability:GetLevel())
    ImGui.Text(string.format("GetRange: %.2f", ability:GetRange()))
    local range_target = EntityList.GetEntityById(Player.GetTargetEntityId())
    if range_target == nil then
        ImGui.Text("IsInRange: (nothing targeted)")
    else
        local in_range, distance = ability:IsInRange(Player.GetCoordinates(), range_target)
        if in_range then
            ImGui.TextColored(0.3, 1.0, 0.3, 1.0, string.format("IsInRange(player, target): true (distance %.2f)", distance))
        else
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, string.format("IsInRange(player, target): false (distance %.2f)", distance))
        end
    end
    ImGui.Text("GetCastTime: " .. ability:GetCastTime())
    ImGui.Text("GetPwrCost: " .. ability:GetPwrCost())
    ImGui.Text(string.format("GetIconBackgroundRef: %08X", ability:GetIconBackgroundRef()))
    ImGui.Text(string.format("GetIconForegroundRef: %08X", ability:GetIconForegroundRef()))
    local bg_texture, bg_w, bg_h = Icon.GetTexture(ability:GetIconBackgroundRef())
    local fg_texture, fg_w, fg_h = Icon.GetTexture(ability:GetIconForegroundRef())
    local icon_scale = 1.5
    if bg_texture or fg_texture then
        ImGui.Text(string.format("Icon (untrimmed, bg:%dx%d, fg:%dx%d):", bg_w, bg_h, fg_w, fg_h))
        ImGui.SameLine()
        local cursor_x, cursor_y = ImGui.GetCursorPos()
        if bg_texture then
            ImGui.Image(bg_texture, bg_w * icon_scale, bg_h * icon_scale)
        end
        if fg_texture then
            local offset_x = (bg_w - fg_w) * icon_scale / 2
            local offset_y = (bg_h - fg_h) * icon_scale / 2
            ImGui.SetCursorPos(cursor_x + offset_x, cursor_y + offset_y)
            ImGui.Image(fg_texture, fg_w * icon_scale, fg_h * icon_scale)
        end
    else
        ImGui.Text("Icon: (not found in the texture dictionary)")
    end

    -- Some icon surfaces carry large fully transparent margins, and some also
    -- pad the art with a flat filler color. trim_transparent crops away the
    -- transparent padding and trim_color additionally crops away the flat
    -- colored padding, detected from the image's outer border ring.
    local trimmed_bg_texture, trimmed_bg_w, trimmed_bg_h = Icon.GetTexture(ability:GetIconBackgroundRef(), {trim_transparent=true, trim_color=true})
    local trimmed_fg_texture, trimmed_fg_w, trimmed_fg_h = Icon.GetTexture(ability:GetIconForegroundRef(), {trim_transparent=true, trim_color=true})
    local icon_scale = 1.5
    if trimmed_bg_texture or trimmed_fg_texture then
        ImGui.Text(string.format("Icon (trimmed, bg:%dx%d, fg:%dx%d):", trimmed_bg_w, trimmed_bg_h, trimmed_fg_w, trimmed_fg_h))
        ImGui.SameLine()
        local cursor_x, cursor_y = ImGui.GetCursorPos()
        if trimmed_bg_texture then
            ImGui.Image(trimmed_bg_texture, trimmed_bg_w * icon_scale, trimmed_bg_h * icon_scale)
        end
        if trimmed_fg_texture then
            local offset_x = (trimmed_bg_w - trimmed_fg_w) * icon_scale / 2
            local offset_y = (trimmed_bg_h - trimmed_fg_h) * icon_scale / 2
            ImGui.SetCursorPos(cursor_x + offset_x, cursor_y + offset_y)
            ImGui.Image(trimmed_fg_texture, trimmed_fg_w * icon_scale, trimmed_fg_h * icon_scale)
        end
    else
        ImGui.Text("Icon: (not found in the texture dictionary)")
    end
    ImGui.Text("GetScope: " .. ability:GetScope() .. " (" .. GetScopeName(ability:GetScope()) .. ")")
    ImGui.Text("GetCooldown: " .. ability:GetCooldown())
    ImGui.Text(string.format("GetEquipRequirements: 0x%02X (bitmask)", ability:GetEquipRequirements()))
    ImGui.Text("IsOnCooldown: " .. tostring(ability:IsOnCooldown()))
    ImGui.Text("GetCooldownLockoutMs: " .. ability:GetCooldownLockoutMs())
end

demo_ability_state = demo_ability_state or {
    index = 1,
    id = 0
}

local function DisplayAbilityListFunctions()
    if ImGui.CollapsingHeader("AbilityList and Ability Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        -- AbilityList.GetCount(): how many abilities the player currently has
        local count = AbilityList.GetCount()
        ImGui.Text("AbilityList.GetCount(): " .. count)

        -- AbilityList.GetAbilityByIndex(index): raw array access.
        -- Valid indices are 1 .. GetCount() (index 0 is the list's sentinel).
        demo_ability_state.index = ImGui.SliderInt("index", demo_ability_state.index, 1, math.max(count, 1))
        local selected_ability = AbilityList.GetAbilityByIndex(demo_ability_state.index)
        if selected_ability and ImGui.TreeNode("AbilityList.GetAbilityByIndex(" .. demo_ability_state.index .. "): " .. selected_ability:GetName()) then
            DisplayAbilityDetails(selected_ability)
            ImGui.TreePop()
        end

        -- AbilityList.GetAbilityById(id): find an ability by its id
        demo_ability_state.id = ImGui.InputInt("id", demo_ability_state.id)
        local ability_by_id = AbilityList.GetAbilityById(demo_ability_state.id)
        if ability_by_id == nil then
            ImGui.Text("AbilityList.GetAbilityById(" .. demo_ability_state.id .. "): not found")
        elseif ImGui.TreeNode("AbilityList.GetAbilityById(" .. demo_ability_state.id .. "): " .. ability_by_id:GetName()) then
            DisplayAbilityDetails(ability_by_id)
            ImGui.TreePop()
        end

        -- AbilityList.Abilities(): iterate every ability the player has,
        -- in id-sorted order (same order the game itself enumerates them)
        if ImGui.TreeNode("AbilityList.Abilities() iterator") then
            for index, ability in AbilityList.Abilities() do
                if ImGui.TreeNode(index .. ". " .. ability:GetName() .. " (ID: " .. ability:GetId() .. ")") then
                    DisplayAbilityDetails(ability)
                    ImGui.TreePop()
                end
            end
            ImGui.TreePop()
        end
    end
end

local function DisplayToolbeltFunctions()
end

-- Live cooldown state for every ability on the hotbars. I wanted to demo how
-- you could use the cooldown functionality the API exposes. IsOnCooldown() tracks
-- the icon dimming on the hot bar and that starts the moment you press the button
-- to cast the spell/ability. GetCooldownLockoutMs() is the total lockout in ms
-- which is ((cast + recast) * 1000 + 300).The Client never counts it down, the
-- server will tell the client when the spell is ready to be used again.
--
-- Because the client stores no live countdown, remaining time is ESTIMATED
-- here. This section runs every frame, but the server's ready message may
-- arrive slightly before or after our estimate.
cooldown_watch_state = cooldown_watch_state or {}
local function UpdateCooldownTracking()
    if Util.IsInGame() == 0 then
        return
    end

    local now = os.clock()
    for bar_index = 0, AbilityBar.num_bars - 1 do
        for slot_index = 0, AbilityBar.GetSlotCount(bar_index) - 1 do
            local ability = AbilityBar.GetAbility(bar_index, slot_index)
            if ability ~= nil then
                local id = ability:GetId()
                if not ability:IsOnCooldown() then
                    -- Ability is ready; forget any tracked cooldown.
                    cooldown_watch_state[id] = nil
                elseif cooldown_watch_state[id] == nil then
                    -- Rising edge: first frame we see this ability on cooldown.
                    cooldown_watch_state[id] = now
                end
            end
        end
    end
end

local function DisplayCooldownWatch()
    if ImGui.CollapsingHeader("Cooldown Watch") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        local now = os.clock()

        for bar_index = 0, AbilityBar.num_bars - 1 do
            for slot_index = 0, AbilityBar.GetSlotCount(bar_index) - 1 do
                local ability = AbilityBar.GetAbility(bar_index, slot_index)
                if ability ~= nil then
                    local started = cooldown_watch_state[ability:GetId()]

                    if not ability:IsOnCooldown() then
                        ImGui.Text(string.format("bar %d slot %d  %-24s ready",
                            bar_index, slot_index, ability:GetName()))
                    elseif started == nil then
                        -- On cooldown but we never saw the rising edge (cooldown
                        -- began before this script loaded), so no estimate exists.
                        ImGui.Text(string.format("bar %d slot %d  %-24s on cooldown (start not observed)",
                            bar_index, slot_index, ability:GetName()))
                    else
                        local elapsed        = now - started
                        local cast_left      = math.max(ability:GetCastTime() - elapsed, 0)
                        local cooldown_left  = math.max((ability:GetCooldownLockoutMs() / 1000) - elapsed, 0)

                        local status
                        if cast_left > 0 then
                            status = string.format("casting %.1fs   cooldown %.1fs", cast_left, cooldown_left)
                        elseif cooldown_left > 0 then
                            status = string.format("cooldown %.1fs", cooldown_left)
                        else
                            status = "waiting on server ready message"
                        end

                        ImGui.Text(string.format("bar %d slot %d  %-24s %s",
                            bar_index, slot_index, ability:GetName(), status))
                    end
                end
            end
        end
    end
end

local function DisplayAbilityBarFunctions()
    if ImGui.CollapsingHeader("AbilityBar Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        -- The game keeps AbilityBar.num_bars (3) hotbars; bar 0 is the main
        -- ability bar. Each bar's live slot count can vary (bar 0: 5-9).
        ImGui.Text("AbilityBar.num_bars: " .. AbilityBar.num_bars)

        -- The game tracks which bar is selected and, per bar, which slot its
        -- cursor is on (the slot W/S move during gameplay).
        ImGui.Text("AbilityBar.GetSelectedBarIndex(): " .. tostring(AbilityBar.GetSelectedBarIndex()))

        for bar_index = 0, AbilityBar.num_bars - 1 do
            local slot_count = AbilityBar.GetSlotCount(bar_index)
            if ImGui.TreeNode("Bar " .. bar_index .. " - AbilityBar.GetSlotCount(" .. bar_index .. "): " .. slot_count) then
                ImGui.Text("AbilityBar.GetSelectedSlotIndex(" .. bar_index .. "): "
                    .. tostring(AbilityBar.GetSelectedSlotIndex(bar_index)))
                for slot_index = 0, slot_count - 1 do
                    local ability_slot = AbilityBar.GetAbilitySlot(bar_index, slot_index)
                    if ImGui.TreeNode("AbilityBar.GetAbilitySlot(" .. bar_index .. ", " .. slot_index .. ")") then
                        ImGui.Text("AbilitySlot:IsEmpty(): " .. tostring(ability_slot:IsEmpty()))
                        ImGui.Text("AbilitySlot:GetIconRef(): " .. tostring(ability_slot:GetIconRef()))

                        -- Ability slots carry a texture dictionary hash in their icon
                        -- ref, and the item hotbar slots do not. They instead have
                        -- hardcoded textures for them.
                        if not ability_slot:IsEmpty() then
                            local icon_texture, icon_w, icon_h
                            local icon_ref = ability_slot:GetIconRef()
                            if icon_ref ~= -1 then
                                icon_texture, icon_w, icon_h = Icon.GetTexture(icon_ref)
                            else
                                local tex_id = AbilityBar.GetSlotUITexId(slot_index)
                                ImGui.Text("AbilityBar.GetSlotUITexId(" .. slot_index .. "): " .. tostring(tex_id))
                                icon_texture, icon_w, icon_h = Icon.GetUITexture(tex_id)
                            end
                            if icon_texture then
                                ImGui.Text("Slot icon:")
                                ImGui.SameLine()
                                ImGui.Image(icon_texture, icon_w * 1.5, icon_h * 1.5)
                            else
                                ImGui.Text("Slot icon: (unavailable)")
                            end
                        end
                        -- GetAbilityIndex() returns nil when the slot doesn't
                        -- reference the player's ability list (empty slot or
                        -- other source type)
                        ImGui.Text("AbilitySlot:GetAbilityIndex(): " .. tostring(ability_slot:GetAbilityIndex()))

                        -- AbilitySlot:GetAbility() resolves the slot into a full
                        -- Ability object (see the Ability accessors above), and is
                        -- also available as AbilityBar.GetAbility(bar, slot)
                        local ability = ability_slot:GetAbility()
                        -- Item hotbar slots (the special items bar) resolve into
                        -- Item objects instead, via AbilitySlot:GetItem() or
                        -- AbilityBar.GetItem(bar, slot).
                        local item = ability_slot:GetItem()
                        if ability then
                            if ImGui.TreeNode("AbilitySlot:GetAbility(): " .. ability:GetName()) then
                                DisplayAbilityDetails(ability)
                                ImGui.TreePop()
                            end
                        elseif item then
                            if ImGui.TreeNode("AbilitySlot:GetItem(): " .. item:GetName()) then
                                ImGui.Text("Item:GetName(): " .. item:GetName())
                                ImGui.Text("Item:GetDescription(): " .. item:GetDescription())
                                ImGui.Text("Item:GetAmount(): " .. tostring(item:GetAmount()))
                                ImGui.Text("Item:GetLevelReq(): " .. tostring(item:GetLevelReq()))
                                ImGui.Text("Item:GetEquippedStatus(): " .. item:GetEquippedStatus())
                                ImGui.TreePop()
                            end
                        else
                            ImGui.Text("AbilitySlot:GetAbility(): nil (empty slot)")
                        end
                        ImGui.TreePop()
                    end
                end
                ImGui.TreePop()
            end
        end
    end
end

local function DisplayEffectsFunctions()
    if ImGui.CollapsingHeader("Effects Functions (buffs/debuffs)") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        -- Effects mirrors the icon row right of the health/power/exp bars
        -- (also listed on the pause menu status page). Max 8 entries.
        ImGui.Text("Effects.GetCount(): " .. Effects.GetCount() .. " / " .. Effects.max_effects)

        -- Effects.All() iterates { index, icon_ref, name }; GetIconRef/GetName/
        -- GetEffect also work for direct access.
        for index, effect in Effects.All() do
            local texture, w, h = Icon.GetTexture(effect.icon_ref, {trim_transparent=true})
            if texture then
                ImGui.Image(texture, w * 1.5, h * 1.5)
                ImGui.SameLine()
            end
            ImGui.Text(index .. ". " .. tostring(effect.name)
                .. string.format(" (icon %08X)", effect.icon_ref))
        end
    end
end

local function DisplayInventoryFunctions()
    if ImGui.CollapsingHeader("Inventory Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        ImGui.Text("Inventory.GetTunar(): " .. Inventory.GetTunar())
        ImGui.Text("Inventory.SlotsUsed(): " .. Inventory.SlotsUsed())
        ImGui.Text("Inventory.SlotsRemaining(): " .. Inventory.SlotsRemaining())

        for _, item in ipairs(Inventory.GetItems()) do
            local texture, w, h = Icon.GetTexture(item:GetIconRef(), {trim_transparent=true})
            if texture then
                ImGui.Image(texture, w * 1.5, h * 1.5)
                ImGui.SameLine()
            end
            ImGui.Text(item.idx .. ". " .. item.name
                .. " x" .. item.amount
                .. " (" .. item.equipped_status .. ")"
                .. string.format(" (icon %08X)", item.icon_ref))
            local description = item:GetDescription()
            if description ~= "" and ImGui.IsItemHovered() then
                ImGui.SetTooltip(description)
            end
        end
    end
end

local function DisplayQuestLogFunctions()
    if ImGui.CollapsingHeader("QuestLog Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        -- QuestLog.GetCount(): how many quests are in the log (max 8)
        local count = QuestLog.GetCount()
        ImGui.Text("QuestLog.GetCount(): " .. count .. " / " .. QuestLog.max_quests)

        -- QuestLog.Quests(): iterate the log in display order. Indices are
        -- zero based, matching the game's own quest log window.
        for index, quest in QuestLog.Quests() do
            ImGui.Text(index .. ". " .. quest:GetName())
        end

        -- QuestLog.GetQuestByIndex(index) also works for direct access,
        -- returning nil when the index is out of range.
    end
end

local function DisplayGroupMemberDetails(member)
    ImGui.Text("GetEntityId: " .. member:GetEntityId())
    ImGui.Text("GetName: " .. member:GetName())
    ImGui.Text("IsActive: " .. tostring(member:IsActive()))

    -- Health accessors return nil when the game doesn't currently know this
    -- member's health.
    local hp255 = member:GetHealthPercent255()
    if hp255 == nil then
        ImGui.Text("GetHealthPercent255: nil (health not known)")
        ImGui.Text("GetHealthPercent: nil (health not known)")
    else
        ImGui.Text("GetHealthPercent255: " .. hp255)
        ImGui.Text(string.format("GetHealthPercent: %.1f%%", member:GetHealthPercent()))
    end

    -- Last position the server reported. May be stale if the member's
    -- entity isn't loaded nearby.
    local coords = member:GetCoordinates()
    ImGui.Text(string.format("GetCoordinates: x = %.2f, y = %.2f, z = %.2f", coords.x, coords.y, coords.z))
end

local function DisplayGroupFunctions()
    if ImGui.CollapsingHeader("Group Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        ImGui.Text("Group.IsInGroup(): " .. tostring(Group.IsInGroup()))
        ImGui.Text("Group.IsSelfLeader(): " .. tostring(Group.IsSelfLeader()))

        -- Member count includes yourself, and is 0 when not in a group.
        local count = Group.GetMemberCount()
        ImGui.Text("Group.GetMemberCount(): " .. count)

        if count == 0 then
            ImGui.Text("(join a group to see member examples)")
            return
        end

        local first_member = Group.GetMemberByIndex(0)
        if first_member and ImGui.TreeNode("Group.GetMemberByIndex(0): " .. first_member:GetName()) then
            DisplayGroupMemberDetails(first_member)
            ImGui.TreePop()
        end

        if ImGui.TreeNode("Group.Members() iterator") then
            for index, member in Group.Members() do
                if ImGui.TreeNode(index .. ". " .. member:GetName() .. " (ID: " .. member:GetEntityId() .. ")") then
                    DisplayGroupMemberDetails(member)
                    ImGui.TreePop()
                end
            end
            ImGui.TreePop()
        end
    end
end

ff_combat_meter = ff_combat_meter or {
    damage_dealt = 0,
    damage_taken = 0,
    healing_received = 0,
    hits_dealt = 0,
    hits_taken = 0,
    log = {},
    subscribed = false,
    last_damage_ms = 0,
}

-- Combat reports individual events, it does not decide when a fight starts or
-- ends. That is deliberate, since the right answer depends on the mod: how long
-- a lull ends a fight, and whether healing should hold one open. Deriving it is
-- a few lines, and this is what they look like.
local IDLE_TIMEOUT_MS = 5000

-- Combat.lua owns the hook and publishes what it captures, so a mod subscribes to
-- the events it cares about instead of draining the ring itself. Several mods
-- can watch the same events this way.
local COMBAT_OWNER = "ff_example"

local function SubscribeToCombatEvents()
    local meter = ff_combat_meter

    local function Log(event, label)
        meter.log[#meter.log + 1] = string.format(
            "#%d  %s  attacker=%d  defender=%d  amount=%d",
            event.seq, label, event.attacker_id, event.defender_id, event.amount)
        while #meter.log > 20 do
            table.remove(meter.log, 1)
        end
    end

    Combat.On(COMBAT_OWNER, Combat.Events.OnDamageDealt, function(event)
        meter.damage_dealt = meter.damage_dealt + math.abs(event.amount)
        meter.hits_dealt = meter.hits_dealt + 1
        -- Damage is what this mod counts as fighting. Healing deliberately does
        -- not, since healing up after a pull would hold the fight open.
        meter.last_damage_ms = math.floor(ImGui.GetTime() * 1000)
        Log(event, "dealt")
    end)

    Combat.On(COMBAT_OWNER, Combat.Events.OnDamageReceived, function(event)
        meter.damage_taken = meter.damage_taken + math.abs(event.amount)
        meter.hits_taken = meter.hits_taken + 1
        meter.last_damage_ms = math.floor(ImGui.GetTime() * 1000)
        Log(event, "taken")
    end)

    Combat.On(COMBAT_OWNER, Combat.Events.OnHealingReceived, function(event)
        meter.healing_received = meter.healing_received + math.abs(event.amount)
        Log(event, "healed")
    end)

    meter.subscribed = true
end

if not ff_combat_meter.subscribed then
    SubscribeToCombatEvents()
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, function()
        Combat.Off(COMBAT_OWNER)
        Combat.Release(COMBAT_OWNER)
    end)
end

-- Save and load demo using UiForge profiles. The Save callback returns a
-- plain data table which UiForge captures into the profile when you use
-- File then Save Profile in the UiForge Settings window. The profile is
-- written to scripts\profiles\<name>.profile.lua along with the set of
-- enabled scripts and the window layout. When you apply a profile through
-- File then Select Profile, the Load callback receives this script's saved
-- table back after the script has run once.
ff_save_demo = ff_save_demo or {
    note = "",
    counter = 0,
    registered = false,
    last_event = "(nothing saved or loaded yet)"
}

if not ff_save_demo.registered then
    UiForge.RegisterCallback(UiForge.CallbackType.Save, function()
        ff_save_demo.last_event = "saved"
        return { note = ff_save_demo.note, counter = ff_save_demo.counter }
    end)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, function(state)
        ff_save_demo.note = tostring(state.note or "")
        ff_save_demo.counter = tonumber(state.counter) or 0
        ff_save_demo.last_event = "loaded"
    end)
    ff_save_demo.registered = true
end

local function DisplaySaveLoadFunctions()
    if ImGui.CollapsingHeader("Save and Load Callbacks (Profiles)") then
        ImGui.Text("Use File > Save Profile / Select Profile in the UiForge Settings window.")
        ImGui.Text("Profiles are stored in: " .. UiForge.profiles_path)
        ImGui.Text("This script's state is saved inside the profile under its file name.")
        ff_save_demo.note = ImGui.InputText("note to persist", ff_save_demo.note)
        if ImGui.Button("Increment counter") then
            ff_save_demo.counter = ff_save_demo.counter + 1
        end
        ImGui.SameLine()
        ImGui.Text("counter: " .. ff_save_demo.counter)
        ImGui.Text("Last event: " .. ff_save_demo.last_event)
    end
end

local function DisplayCombatFunctions()
    -- Driven every frame even when the header is collapsed, so the 64 entry
    -- ring buffer never overruns. Any subscriber may drive it, a second call in
    -- the same frame simply finds the ring already empty.
    local meter = ff_combat_meter
    Combat.Update()

    if ImGui.CollapsingHeader("Combat Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        ImGui.Text("Combat.IsHookInstalled(): " .. tostring(Combat.IsHookInstalled()))
        ImGui.Text("Combat.GetOwnerCount(): " .. Combat.GetOwnerCount())
        -- The hook is shared, so a mod claims and releases it rather than
        -- installing and uninstalling. It comes up on the first claim and goes
        -- away only once the last one is dropped.
        if not Combat.HasClaim(COMBAT_OWNER) then
            if ImGui.Button("Combat.Acquire()") then
                local ok, err = Combat.Acquire(COMBAT_OWNER)
                meter.last_error = ok and nil or err
            end
        else
            -- Releasing drops only this script's claim. The hook stays up if
            -- another mod is still holding one.
            if ImGui.Button("Combat.Release()") then
                Combat.Release(COMBAT_OWNER)
            end
        end
        if meter.last_error then
            ImGui.Text("acquire failed: " .. meter.last_error)
        end

        ImGui.Text("Combat.GetEventCount(): " .. Combat.GetEventCount())
        ImGui.Text("Combat.GetDroppedCount(): " .. Combat.GetDroppedCount())
        -- Derived here, not reported by Combat. See IDLE_TIMEOUT_MS above.
        local idle_ms = math.floor(ImGui.GetTime() * 1000) - meter.last_damage_ms
        local fighting = meter.last_damage_ms > 0 and idle_ms < IDLE_TIMEOUT_MS
        ImGui.Text(string.format("Fighting (derived by this mod): %s", tostring(fighting)))

        ImGui.Text(string.format("Damage dealt: %d (%d hits)", meter.damage_dealt, meter.hits_dealt))
        ImGui.Text(string.format("Damage taken: %d (%d hits)", meter.damage_taken, meter.hits_taken))
        ImGui.Text(string.format("Healing received: %d", meter.healing_received))

        if ImGui.Button("Reset meter") then
            meter.damage_dealt, meter.damage_taken, meter.healing_received = 0, 0, 0
            meter.hits_dealt, meter.hits_taken = 0, 0
            meter.log = {}
        end

        if ImGui.TreeNode("Recent events (subscribed)") then
            if #meter.log == 0 then
                ImGui.Text("(no combat events captured yet)")
            end
            for _, line in ipairs(meter.log) do
                ImGui.Text(line)
            end
            ImGui.TreePop()
        end
    end
end

-- Custom chat window demo: catch Enter before the game sees it, focus our own ImGui
-- text box instead of EQOA's typing window, let ImGui handle all of the text editing
-- (the UiForge overlay does not pass keyboard input down to the game while an ImGui
-- widget has focus), and on submit push the message out through the game's own send
-- path with Chat.SendMessage.
--
-- Two hooks make this work:
--   * Input.InstallKeyHook() lets us observe keys (Input.PollKeyEvents) and suppress
--     specific ones (Input.SetKeySuppressed) so the game never sees them. Here only
--     Enter is suppressed — it would otherwise open EQOA's built-in message box.
--   * Chat.InstallSendHook() lets Chat.SendMessage hand the message to the game's own
--     chat sender on the next frame, so the outbound packet is exactly what typing in
--     the native chat window would produce.
ff_custom_chat = ff_custom_chat or {
    capturing = false,          -- key hook installed and Enter owned by us
    box_active = false,         -- our ImGui chat box is open
    focus_pending = false,      -- give the box keyboard focus on the next drawn frame
    text = "",                  -- message being composed (owned by ImGui)
    mode_index = 0,             -- selected entry of chat_modes below
    last_sent = "(nothing sent yet)",
    last_error = nil,
}

-- Selectable chat modes. Prefixing per send is how the game itself routes slash
-- commands; there is no persistent mode to set (see Chat.ChatMode).
local chat_modes = {
    { name = "Default", prefix = Chat.ChatMode.Default },
    { name = "Say",     prefix = Chat.ChatMode.Say },
    { name = "Group",   prefix = Chat.ChatMode.Group },
    { name = "Guild",   prefix = Chat.ChatMode.Guild },
    { name = "Shout",   prefix = Chat.ChatMode.Shout },
}

local function SendCustomChatText()
    local text = ff_custom_chat.text
    if text == "" then
        return
    end
    -- The text goes through the game's own typed-chat processor, so slash commands
    -- typed into the box work exactly as they would in the native chat box
    -- (/say /shout /tell /reply ...) and always override the selected mode.
    local mode = chat_modes[ff_custom_chat.mode_index + 1].prefix
    local ok, err = Chat.SendChatText(text, mode)
    if ok then
        ff_custom_chat.last_sent = text
        ff_custom_chat.last_error = nil
        ff_custom_chat.text = ""
    else
        ff_custom_chat.last_error = err
    end
end

-- Runs every frame while capturing so the key ring buffer never overruns, even when
-- the header is collapsed. The only key we act on is Enter: it opens our chat box and
-- moves keyboard focus to it. Everything after that is ImGui's job.
local function UpdateCustomChatCapture()
    if not ff_custom_chat.capturing or not Input.IsKeyHookInstalled() then
        return
    end

    for _, event in ipairs(Input.PollKeyEvents()) do
        if event.is_down and event.key == Input.Key.Enter and not ff_custom_chat.box_active then
            ff_custom_chat.box_active = true
            ff_custom_chat.focus_pending = true
        end
    end
end

local function StartCapturing()
    -- Both hooks are needed: one to grab keys, one to send.
    local ok, err = Input.InstallKeyHook()
    if not ok then
        ff_custom_chat.last_error = err
        return
    end
    ok, err = Chat.InstallSendHook()
    if not ok then
        ff_custom_chat.last_error = err
        return
    end

    -- Swallow Enter so the game's own typing window never opens.
    Input.SetKeySuppressed(Input.Key.Enter, true)
    ff_custom_chat.capturing = true
    ff_custom_chat.last_error = nil
end

local function StopCapturing()
    -- Give the keyboard back to the game entirely: unsuppress Enter, then remove both
    -- hooks so the patched instructions are restored and the caves zeroed.
    if Input.IsKeyHookInstalled() then
        Input.SetKeySuppressed(Input.Key.Enter, false)
    end
    Input.UninstallKeyHook()
    Chat.UninstallSendHook()
    ff_custom_chat.capturing = false
    ff_custom_chat.box_active = false
    ff_custom_chat.focus_pending = false
end

local function DisplayCustomChatInput()
    if ImGui.CollapsingHeader("Custom Chat Input (keyboard intercept + send)") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        ImGui.Text("Capturing keyboard: " .. tostring(ff_custom_chat.capturing))
        ImGui.Text("Key hook installed: " .. tostring(Input.IsKeyHookInstalled()))
        ImGui.Text("Send hook installed: " .. tostring(Chat.IsSendHookInstalled()))

        if not ff_custom_chat.capturing then
            if ImGui.Button("Start capturing (suppress Enter)") then
                StartCapturing()
            end
        else
            if ImGui.Button("Stop capturing") then
                StopCapturing()
            end
        end

        if ff_custom_chat.last_error then
            ImGui.Text("error: " .. ff_custom_chat.last_error)
        end
        if Chat.IsSendPending() then
            -- The cave clears this the same frame it hands the message to the game. If
            -- this line ever sticks, the hooked per-frame call site is not executing.
            ImGui.Text("send pending (waiting for the game to pick it up)...")
        end

        -- Chat mode: applied as a slash-command prefix on each send. Typing an explicit
        -- /command in the message box overrides it.
        for i, m in ipairs(chat_modes) do
            if i > 1 then ImGui.SameLine() end
            ff_custom_chat.mode_index = ImGui.RadioButton(m.name, ff_custom_chat.mode_index, i - 1)
        end

        if not ff_custom_chat.box_active then
            ImGui.Text("Press Enter in game to open the chat box (capturing must be on).")
        else
            if ff_custom_chat.focus_pending then
                ImGui.SetKeyboardFocusHere()
                ff_custom_chat.focus_pending = false
            end
            local entered
            ff_custom_chat.text, entered = ImGui.InputText("message",
                ff_custom_chat.text, ImGuiInputTextFlags.EnterReturnsTrue)
            if entered then
                SendCustomChatText()
                ff_custom_chat.box_active = false
            end
            ImGui.SameLine()
            if ImGui.Button("Cancel") then
                ff_custom_chat.text = ""
                ff_custom_chat.box_active = false
            end
        end

        ImGui.Text("Last sent: " .. ff_custom_chat.last_sent)

        ImGui.TextWrapped("Tip: capture keeps working with the header collapsed, but the chat box itself can only appear while this section is visible. Use Stop capturing to hand Enter back to the game.")
    end
end

local function RemoveChatHooks()
    StopCapturing()
end

if not ff_custom_chat.cleanup_registered then
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, RemoveChatHooks)
    UiForge.RegisterCallback(UiForge.CallbackType.OnEject, RemoveChatHooks)
    ff_custom_chat.cleanup_registered = true
end

-- Per-frame state updates that must run regardless of any UI visibility.
UpdateCooldownTracking()
UpdateCustomChatCapture()

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

    DisplayCooldownWatch()

    DisplayEffectsFunctions()

    DisplayInventoryFunctions()

    DisplayQuestLogFunctions()

    DisplayGroupFunctions()

    DisplayCombatFunctions()

    DisplayCustomChatInput()

    DisplaySaveLoadFunctions()
end
-- End the window
ImGui.End()
