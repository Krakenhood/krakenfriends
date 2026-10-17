local _, KR = ...
local S, C = KR.Spells, KR.Coach

--------------------------------------------------------------------------------
-- Practice mode (/kr practice)
--
-- Pretend fights as a level 30 Arms warrior, on any character, to try the bar and
-- the coach without a warrior (or without pulling anything). The pretend warrior
-- stands in for the game: its rage, stance, cooldowns, target and buffs replace
-- what the Spells module reads, and its fights are played as game events through
-- KR:Inject, so the bar, the swing timer and the coach run their real code.
--
-- Fights take about 35 seconds with a short break between them. Every other one
-- is sloppy on purpose (an Overpower let go, rage capped, no Battle Shout, a
-- Heroic Strike in the Execute phase, a costly stance switch) so the coach has
-- something to say. A real fight ends practice at once.
--------------------------------------------------------------------------------

local P = {}
KR.Practice = P

local TICK = 0.1
local FIGHT = 34      -- seconds until the target dies
local BREAK = 8       -- seconds between fights
local SPEED = 2.6     -- the pretend two-hander
local KEEP = 10       -- Tactical Mastery, 2 points

-- what the pretend warrior knows, and the rage it costs (Improved Heroic Strike: 12)
local KNOWS = {
    hs = 12, cleave = 20, execute = 15, ms = 30, sunder = 15, overpower = 5, rend = 10, hamstring = 10,
    tclap = 20, shout = 10, demo = 10, pummel = 10, intercept = 10, bloodrage = 0, charge = 0,
}

local FOES = {
    { "Defias Pillager", "elite", 31 }, { "Mor'Ladim", "rareelite", 35 }, { "Stonetusk Boar", "normal", 30 },
    { "Rotting Horror", "elite", 32 }, { "Riverpaw Brute", "normal", 30 }, { "Gath'Ilzogg", "elite", 33 },
}

local sim = {}
local ticker, saved

local function now() return GetTime() end

--------------------------------------------------------------------------------
-- The pretend warrior, standing in for the game
--------------------------------------------------------------------------------

local overrides = {
    Scan = function(self)
        wipe(self.known)
        wipe(self.byName)
        for _, a in ipairs(KR.Abilities) do
            local name = S.SpellName(a.id) or a.name
            self.byName[name] = a.key
            if KNOWS[a.key] then
                self.known[a.key] = { ability = a, id = a.id, name = name, cost = KNOWS[a.key], icon = S.SpellIcon(a.id, a.icon) }
            end
        end
        for _, st in ipairs(KR.Stances) do
            st.label = S.SpellName(st.id) or st.name
            st.texture = S.SpellIcon(st.id, st.icon)
        end
        KR:Fire("SPELLS")
    end,
    Rage = function() return sim.rage, 100, sim.rage end,
    Stance = function() return KR.Stances[sim.stance] end,
    Keep = function() return KEEP end,
    CooldownLeft = function(_, key)
        if not S.known[key] then return nil end
        return math.max(0, (sim.cd[key] or 0) - now())
    end,
    Queued = function(_, key) return sim.queued[key] or false end,
    HasBuff = function(_, key) return key == "shout" and (sim.shoutUntil or 0) > now() end,
    SunderStacks = function() return sim.fighting and sim.sunder or nil end,
    TargetHealth = function() return sim.fighting and sim.hp or nil end,
    Target = function()
        if not sim.fighting then return nil end
        local foe = sim.foe
        return foe[1], foe[2], foe[3], sim.guid, sim.hp <= 0
    end,
    Usable = function(self, key)
        local k = self.known[key]
        if not k then return false end
        local rage, ready = sim.rage, self:CooldownLeft(key) <= 0
        local lit
        if key == "overpower" then
            lit = sim.opUntil > now() and sim.stance == 1 and ready
        elseif key == "revenge" then
            lit = false
        elseif key == "execute" then
            lit = sim.fighting and sim.hp > 0 and sim.hp < 20 and self:StanceFits(k.ability)
        else
            lit = ready and self:StanceFits(k.ability)
        end
        if not lit then return false, false end
        return rage >= k.cost, rage < k.cost
    end,
}

--------------------------------------------------------------------------------
-- Playing a fight
--------------------------------------------------------------------------------

local function setRage(v)
    sim.rage = math.max(0, math.min(100, math.floor(v + 0.5)))
    KR:Inject("UNIT_POWER_UPDATE", "player", "RAGE")
end

local function cast(key, cost)
    if cost and cost > 0 then sim.rage = math.max(0, sim.rage - cost) end
    KR:Inject("UNIT_SPELLCAST_SUCCEEDED", "player", "Practice-" .. key, KR.AbilityByKey[key].id)
    if cost then KR:Inject("UNIT_POWER_UPDATE", "player", "RAGE") end
end

local function setStance(i)
    sim.stance = i
    KR:Inject("UPDATE_SHAPESHIFT_FORM")
    if sim.rage > KEEP then setRage(KEEP) end
end

local function startFight()
    sim.n = (sim.n or 0) + 1
    sim.foe = FOES[(sim.n - 1) % #FOES + 1]
    sim.guid = ("Creature-0-0-0-0-%d-Practice"):format(sim.n)
    sim.sloppy = sim.n % 2 == 1
    sim.t0 = now()
    sim.fighting, sim.hp, sim.sunder = true, 100, 0
    sim.cd, sim.queued, sim.done = {}, {}, {}
    sim.opUntil, sim.opAt, sim.opLetGo = 0, 0, false
    sim.nextSwing, sim.nextHurt, sim.nextExec, sim.swings = 0.4, 1.3, 0, 0
    sim.stance = 1
    KR:Inject("PLAYER_REGEN_DISABLED")
    KR:Inject("PLAYER_ENTER_COMBAT")
end

local function endFight()
    sim.fighting = false
    sim.queued = {}
    KR:Inject("PLAYER_LEAVE_COMBAT")
    KR:Inject("PLAYER_REGEN_ENABLED")
    sim.breakUntil = now() + BREAK
end

-- once(name, t): true the first time the fight passes `t` seconds
local function once(name, t, elapsed)
    if sim.done[name] or elapsed < t then return false end
    sim.done[name] = true
    return true
end

local function fightStep(t)
    local clock = now()
    sim.hp = math.max(0, 100 * (1 - t / FIGHT))
    local sloppy = sim.sloppy
    local execPhase = sim.hp > 0 and sim.hp < 20

    if once("charge", 0.2, t) then cast("charge"); setRage(sim.rage + 15) end
    if once("shout", 1.0, t) and not sloppy and (sim.shoutUntil or 0) < clock + 30 then
        cast("shout", 10)
        sim.shoutUntil = clock + 120
    end

    -- the target hits you: rage from damage taken
    if t >= sim.nextHurt and sim.hp > 0 then
        sim.nextHurt = sim.nextHurt + 1.7
        KR:Inject("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
        setRage(sim.rage + 5)
    end

    -- your swing: rage, a queued Heroic Strike, or a dodge every fourth swing
    if t >= sim.nextSwing and sim.hp > 0 then
        sim.nextSwing = sim.nextSwing + SPEED
        sim.swings = sim.swings + 1
        if sim.queued.hs then
            sim.queued.hs = nil
            cast("hs", KNOWS.hs)
        elseif sim.swings % 4 == 0 and sim.stance == 1 then
            sim.opUntil, sim.opAt = clock + KR.PROC_WINDOW, clock
        else
            local gain = (sloppy and t > 8 and t < 17) and 26 or 16 -- a run of crits in the sloppy fight
            setRage(sim.rage + gain)
        end
    end

    -- Overpower: taken a moment after the dodge (the sloppy warrior lets the first one go)
    if sim.opUntil > clock and clock - sim.opAt >= 1.2 then
        if sloppy and not sim.opLetGo then sim.opLetGo = sim.opAt end
        if sim.opLetGo ~= sim.opAt and sim.rage >= KNOWS.overpower and (sim.cd.overpower or 0) <= clock and sim.stance == 1 then
            cast("overpower", KNOWS.overpower)
            sim.cd.overpower, sim.opUntil = clock + 5, 0
        end
    end

    -- Sunder Armor, each one as soon as there's rage for it after its time:
    -- three in the sloppy fight, five in the clean one
    local due = ({ 3, 5.5, 8, 10.5, 13 })[sim.sunder + 1]
    if due and t >= due and (sim.sunder < 3 or not sloppy) and sim.rage >= KNOWS.sunder then
        cast("sunder", KNOWS.sunder)
        sim.sunder = sim.sunder + 1
    end

    -- the sloppy warrior sits on its rage for a while, then switches stance with a full bar
    local holding = sloppy and t > 8 and t < 19
    if sloppy and once("bloodrage", 10, t) then cast("bloodrage"); setRage(sim.rage + 10) end
    if sloppy and once("berserker", 19, t) then setStance(3) end
    if sloppy and once("battle", 23, t) then setStance(1) end

    -- Mortal Strike on cooldown
    if t > 2 and not holding and not execPhase and sim.stance == 1 and (sim.cd.ms or 0) <= clock and sim.rage >= KNOWS.ms then
        cast("ms", KNOWS.ms)
        sim.cd.ms = clock + 6
    end

    -- Heroic Strike with rage to spare (the sloppy one also once in the Execute phase)
    if not sim.queued.hs and not holding and not execPhase and sim.rage >= 42 then sim.queued.hs = true end
    if sloppy and execPhase and not sim.done.execHS and sim.rage >= KNOWS.hs then
        sim.queued.hs, sim.done.execHS = true, true
    end

    -- Execute below 20%
    -- (a moment to react once there's rage for it)
    if execPhase and not sim.queued.hs and t >= sim.nextExec and sim.rage >= KNOWS.execute and sim.stance ~= 2 then
        sim.execAt = sim.execAt or t + 0.6
        if t >= sim.execAt then
            cast("execute")
            setRage(0)
            sim.nextExec, sim.execAt = t + 2.2, nil
        end
    end

    if t >= FIGHT + 0.8 then endFight() end
end

local function step()
    if not KR.practice then return end
    if sim.fighting then
        fightStep(now() - sim.t0)
    elseif now() >= (sim.breakUntil or 0) then
        startFight()
    elseif sim.rage > 0 and now() >= sim.breakUntil - BREAK + 2 then
        setRage(sim.rage - 4) -- rage fades out of combat
    end
end
P.Step = step

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

function P:Start()
    if KR.practice then return end
    KR.practice = true
    sim = { rage = 0, stance = 1, cd = {}, queued = {}, done = {}, opUntil = 0, breakUntil = now() + 2 }
    saved = {}
    for name, fn in pairs(overrides) do saved[name] = rawget(S, name); S[name] = fn end
    KR.Swing.fixedSpeed = SPEED
    KR.Swing.speed = SPEED
    C:Abort()

    if KR.active then
        S:Scan()
    else
        KR.active = true
        if KR.Hud.frame then
            S:Scan()
            KR.Hud.frame:Show()
        else
            KR:Fire("SETUP")
        end
    end
    KR.Hud:Update()
    ticker = C_Timer.NewTicker(TICK, function() KR.dispatch(step) end)
    KR:Print("Practice: you're a level 30 Arms warrior now, fighting pretend foes every 45 seconds. Watch the bar; the coach grades each fight (/kr opens it). /kr practice again stops.")
end

function P:Stop(why)
    if not KR.practice then return end
    if ticker then ticker:Cancel(); ticker = nil end
    C:Abort()
    KR.Swing:Reset()
    for name in pairs(overrides) do S[name] = saved[name] end
    saved = nil
    KR.Swing.fixedSpeed = nil
    KR.practice = false
    sim = {}
    if KR.notWarrior then
        KR.active = false
        if KR.Hud.frame then KR.Hud.frame:Hide() end
    else
        S:Scan()
        KR.Hud:Update()
    end
    KR:Print(why or "Practice over. The practice fights stay in the coach, marked as practice (/kr clear forgets them).")
end

function P:Toggle()
    if KR.practice then self:Stop() else self:Start() end
end

-- A real fight ends practice at once.
KR:On("PLAYER_REGEN_DISABLED", function()
    if not KR.practice or KR.injecting then return end
    P:Stop("A real fight: practice stopped.")
    if KR.active then C:Start() end
end)
