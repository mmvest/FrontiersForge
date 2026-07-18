--[[
    meter.lua

    The encounter engine behind the damage meter.

    The engine is fed lifetime counters that only ever climb and never reset. It
    diffs each new report against the last one it saw and folds the difference
    into the encounter it is currently running. Reporting lifetime totals rather
    than events means a repeated report can never double count, and a counter that
    restarts at zero is picked up as a fresh baseline rather than as negative
    damage.

    Only the local client's totals are ever reported here, since there is no
    server to receive anyone else's numbers. Everything is keyed by a client id
    anyway, so the accumulation stays open to more sources if one ever exists.

    Time is measured from the fighting, not from the wall clock. The duration is
    the span between the first and the last thing that happened, so the seconds
    spent waiting for the next swing, and the idle stretch that eventually ends
    the fight, never land in the denominator and never dilute a rate. A window
    started by hand is the exception, since there the whole window was chosen on
    purpose.

    This module reads no game memory and knows nothing about the network.
]]

local Meter = {}
Meter.__index = Meter

-- What gets reported, and what the meter accumulates.
Meter.FIELDS = { "damage_done", "damage_taken", "healing_done", "healing_taken" }

-- Only these say a fight is happening. Healing does not open a fight and does not
-- keep one alive, because healing up after a pull is not combat and would
-- otherwise hold the encounter open long past the last swing, quietly stretching
-- the denominator and deflating the whole table.
local COMBAT_FIELDS = { damage_done = true, damage_taken = true }

-- A single hit would otherwise divide by nothing and read as a preposterous rate.
local MIN_DURATION_MS = 1000
Meter.MIN_DURATION_MS = MIN_DURATION_MS

--- @return table config
function Meter.DefaultConfig()
    return {
        auto_encounters = true,
        -- Quiet this long and the fight is over. Long enough to ride out a gap
        -- between swings, short enough not to glue two pulls together.
        idle_timeout_ms = 5000,
    }
end

function Meter.new()
    return setmetatable({
        id = 0,
        active = false,
        manual = false,     -- this window was started by hand
        start_ms = 0,
        last_ms = 0,        -- the last time anything at all happened
        stop_ms = 0,
        totals = {},        -- client_id to this encounter's accumulated totals
        overall = {},       -- client_id to everything all session, fights or not
        baseline = {},      -- client_id to the last lifetime counters seen
    }, Meter)
end

local function ZeroTotals()
    return { damage_done = 0, damage_taken = 0, healing_done = 0, healing_taken = 0 }
end

--- Opens a fresh encounter, discarding the previous one's totals.
--- The baselines survive, since they are what future differences are measured
--- against and have nothing to do with which fight is running.
--- @param manual boolean True when started by hand rather than by combat.
function Meter:Begin(now_ms, manual)
    self.id = self.id + 1
    self.active = true
    self.manual = manual and true or false
    self.start_ms = now_ms
    self.last_ms = now_ms
    self.stop_ms = 0
    self.totals = {}
end

--- Closes the encounter. The totals stay put so the table can still be read.
function Meter:Stop(now_ms)
    if not self.active then
        return
    end
    self.active = false
    self.stop_ms = now_ms
end

--- Throws the encounter away entirely.
function Meter:Reset()
    self.active = false
    self.manual = false
    self.start_ms = 0
    self.last_ms = 0
    self.stop_ms = 0
    self.totals = {}
end

--- Folds one source's lifetime counters into the running encounter.
--- Call once per source per tick, with whatever it last reported.
--- @param client_id integer
--- @param state table|nil The reported lifetime counters.
--- @param now_ms integer
--- @param config table From DefaultConfig.
function Meter:Observe(client_id, state, now_ms, config)
    if state == nil then
        return
    end

    local base = self.baseline[client_id] or {}
    local deltas = ZeroTotals()
    local fighting = false
    local moved = false
    local seen = {}

    for _, field in ipairs(Meter.FIELDS) do
        local value = state[field]

        if value == nil then
            -- This field was not reported, either because nothing has come in yet
            -- or because it is turned off. That is not the same as a zero, and
            -- treating it as one would make the next report look like the entire
            -- lifetime counter had just been dealt. So the last known value is
            -- kept, and nothing is counted.
            seen[field] = base[field]
        else
            -- A counter that went backwards means a restart from zero, which is a
            -- new baseline rather than negative damage.
            if base[field] ~= nil and value > base[field] then
                deltas[field] = value - base[field]
                moved = true
                if COMBAT_FIELDS[field] then
                    fighting = true
                end
            end
            seen[field] = value
        end
    end

    self.baseline[client_id] = seen

    if not moved then
        return
    end

    -- Everything is recorded here regardless of any encounter, so healing done
    -- between pulls still lands in the lifetime table.
    local overall = self.overall[client_id] or ZeroTotals()
    for _, field in ipairs(Meter.FIELDS) do
        overall[field] = overall[field] + deltas[field]
    end
    self.overall[client_id] = overall

    if not self.active then
        -- Damage is what opens an automatic encounter. Healing on its own never
        -- does, so out of combat healing is recorded without starting a fight.
        if not fighting or not config.auto_encounters then
            return
        end
        self:Begin(now_ms, false)
    end

    -- Only fighting keeps the fight alive. Healing lands in the encounter it
    -- happens to fall inside, but it never pushes the end of that fight back.
    if fighting then
        self.last_ms = now_ms
    end

    local totals = self.totals[client_id] or ZeroTotals()
    for _, field in ipairs(Meter.FIELDS) do
        totals[field] = totals[field] + deltas[field]
    end
    self.totals[client_id] = totals
end

--- Everything a source has done all session, in combat or out of it.
--- @return table totals
function Meter:GetOverall(client_id)
    return self.overall[client_id] or ZeroTotals()
end

--- Closes an automatic encounter once the fighting has stopped. Call every tick.
function Meter:Update(now_ms, config)
    if not self.active or self.manual or not config.auto_encounters then
        return
    end

    if (now_ms - self.last_ms) > config.idle_timeout_ms then
        self:Stop(self.last_ms)
    end
end

--- How long the encounter counts for, which is what every rate divides by.
--- @return integer duration_ms
function Meter:GetDurationMs(now_ms)
    if self.start_ms == 0 then
        return 0
    end

    local finish
    if self.manual then
        -- This window was chosen deliberately, so all of it counts, idle
        -- stretches included.
        finish = self.active and (now_ms or self.last_ms) or self.stop_ms
    else
        -- Only the fighting counts.
        finish = self.last_ms
    end

    return math.max(0, finish - self.start_ms)
end

--- The encounter totals for one source, zeroes when it has done nothing.
--- @return table totals
function Meter:GetTotals(client_id)
    return self.totals[client_id] or ZeroTotals()
end

--- Divides a total by the encounter, giving a per second rate.
--- @return number rate
function Meter.PerSecond(amount, duration_ms)
    if amount == nil or amount <= 0 then
        return 0
    end
    return amount / (math.max(duration_ms or 0, MIN_DURATION_MS) / 1000)
end

--- Forgets a source, so it starts from a clean baseline if it returns.
function Meter:Forget(client_id)
    self.totals[client_id] = nil
    self.overall[client_id] = nil
    self.baseline[client_id] = nil
end

return Meter
