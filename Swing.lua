local _, KR = ...
local call, clean = KR.call, KR.clean

--------------------------------------------------------------------------------
-- Swing timer (experimental)
--
-- There is no combat log on Forever, so the game never says "you swung". We
-- piece it together from what it does say:
--   * Heroic Strike and Cleave report a cast when the swing they replace lands.
--   * A swing that hits gives rage. A gain of rage you didn't get from taking a
--     hit (you were just hit), from Bloodrage or Charge, is your weapon.
--   * Solo, your target dodging, parrying or being missed is your swing too.
-- Between those we count on with your attack speed. Main hand only; with two
-- weapons the off hand's rage is filtered out by timing, which can jitter.
--------------------------------------------------------------------------------

local W = {}
KR.Swing = W

W.speed = nil      -- main-hand attack speed in seconds
W.last = nil       -- GetTime() of the last main-hand swing we saw (or assumed)
W.attacking = false
W.seen = 0         -- swings we saw since auto-attack began

local HURT_WINDOW = 0.15 -- a rage gain this close after taking a hit is from the hit
local GIVE_WINDOW = 0.35 -- ... or after Bloodrage or Charge
local lastHurt, lastGive = -10, -10
local lastRage

local function now() return GetTime() end

local function readSpeed()
    local mh = call(UnitAttackSpeed, "player")
    if type(mh) == "number" and mh > 0 then W.speed = mh end
end

-- Record a main-hand swing at `t`; `how` is what told us.
function W:Mark(how, t)
    t = t or now()
    if not self.speed then readSpeed() end
    if not self.speed then return end
    -- the off hand and talent rage arrive between main-hand swings: too soon to be one
    if self.last and t - self.last < self.speed * 0.6 then return end
    self.last = t
    self.seen = self.seen + 1
    KR:Debug("swing (%s)", how)
    KR:Fire("SWING", how)
end

-- fraction done (0..1), seconds left, speed. nil while not attacking.
function W:Progress()
    if not (self.attacking and self.speed and self.last) then return nil end
    local t = now()
    -- a swing that missed without our noticing: count on with the attack speed
    while t - self.last > self.speed do self.last = self.last + self.speed end
    local done = (t - self.last) / self.speed
    return done, self.speed - (t - self.last), self.speed
end

function W:Reset()
    self.attacking, self.last, self.seen = false, nil, 0
end

--------------------------------------------------------------------------------

KR:OnReady("PLAYER_ENTER_COMBAT", function()
    readSpeed()
    W.attacking = true
    -- the first swing goes out as soon as you're in range
    W.last = W.speed and (now() - W.speed * 0.999) or nil
    W.seen = 0
end)

KR:OnReady("PLAYER_LEAVE_COMBAT", function() W:Reset() end)

KR:OnReady("UNIT_ATTACK_SPEED", function(unit)
    if clean(unit) ~= "player" then return end
    local old = W.speed
    readSpeed()
    -- keep the swing at the same fraction done when haste comes or goes
    if old and W.speed and W.last and old ~= W.speed then
        local t = now()
        W.last = t - (t - W.last) * W.speed / old
    end
end)

KR:OnReady("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if clean(unit) ~= "player" then return end
    local key = KR.Spells:KeyOf(clean(spellID))
    local a = key and KR.AbilityByKey[key]
    if not a then return end
    if a.swing then W:Mark(key) end
    if a.gives then lastGive = now() end
end)

KR:OnReady("UNIT_COMBAT", function(unit, action)
    unit, action = clean(unit), clean(action)
    if unit == "player" then
        if action == "WOUND" or action == "BLOCK" then lastHurt = now() end
        return
    end
    if unit ~= "target" or not W.attacking then return end
    -- with others in the group, the target's dodge may be theirs
    if call(IsInGroup) then return end
    if action == "DODGE" or action == "PARRY" or action == "MISS" or action == "BLOCK" then W:Mark(action:lower()) end
end)

local function onPower(unit, kind)
    if clean(unit) ~= "player" or (kind and clean(kind) ~= "RAGE") then return end
    local rage = KR.Spells:Rage()
    if type(rage) ~= "number" then lastRage = nil; return end
    local gain = lastRage and rage - lastRage
    lastRage = rage
    if not (gain and gain > 0 and W.attacking) then return end
    local t = now()
    if t - lastHurt < HURT_WINDOW or t - lastGive < GIVE_WINDOW then return end
    -- Bloodrage hands out 1 rage a second, Anger Management 1 every 3: a single point
    -- counts only when a swing is due anyway
    if gain <= 1 then
        if not (W.speed and W.last and t - W.last >= W.speed * 0.85) then return end
    end
    W:Mark("rage", t)
end

KR:OnReady("UNIT_POWER_UPDATE", onPower)
KR:OnReady("UNIT_POWER_FREQUENT", onPower)
KR:Listen("SETUP", function() readSpeed() end)
