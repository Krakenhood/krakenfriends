local _, KR = ...
local call, clean = KR.call, KR.clean
local S = KR.Spells

--------------------------------------------------------------------------------
-- The coach
--
-- Watches each fight (from entering combat to leaving it) and keeps what a
-- warrior can learn from: the Overpower and Revenge chances you had and used,
-- the Execute phase, the time your rage sat full, what stance switches cost,
-- Battle Shout and Sunder Armor. After the fight that becomes a grade and a few
-- tips; over many fights, trends.
--
-- No combat log on Forever: chances are seen through your target dodging
-- (solo), you dodging, parrying or blocking, and the game lighting the ability up.
--------------------------------------------------------------------------------

local C = {}
KR.Coach = C

local TICK = 0.1
local MIN_FIGHT = 6     -- shorter fights aren't kept
local TOAST_FIGHT = 10  -- ... or announced

C.fight = nil      -- the fight going on
C.windows = {}     -- "op"/"rv" -> the open chance
C.execute = false  -- is the target in Execute range
local lastClose = {}
local lastRage
local ticker
local pendingSwap

local PROCS = {
    op = { key = "overpower", stance = "battle" },
    rv = { key = "revenge", stance = "defensive" },
}

local function now() return GetTime() end

--------------------------------------------------------------------------------
-- A fight
--------------------------------------------------------------------------------

local function newFight()
    return {
        t = KR.Now(), start = now(), dur = 0,
        targets = {}, -- name -> { s = seconds targeted, cls, lv }
        stance = {},
        op = { win = 0, used = 0, missed = 0, starved = 0, other = 0 },
        rv = { win = 0, used = 0, missed = 0, starved = 0, other = 0 },
        exec = { time = 0, casts = 0, hs = 0 },
        capped = 0, stanceLoss = 0, swaps = 0,
        shout = { up = 0, known = S:Known("shout") ~= nil, seen = false },
        sunder = { casts = 0, max = 0, to5 = nil, drops = 0 },
        hs = 0, starved = 0, swings = 0,
        casts = {}, spent = {},
    }
end

function C:Window(kind)
    local w = self.windows[kind]
    if not w then return nil end
    return math.max(0, KR.PROC_WINDOW - (now() - w.t0)), w
end

local function openWindow(kind, how)
    local F = C.fight
    local p = PROCS[kind]
    if not (F and S:Known(p.key)) then return end
    local w = C.windows[kind]
    if w then
        w.t0 = now() -- a second dodge renews the chance
        return
    end
    C.windows[kind] = { t0 = now(), how = how, fits = false, could = false, short = false, used = false }
    F[kind].win = F[kind].win + 1
    KR:Debug("%s chance (%s)", p.key, how)
    KR:Fire("PROC", kind, true)
end

local function closeWindow(kind)
    local F, w = C.fight, C.windows[kind]
    if not w then return end
    C.windows[kind] = nil
    lastClose[kind] = now()
    if F and not w.used then
        local stat = F[kind]
        if not w.fits then
            stat.other = stat.other + 1        -- never in the stance it needs
        elseif w.could then
            stat.missed = stat.missed + 1      -- ready, affordable, and not used
        elseif w.short then
            stat.starved = stat.starved + 1    -- ready but not enough rage
        end
    end
    KR:Fire("PROC", kind, false)
end

-- Look at an open chance: could you have used it right now?
local function sampleWindow(kind, w, stanceKey, rage)
    local p = PROCS[kind]
    local k = S:Known(p.key)
    if not k then return end
    local fits = stanceKey == p.stance
    if fits then w.fits = true end
    local cd = S:CooldownLeft(p.key)
    local ready = cd == nil or cd <= 0.1
    if fits and ready then
        if rage == nil or rage >= k.cost then w.could = true else w.short = true end
    end
    -- the game turned it off again before our five seconds ran out: someone used it or it ran out
    local usable, noRage = S:Usable(p.key)
    if usable or noRage then w.sawUsable = true
    elseif w.sawUsable and usable == false then closeWindow(kind) end
end

local function targetInfo(F)
    local name, cls, lv, guid, dead = S:Target()
    if not name then return nil end
    local t = F.targets[name]
    if not t then
        t = { s = 0, cls = cls, lv = lv }
        F.targets[name] = t
    end
    return t, guid, dead
end

local sunderGUID, sunderLast = nil, 0

local function tick()
    local F = C.fight
    if not F then return end
    local t = now()
    local dt = math.min(1, t - (F.lastTick or t))
    F.lastTick = t
    if dt <= 0 then return end

    local rage, max = S:Rage()
    local stanceKey = S:StanceKey()
    if stanceKey then F.stance[stanceKey] = (F.stance[stanceKey] or 0) + dt end
    if rage and rage >= max then F.capped = F.capped + dt end

    -- Battle Shout
    if F.shout.known then
        local up = S:HasBuff("shout")
        if up ~= nil then F.shout.seen = true end
        if up then F.shout.up = F.shout.up + dt end
    end

    -- the target: who you fought, the Execute phase, Sunder Armor
    local target, guid, dead = targetInfo(F)
    if target then target.s = target.s + dt end
    local exec = false
    if target and S:Known("execute") then
        local hp = S:TargetHealth()
        if hp then
            exec = hp > 0 and hp < 20
        else
            local usable, noRage = S:Usable("execute")
            exec = (usable or noRage) and true or false
        end
    end
    if exec ~= C.execute then
        C.execute = exec
        KR:Fire("PROC", "ex", exec)
    end
    if exec then F.exec.time = F.exec.time + dt end

    if target and F.sunder.casts > 0 then
        local stacks = S:SunderStacks()
        if stacks then
            if guid ~= sunderGUID then sunderGUID, sunderLast = guid, stacks end
            if stacks > F.sunder.max then F.sunder.max = stacks end
            if stacks >= 5 and not F.sunder.to5 and F.sunder.first then F.sunder.to5 = t - F.sunder.first end
            if sunderLast > 0 and stacks == 0 and not dead then F.sunder.drops = F.sunder.drops + 1 end
            sunderLast = stacks
        end
    end

    -- Overpower and Revenge: the game lighting them up opens a chance too
    for kind, p in pairs(PROCS) do
        local w = C.windows[kind]
        if not w and S:Known(p.key) and t - (lastClose[kind] or -10) > 1 then
            local usable, noRage = S:Usable(p.key)
            if usable or noRage then
                openWindow(kind, "lit")
                if C.windows[kind] then C.windows[kind].sawUsable = true end
            end
        end
        w = C.windows[kind]
        if w then
            if t - w.t0 >= KR.PROC_WINDOW then closeWindow(kind)
            else sampleWindow(kind, w, stanceKey, rage) end
        end
    end

    if pendingSwap and t - pendingSwap.t > 0.5 then pendingSwap = nil end
end
C.Tick = tick

function C:Start()
    if self.fight then return end
    self.fight = newFight()
    self.fight.lastTick = now()
    wipe(self.windows)
    sunderGUID, sunderLast = nil, 0
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(TICK, function() KR.dispatch(tick) end)
    KR:Fire("COMBAT", true)
end

function C:Stop()
    local F = self.fight
    if not F then return end
    tick()
    for kind in pairs(PROCS) do closeWindow(kind) end
    if ticker then ticker:Cancel(); ticker = nil end
    self.fight = nil
    if self.execute then self.execute = false; KR:Fire("PROC", "ex", false) end
    KR:Fire("COMBAT", false)

    F.dur = now() - F.start
    local acted = next(F.casts) ~= nil or F.swings > 0
    if F.dur < MIN_FIGHT or not acted then return end
    local record = self:Finish(F)
    local fights = KR.char.fights
    fights[#fights + 1] = record
    while #fights > KR.FIGHT_CAP do table.remove(fights, 1) end
    KR:Fire("FIGHTS")
    if record.dur >= TOAST_FIGHT then KR:Fire("FIGHT_DONE", record) end
end

-- Drops the fight going on without keeping it.
function C:Abort()
    if not self.fight then return end
    if ticker then ticker:Cancel(); ticker = nil end
    wipe(self.windows)
    self.fight = nil
    if self.execute then self.execute = false; KR:Fire("PROC", "ex", false) end
    KR:Fire("COMBAT", false)
end

-- What's worth keeping of a fight, with its score.
function C:Finish(F)
    local name, best = nil, -1
    for n, t in pairs(F.targets) do
        if t.s > best then name, best = n, t.s end
    end
    local main = name and F.targets[name]
    local r = {
        t = F.t, dur = math.floor(F.dur * 10 + 0.5) / 10,
        target = name, cls = main and main.cls, lv = main and main.lv, adds = 0,
        stance = F.stance, op = F.op, rv = F.rv, exec = F.exec,
        capped = F.capped, stanceLoss = F.stanceLoss, swaps = F.swaps,
        shout = F.shout.known and F.shout.seen and { up = F.shout.up } or nil,
        sunder = F.sunder.casts > 0 and { casts = F.sunder.casts, max = F.sunder.max, to5 = F.sunder.to5, drops = F.sunder.drops } or nil,
        hs = F.hs, starved = F.starved, casts = F.casts, spent = F.spent,
        practice = KR.practice or nil,
    }
    for n in pairs(F.targets) do if n ~= name then r.adds = r.adds + 1 end end
    r.score = self:Score(r)
    return r
end

--------------------------------------------------------------------------------
-- Grading. Each part the fight gives us something to judge by counts, weighted;
-- a fight with nothing to judge gets no grade.
--------------------------------------------------------------------------------

local function ratio(a, b) if b and b > 0 then return a / b end end

function C:Parts(r)
    local parts = {}
    local function add(id, label, value, weight)
        if value then parts[#parts + 1] = { id = id, label = label, value = math.max(0, math.min(1, value)), weight = weight } end
    end
    add("op", "Overpower", ratio(r.op.used, r.op.used + r.op.missed), 2)
    add("rv", "Revenge", ratio(r.rv.used, r.rv.used + r.rv.missed), 2)
    if r.dur >= 8 then add("cap", "Rage not wasted", 1 - r.capped / (r.dur * 0.25), 1.5) end
    if r.exec.time >= 2 then
        local expected = math.max(1, math.floor(r.exec.time / 2))
        add("ex", "Execute phase", r.exec.casts / expected - 0.25 * (r.exec.hs or 0), 1.5)
    end
    if r.shout and r.dur >= 15 then add("bs", "Battle Shout", r.shout.up / r.dur / 0.9, 1) end
    if r.hs > 0 and (r.starved or 0) > 0 then add("hs", "Heroic Strike timing", 1 - r.starved / r.hs, 1) end
    if r.sunder and r.dur >= 15 then add("sa", "Sunder Armor", r.sunder.max / 5 - 0.2 * r.sunder.drops, 1) end
    return parts
end

function C:Score(r)
    local sum, weights = 0, 0
    for _, p in ipairs(self:Parts(r)) do
        sum, weights = sum + p.value * p.weight, weights + p.weight
    end
    if weights == 0 then return nil end
    return math.floor(100 * sum / weights + 0.5)
end

local GRADES = { { 95, "S" }, { 85, "A" }, { 70, "B" }, { 55, "C" }, { 0, "D" } }

function C.Grade(score)
    if not score then return "-" end
    for _, g in ipairs(GRADES) do
        if score >= g[1] then return g[2] end
    end
end

function C.GradeColor(score)
    local T = KR.Theme
    if not score then return T.dim end
    if score >= 85 then return T.good end
    if score >= 70 then return T.gold end
    if score >= 55 then return T.warn end
    return T.bad
end

--------------------------------------------------------------------------------
-- Tips: what to tell the player about one fight, the most useful first.
-- Each is { level = "bad"|"warn"|"good", text }.
--------------------------------------------------------------------------------

local function plural(n, one, many) return n == 1 and one or (many or one .. "s") end

function C:Tips(r)
    local tips = {}
    local function tip(level, text) tips[#tips + 1] = { level = level, text = text } end

    local op = r.op
    if op.missed > 0 then
        tip("bad", ("%d Overpower %s went by: it can't be dodged or blocked and costs only 5 rage. Use it inside the 5 seconds after the dodge."):format(op.missed, plural(op.missed, "chance")))
    elseif op.used > 0 and op.used >= op.win - op.other then
        tip("good", ("Every Overpower chance taken (%d)."):format(op.used))
    end
    if op.starved > 0 then
        tip("warn", ("%d Overpower %s came while you had less than 5 rage. Keep a little rage back in Battle Stance."):format(op.starved, plural(op.starved, "chance")))
    end
    if op.other >= 2 and r.stance and (r.stance.berserker or 0) > (r.stance.battle or 0) then
        tip("warn", ("Your target dodged %d times while you were out of Battle Stance. With Tactical Mastery, a quick switch for Overpower can pay off."):format(op.other))
    end

    local rv = r.rv
    if rv.missed > 0 then
        tip("bad", ("%d Revenge %s unused: after you dodge, parry or block it's cheap threat. Press it first when it lights up."):format(rv.missed, plural(rv.missed, "chance")))
    elseif rv.used > 0 and rv.missed == 0 then
        tip("good", ("Every Revenge chance used (%d)."):format(rv.used))
    end

    if r.capped >= 3 then
        local hs = S:Known("hs")
        tip(r.capped >= r.dur * 0.15 and "bad" or "warn", ("Your rage sat full for %s. Every point past 100 is lost: %s would have used it."):format(KR.FormatClock(r.capped), r.adds > 0 and "Cleave" or (hs and hs.name or "Heroic Strike")))
    elseif r.dur >= 20 then
        tip("good", "Rage never went to waste.")
    end

    local ex = r.exec
    if ex.time >= 2 then
        if ex.casts == 0 then
            tip("bad", ("The target spent %s in Execute range and you didn't Execute once."):format(KR.FormatClock(ex.time)))
        elseif (ex.hs or 0) > 0 and (r.stance.defensive or 0) < r.dur / 2 then
            tip("warn", ("%d Heroic %s during the Execute phase: below 20%%, Execute gets more out of each point of rage."):format(ex.hs, plural(ex.hs, "Strike")))
        elseif ex.casts > 0 then
            tip("good", ("%d %s in the Execute phase."):format(ex.casts, plural(ex.casts, "Execute")))
        end
    end

    if (r.starved or 0) >= 2 then
        local main
        for _, key in ipairs({ "ms", "bt", "ss" }) do if S:Known(key) then main = S:Known(key).name; break end end
        tip("warn", ("%d Heroic %s left you without the rage for %s while it was ready. Queue Heroic Strike only with rage to spare."):format(r.starved, plural(r.starved, "Strike"), main or "your big hitter"))
    end

    if r.shout and r.dur >= 15 then
        local pct = KR.Percent(r.shout.up, r.dur)
        if pct < 50 then
            tip("warn", ("Battle Shout was up for only %d%% of the fight. Shout before the pull; it lasts two minutes."):format(pct))
        elseif pct >= 95 then
            tip("good", "Battle Shout up the whole fight.")
        end
    end

    if r.stanceLoss >= 10 then
        tip("warn", ("Stance switches cost you %d rage. Switch with little rage, or spend it first."):format(r.stanceLoss))
    end

    if r.sunder and r.dur >= 15 then
        local s = r.sunder
        if s.max < 5 then
            tip("warn", ("Sunder Armor only reached %d %s. Five stacks help everyone hitting the target."):format(s.max, plural(s.max, "stack")))
        elseif s.to5 then
            tip(s.to5 <= 12 and "good" or "warn", ("Five Sunder Armors after %s."):format(KR.FormatClock(s.to5)))
        end
        if s.drops > 0 then
            tip("bad", ("Sunder Armor fell off %d %s. Refresh it before its 30 seconds run out."):format(s.drops, plural(s.drops, "time")))
        end
    end

    local order = { bad = 1, warn = 2, good = 3 }
    table.sort(tips, function(a, b) return order[a.level] < order[b.level] end)
    return tips
end

--------------------------------------------------------------------------------
-- Trends: the newest fights against the ones before them.
--------------------------------------------------------------------------------

local TREND_N = 10

local function average(fights, from, to, fn)
    local sum, n = 0, 0
    for i = from, to do
        local v = fights[i] and fn(fights[i])
        if v then sum, n = sum + v, n + 1 end
    end
    if n == 0 then return nil end
    return sum / n
end

C.TrendDefs = {
    { label = "Grade", fn = function(r) return r.score end, fmt = "%d", higher = true },
    { label = "Overpower used", fn = function(r) local d = r.op.used + r.op.missed; return d > 0 and 100 * r.op.used / d or nil end, fmt = "%d%%", higher = true },
    { label = "Revenge used", fn = function(r) local d = r.rv.used + r.rv.missed; return d > 0 and 100 * r.rv.used / d or nil end, fmt = "%d%%", higher = true },
    { label = "Rage full, per minute", fn = function(r) return r.dur >= 8 and 60 * r.capped / r.dur or nil end, fmt = "%.1fs", higher = false },
    { label = "Battle Shout uptime", fn = function(r) return r.shout and r.dur >= 15 and 100 * r.shout.up / r.dur or nil end, fmt = "%d%%", higher = true },
}

-- For each trend: { label, now, before, better = true/false/nil }
function C:Trends()
    local fights = KR.char.fights
    local n = #fights
    local out = {}
    for _, def in ipairs(self.TrendDefs) do
        local cur = average(fights, math.max(1, n - TREND_N + 1), n, def.fn)
        local prev = n > TREND_N and average(fights, math.max(1, n - 2 * TREND_N + 1), n - TREND_N, def.fn) or nil
        local better
        if cur and prev and math.abs(cur - prev) >= 0.05 * math.max(1, math.abs(prev)) then
            better = (cur > prev) == def.higher
        end
        if cur then out[#out + 1] = { label = def.label, now = cur, before = prev, better = better, fmt = def.fmt } end
    end
    return out
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

KR:OnReady("PLAYER_REGEN_DISABLED", function() C:Start() end)
KR:Listen("SWING", function() if C.fight then C.fight.swings = C.fight.swings + 1 end end)
KR:OnReady("PLAYER_REGEN_ENABLED", function() C:Stop() end)

KR:OnReady("UNIT_COMBAT", function(unit, action)
    unit, action = clean(unit), clean(action)
    if not C.fight then return end
    if unit == "player" and (action == "DODGE" or action == "PARRY" or action == "BLOCK") then
        openWindow("rv", action:lower())
    elseif unit == "target" and action == "DODGE" and not call(IsInGroup) then
        openWindow("op", "dodge")
    end
end)

KR:OnReady("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if clean(unit) ~= "player" then return end
    local key = S:KeyOf(clean(spellID))
    local F = C.fight
    if not (key and F) then return end
    F.casts[key] = (F.casts[key] or 0) + 1
    local k = S:Known(key)
    local cost = k and k.cost or 0
    if key == "execute" and lastRage then cost = math.max(cost, lastRage) end -- Execute takes all the rage
    if cost > 0 then F.spent[key] = (F.spent[key] or 0) + cost end

    for kind, p in pairs(PROCS) do
        if p.key == key then
            -- a chance we didn't see (a dodge in a group) still was one
            if not C.windows[kind] then F[kind].win = F[kind].win + 1 end
            F[kind].used = F[kind].used + 1
            local w = C.windows[kind]
            if w then w.used = true; closeWindow(kind) end
        end
    end

    if key == "execute" then F.exec.casts = F.exec.casts + 1 end
    if key == "sunder" then
        F.sunder.casts = F.sunder.casts + 1
        F.sunder.first = F.sunder.first or now()
    end
    if key == "hs" or key == "cleave" then
        F.hs = F.hs + 1
        if C.execute then F.exec.hs = F.exec.hs + 1 end
        -- did that swing leave too little rage for the big ability that was ready?
        C_Timer.After(0.05, function()
            local rage = S:Rage()
            if not (C.fight == F and rage) then return end
            for _, mk in ipairs({ "ms", "bt", "ss" }) do
                local m = S:Known(mk)
                if m then
                    local cd = S:CooldownLeft(mk)
                    if cd and cd <= 0.5 and rage < m.cost then F.starved = F.starved + 1 end
                    break
                end
            end
        end)
    end
end)

-- Rage, and what a stance switch costs. The game caps your rage at what you keep
-- (Tactical Mastery) on a switch; the rage event can come just before or just
-- after the stance event, so both orders are handled.
local prevRage, lastChange = nil, -10

-- A switch drops your rage to exactly what you keep, which is 0 to 25 in steps of
-- 5; any other drop is rage you spent. True when the drop was the switch.
local function swapCost(before, after)
    if not (before and after) or after >= before or after > 25 or after % 5 ~= 0 then return false end
    pendingSwap = nil
    local lost = before - after
    KR.char.keep = after -- learn what you keep
    if C.fight then C.fight.stanceLoss = C.fight.stanceLoss + lost end
    KR:Debug("stance switch cost %d rage", lost)
    return true
end

local function onPower(unit, kind)
    if clean(unit) ~= "player" or (kind and clean(kind) ~= "RAGE") then return end
    local rage = S:Rage()
    if type(rage) ~= "number" or rage == lastRage then return end
    if pendingSwap then
        if now() - pendingSwap.t > 0.5 then pendingSwap = nil
        elseif not swapCost(pendingSwap.before, rage) then pendingSwap.before = rage end
    end
    prevRage, lastRage, lastChange = lastRage, rage, now()
end
KR:OnReady("UNIT_POWER_UPDATE", onPower)
KR:OnReady("UNIT_POWER_FREQUENT", onPower)

local lastStance
KR:OnReady("UPDATE_SHAPESHIFT_FORM", function()
    local st = S:StanceKey()
    if st == lastStance then return end
    if lastStance and st then
        if C.fight then C.fight.swaps = C.fight.swaps + 1 end
        -- the rage dropped just before, or wait for the drop
        local done = now() - lastChange < 0.2 and swapCost(prevRage, lastRage)
        if not done and lastRage then pendingSwap = { before = lastRage, t = now() } end
    end
    lastStance = st
end)
KR:Listen("SETUP", function()
    lastStance = S:StanceKey()
    lastRage = S:Rage()
end)

--------------------------------------------------------------------------------
-- Demo fights: to see the coach without fighting. Marked, and removed again
-- with /kr demo.
--------------------------------------------------------------------------------

function C:ToggleDemo()
    local fights = KR.char.fights
    local had = false
    for i = #fights, 1, -1 do
        if fights[i].demo then table.remove(fights, i); had = true end
    end
    if had then
        KR:Print("Demo fights removed.")
        KR:Fire("FIGHTS")
        return
    end
    local t0 = KR.Now() - 3600 * 5
    local foes = {
        { "Defias Pillager", "normal", 18 }, { "Murloc Tidehunter", "normal", 17 }, { "Mor'Ladim", "rareelite", 35 },
        { "Edwin VanCleef", "elite", 21 }, { "Cookie", "elite", 20 }, { "Riverpaw Gnoll", "normal", 16 },
        { "Defias Taskmaster", "normal", 17 }, { "Mr. Smite", "elite", 20 }, { "Harvest Watcher", "normal", 18 },
        { "Rhahk'Zor", "elite", 19 }, { "Sneed", "elite", 20 }, { "Gilnid", "elite", 20 },
    }
    for i, foe in ipairs(foes) do
        local good = i / #foes -- the demo warrior gets better fight by fight
        local dur = (foe[2] == "normal") and (14 + i % 5 * 3) or (38 + i * 4)
        local opWin = 1 + i % 3
        local opUsed = math.min(opWin, math.floor(opWin * good + 0.5))
        local r = {
            demo = true, t = t0 + i * 900, dur = dur, target = foe[1], cls = foe[2], lv = foe[3], adds = (i % 4 == 0) and 2 or 0,
            stance = { battle = dur * 0.7, berserker = dur * 0.3 },
            op = { win = opWin, used = opUsed, missed = opWin - opUsed, starved = (i % 5 == 0) and 1 or 0, other = (i % 6 == 0) and 2 or 0 },
            rv = { win = 0, used = 0, missed = 0, starved = 0, other = 0 },
            exec = { time = dur * 0.18, casts = math.floor(dur * 0.18 / 2 * (0.4 + 0.6 * good)), hs = (good < 0.5) and 1 or 0 },
            capped = math.max(0, (1 - good) * dur * 0.2), stanceLoss = (i % 3 == 0) and 15 or 0, swaps = 1 + i % 3,
            shout = { up = dur * math.min(1, 0.4 + good * 0.6) },
            hs = 3 + i % 4, starved = (good < 0.4) and 2 or 0,
            casts = { ms = 2 + math.floor(dur / 6), hs = 3 + i % 4, overpower = opUsed, execute = 2, shout = 1 },
            spent = { ms = 30 * (2 + math.floor(dur / 6)), hs = 15 * (3 + i % 4), overpower = 5 * opUsed, execute = 60, shout = 10 },
        }
        if foe[2] ~= "normal" then r.sunder = { casts = 6, max = (i > 6) and 5 or 3, to5 = (i > 6) and (16 - i) or nil, drops = (i == 5) and 1 or 0 } end
        r.score = self:Score(r)
        fights[#fights + 1] = r
    end
    while #fights > KR.FIGHT_CAP do table.remove(fights, 1) end
    KR:Print("Demo fights added: open the coach with /kr. /kr demo again removes them.")
    KR:Fire("FIGHTS")
end
