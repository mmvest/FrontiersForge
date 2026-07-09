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
    ImGui.Text("Name: " .. entity.name)
    ImGui.Text("ID: " .. entity.id)
    ImGui.Text("Level: " .. entity.level)
    ImGui.Text("HP: " .. entity.percent_hp .. "%")
    ImGui.Text(string.format("Coordinates: x = %.2f, y = %.2f, z = %.2f", entity.x, entity.y, entity.z))

    -- Disposition towards the player. The server only sends this
    -- for the CURRENT TARGET, so every other entity shows nil / "Unknown".
    ImGui.Text("Disposition: " .. tostring(entity.disposition)
        .. " (" .. tostring(entity.disposition_name) .. ")")
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
        if entity == nil then
            entity = { id = 0, percent_hp = 0, x = 0, y = 0, z = 0, name = "No entity selected", level = 0,
                       disposition = nil, disposition_name = EntityList.GetDispositionName(nil) }
        end
        if ImGui.TreeNode("GetEntityById: " .. entity.name .. " (ID: " .. entity.id .. ")") then
            -- Inside the tree node, show the entity stats. The current target
            -- is the one entity whose disposition is populated.
            DisplayEntityDetails(entity)

            -- End the tree node
            ImGui.TreePop()
        end

        entity = EntityList.GetEntityByIndex(0)
        if entity == nil then
            entity = { id = 0, percent_hp = 0, x = 0, y = 0, z = 0, name = "No entity", level = 0,
                       disposition = nil, disposition_name = EntityList.GetDispositionName(nil) }
        end
        if ImGui.TreeNode("GetEntityByIndex: " .. entity.name .. " (ID: " .. entity.id .. ")") then
            -- Inside the tree node, show the entity stats
            DisplayEntityDetails(entity)

            -- End the tree node
            ImGui.TreePop()
        end

        local entities = EntityList.GetAllEntities()
        if entities == nil then
            entities = {{ id = 0, percent_hp = 0, x = 0, y = 0, z = 0, name = "No entities around", level = 0,
                          disposition = nil, disposition_name = EntityList.GetDispositionName(nil) }}
        end
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
    ImGui.Text("GetCategory: " .. ability:GetCategory())
    ImGui.Text("GetSpellbookSlot: " .. ability:GetSpellbookSlot())
    ImGui.Text("GetLevel: " .. ability:GetLevel())
    ImGui.Text(string.format("GetRange: %.2f", ability:GetRange()))
    ImGui.Text("GetCastTime: " .. ability:GetCastTime())
    ImGui.Text("GetPwrCost: " .. ability:GetPwrCost())
    -- Icon refs are resource hashes. The hex form matches the res_<hash>.png
    -- file names produced by tools/rip_esf_icons.py.
    ImGui.Text(string.format("GetIconBackgroundRef: %08X", ability:GetIconBackgroundRef()))
    ImGui.Text(string.format("GetIconForegroundRef: %08X", ability:GetIconForegroundRef()))

    -- Icon.GetTexture(hash): decodes the icon straight out of game memory the
    -- first time and returns a cached ImGui texture afterwards. Draw the
    -- background first, then the foreground on top of it at the same spot.
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

        for bar_index = 0, AbilityBar.num_bars - 1 do
            local slot_count = AbilityBar.GetSlotCount(bar_index)
            if ImGui.TreeNode("Bar " .. bar_index .. " - AbilityBar.GetSlotCount(" .. bar_index .. "): " .. slot_count) then
                for slot_index = 0, slot_count - 1 do
                    local ability_slot = AbilityBar.GetAbilitySlot(bar_index, slot_index)
                    if ImGui.TreeNode("AbilityBar.GetAbilitySlot(" .. bar_index .. ", " .. slot_index .. ")") then
                        ImGui.Text("AbilitySlot:IsEmpty(): " .. tostring(ability_slot:IsEmpty()))
                        ImGui.Text("AbilitySlot:GetIconRef(): " .. tostring(ability_slot:GetIconRef()))
                        -- GetAbilityIndex() returns nil when the slot doesn't
                        -- reference the player's ability list (empty slot or
                        -- other source type)
                        ImGui.Text("AbilitySlot:GetAbilityIndex(): " .. tostring(ability_slot:GetAbilityIndex()))

                        -- AbilitySlot:GetAbility() resolves the slot into a full
                        -- Ability object (see the Ability accessors above), and is
                        -- also available as AbilityBar.GetAbility(bar, slot)
                        local ability = ability_slot:GetAbility()
                        if ability then
                            if ImGui.TreeNode("AbilitySlot:GetAbility(): " .. ability:GetName()) then
                                DisplayAbilityDetails(ability)
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
}

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
    -- Poll every frame while the hook is up, even when the header is
    -- collapsed, so the 64-entry ring buffer never overruns.
    local meter = ff_combat_meter
    if Combat.IsHookInstalled() then
        for _, event in ipairs(Combat.PollEvents()) do
            if event.is_heal then
                if event.incoming then
                    meter.healing_received = meter.healing_received + event.amount
                end
            elseif event.outgoing then
                meter.damage_dealt = meter.damage_dealt - event.amount
                meter.hits_dealt = meter.hits_dealt + 1
            elseif event.incoming then
                meter.damage_taken = meter.damage_taken - event.amount
                meter.hits_taken = meter.hits_taken + 1
            end
            meter.log[#meter.log + 1] = string.format(
                "#%d  attacker=%d  defender=%d  amount=%d%s",
                event.seq, event.attacker_id, event.defender_id, event.amount,
                event.is_heal and "  (heal)" or "")
            if #meter.log > 20 then
                table.remove(meter.log, 1)
            end
        end
    end

    if ImGui.CollapsingHeader("Combat Functions") then
        if Util.IsInGame() == 0 then
            NotInGameWarning()
            return
        end

        ImGui.Text("Combat.IsHookInstalled(): " .. tostring(Combat.IsHookInstalled()))
        if not Combat.IsHookInstalled() then
            if ImGui.Button("Combat.InstallHook()") then
                local ok, err = Combat.InstallHook()
                meter.last_error = ok and nil or err
            end
        else
            if ImGui.Button("Combat.UninstallHook()") then
                Combat.UninstallHook()
            end
        end
        if meter.last_error then
            ImGui.Text("install failed: " .. meter.last_error)
        end

        ImGui.Text("Combat.GetEventCount(): " .. Combat.GetEventCount())
        ImGui.Text("Combat.GetDroppedCount(): " .. Combat.GetDroppedCount())

        ImGui.Text(string.format("Damage dealt: %d (%d hits)", meter.damage_dealt, meter.hits_dealt))
        ImGui.Text(string.format("Damage taken: %d (%d hits)", meter.damage_taken, meter.hits_taken))
        ImGui.Text(string.format("Healing received: %d", meter.healing_received))

        if ImGui.Button("Reset meter") then
            meter.damage_dealt, meter.damage_taken, meter.healing_received = 0, 0, 0
            meter.hits_dealt, meter.hits_taken = 0, 0
            meter.log = {}
        end

        if ImGui.TreeNode("Recent events (Combat.PollEvents())") then
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

-- Per-frame state updates that must run regardless of any UI visibility.
UpdateCooldownTracking()

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

    DisplayQuestLogFunctions()

    DisplayGroupFunctions()

    DisplayCombatFunctions()

    DisplaySaveLoadFunctions()
end
-- End the window
ImGui.End()
