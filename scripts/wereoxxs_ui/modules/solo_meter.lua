--[[
    solo_meter.lua

    The one player encounter engine for wereoxxs_ui.

    Wraps the shared Meter with the encounter bookkeeping a session would
    normally do, for a meter that only ever watches the local player. Lifetime
    combat counters go in each tick, and what comes out is the current fight's
    totals, the session totals, and a history of finished fights, in the same
    shapes damage_meter.lua draws.

    This module never reads game memory. The counters arrive from the caller.
]]

local Meter = require("meter")

local SoloMeter = {}
SoloMeter.__index = SoloMeter

local CLIENT_ID = 1

function SoloMeter.new()
    return setmetatable({
        meter = Meter.new(),
        config = Meter.DefaultConfig(),
        encounter = { duration_ms = 0, id = 0, active = false },
        history = {},
        fight_count = 0,
        was_active = false,
    }, SoloMeter)
end

--- Folds the local player's lifetime counters in and runs the encounter clock.
--- @param totals table Lifetime damage_done, damage_taken, healing_done, healing_taken.
--- @param battle_music boolean|nil From the game, so the meter never reads memory.
function SoloMeter:Update(now_ms, totals, battle_music)
    self.meter:Observe(CLIENT_ID, totals, now_ms, self.config)
    self.meter:Update(now_ms, self.config, battle_music)

    local active = self.meter.active
    self.encounter = {
        duration_ms = self.meter:GetDurationMs(now_ms),
        id = self.meter.id,
        active = active,
    }

    -- A fight that just closed goes to the history, if anything happened in it.
    if self.was_active and not active then
        self:Archive()
    end
    self.was_active = active
end

--- The local player's totals for the running fight.
function SoloMeter:GetTotals()
    return self.meter:GetTotals(CLIENT_ID)
end

--- The local player's totals for the whole session.
function SoloMeter:GetOverall()
    return self.meter:GetOverall(CLIENT_ID)
end

function SoloMeter:GetEncounter()
    return self.encounter
end

function SoloMeter:GetHistory()
    return self.history
end

function SoloMeter:ClearHistory()
    self.history = {}
    self.fight_count = 0
end

function SoloMeter:Start(now_ms)
    self.meter:Begin(now_ms, true)
end

function SoloMeter:Stop(now_ms)
    self.meter:Stop(now_ms)
end

function SoloMeter:Reset()
    self.meter:Reset()
end

--- Files the finished fight into the history, in the shape the damage meter's
--- history view draws.
function SoloMeter:Archive()
    local totals = self.meter:GetTotals(CLIENT_ID)
    local moved = (totals.damage_done or 0) > 0 or (totals.damage_taken or 0) > 0
        or (totals.healing_done or 0) > 0 or (totals.healing_taken or 0) > 0
    if not moved then
        return
    end

    self.fight_count = self.fight_count + 1
    self.history[#self.history + 1] = {
        id = self.fight_count,
        duration_ms = self.encounter.duration_ms,
        members = {
            {
                name = self.name or "You",
                class_id = self.class_id,
                damage_done = totals.damage_done or 0,
                damage_taken = totals.damage_taken or 0,
                healing_done = totals.healing_done or 0,
                healing_taken = totals.healing_taken or 0,
            },
        },
    }
    while #self.history > 50 do
        table.remove(self.history, 1)
    end
end

--- Who the archive rows are labeled as. Set once identity is known.
function SoloMeter:SetIdentity(name, class_id)
    self.name = name
    self.class_id = class_id
end

return SoloMeter
