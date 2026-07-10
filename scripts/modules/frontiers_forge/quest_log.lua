local Util = require("frontiers_forge.util")
local Quest = require("frontiers_forge.quest")

-- The quest log is owned by the client-state singleton, resolved through the
-- static pointer at 0x4E37F0 which points at singleton + 4. The quest array is
-- packed with no sentinel, so valid quests always occupy indices 0 .. count-1 in
-- log order.
local QuestLog = {}

local GUI_CONTEXT_PTR_OFFSET = 0x4E37F0

QuestLog.max_quests = 8

-- Singleton-relative offsets. The GUI-context pointer lands at singleton + 4,
-- so 4 is subtracted when reading through it.
local QUEST_ARRAY_OFFSET = 0x2C6E0
local QUEST_COUNT_OFFSET = 0x2CEE0

--- Number of quests currently in the log.
--- @return integer count Quest count from 0 to max_quests, or 0 when not in game.
function QuestLog.GetCount()
    local count = Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {QUEST_COUNT_OFFSET - 4}, "uint32_t", 0)
    if count < 0 or count > QuestLog.max_quests then
        return 0
    end
    return count
end

--- Get the quest at a log index. Indices are zero based and match the order
--- the quest log window displays, from 0 to GetCount() - 1.
--- @param index integer Log index from 0 to GetCount() - 1.
--- @return table|nil quest Quest object, or nil when the index is out of range or not in game.
function QuestLog.GetQuestByIndex(index)
    if index < 0 or index >= QuestLog.GetCount() then
        return nil
    end
    local gui_context = Util.ReadFromOffset(GUI_CONTEXT_PTR_OFFSET, "uint32_t")
    if gui_context == nil or gui_context == 0 then
        return nil
    end
    local singleton = gui_context - 4
    local address = Util.EEmem() + singleton + QUEST_ARRAY_OFFSET + (index * Quest.size)
    return Quest.new(address)
end

--- Iterator over all quests in log order.
--- Usage looks like `for index, quest in QuestLog.Quests() do ... end`.
--- @return function iterator Iterator producing zero based log index and Quest object pairs.
function QuestLog.Quests()
    local index = -1
    return function()
        index = index + 1
        local quest = QuestLog.GetQuestByIndex(index)
        if quest == nil then
            return nil
        end
        return index, quest
    end
end

return QuestLog
