local _, KR = ...
local call = KR.call

--------------------------------------------------------------------------------
-- What this warrior knows and can do right now: abilities with their real rage
-- cost (talents change them), the stance, rage, usability and buffs.
--------------------------------------------------------------------------------

local S = {}
KR.Spells = S

S.known = {}   -- key -> { ability, id = known rank, name, cost, icon }
S.byName = {}  -- localized spell name -> ability key, to recognise casts of any rank

local RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return call(C_Spell.GetSpellName, id) end
    if GetSpellInfo then return (call(GetSpellInfo, id)) end
end

-- The rank of a spell this character knows, by name (the client answers a name
-- lookup with the highest rank in the spellbook, and with nothing for an unknown spell).
local function knownRank(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = call(C_Spell.GetSpellInfo, name)
        if type(info) == "table" and type(info.spellID) == "number" then return info.spellID, info.iconID end
        return nil
    end
    if GetSpellInfo then
        local _, _, icon, _, _, _, id = call(GetSpellInfo, name)
        if type(id) == "number" then return id, icon end
    end
end

local function rageCost(id, fallback)
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    local costs = get and call(get, id)
    if type(costs) == "table" then
        for _, c in ipairs(costs) do
            local kind, amount = KR.clean(c.type), KR.clean(c.cost)
            if kind == RAGE and type(amount) == "number" then return amount end
        end
    end
    return fallback
end

local function spellIcon(id, fallback)
    local get = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    local tex = get and call(get, id)
    return tex or ("Interface\\Icons\\" .. fallback)
end

S.SpellName, S.SpellIcon = spellName, spellIcon

function S:Scan()
    wipe(self.known)
    wipe(self.byName)
    for _, a in ipairs(KR.Abilities) do
        local name = spellName(a.id)
        if type(name) == "string" then
            self.byName[name] = a.key
            local id, icon = knownRank(name)
            -- a lookup that works on a spell you don't know would claim it; check the spellbook too
            if id and (IsPlayerSpell or IsSpellKnown) then
                local inBook = (IsPlayerSpell and call(IsPlayerSpell, id)) or (IsSpellKnown and call(IsSpellKnown, id))
                if not inBook then id = nil end
            end
            if id then
                self.known[a.key] = {
                    ability = a, id = id, name = name,
                    cost = rageCost(id, a.cost),
                    icon = icon or spellIcon(id, a.icon),
                }
            end
        end
    end
    for _, st in ipairs(KR.Stances) do
        st.label = spellName(st.id) or st.name
        st.texture = spellIcon(st.id, st.icon)
    end
    KR:Fire("SPELLS")
end

function S:Known(key) return self.known[key] end

function S:KeyOf(spellID)
    local name = spellName(spellID)
    if name then return self.byName[name] end
    for _, a in ipairs(KR.Abilities) do
        if a.id == spellID then return a.key end
    end
end

--------------------------------------------------------------------------------
-- Rage
--------------------------------------------------------------------------------

-- Current and maximum rage. `raw` is the unchecked value, which a status bar can
-- still show even when the game hands it out as a secret.
function S:Rage()
    local raw = UnitPower and UnitPower("player", RAGE)
    local rage = KR.clean(raw)
    local max = call(UnitPowerMax, "player", RAGE)
    if type(max) ~= "number" or max <= 0 then max = 100 end
    return type(rage) == "number" and rage or nil, max, raw
end

--------------------------------------------------------------------------------
-- Stance
--------------------------------------------------------------------------------

-- The stance entry (from KR.Stances) you're in, or nil.
function S:Stance()
    local index = call(GetShapeshiftForm)
    if type(index) ~= "number" or index <= 0 then return nil end
    if GetShapeshiftFormInfo then
        local _, _, _, id = call(GetShapeshiftFormInfo, index)
        if type(id) == "number" then
            for _, st in ipairs(KR.Stances) do
                if spellName(st.id) == spellName(id) then return st end
            end
        end
    end
    return KR.Stances[index]
end

function S:StanceKey()
    local st = self:Stance()
    return st and st.key
end

-- Can `ability` be used in the stance you're in? (true when it doesn't care)
function S:StanceFits(ability, stanceKey)
    if not ability.stances then return true end
    stanceKey = stanceKey or self:StanceKey()
    for _, k in ipairs(ability.stances) do
        if k == stanceKey then return true end
    end
    return false
end

-- The rage you keep on a stance switch. The game sets your rage to at most this
-- much (Tactical Mastery adds 5 per point). Learned from the switches you make;
-- until then read from the talent, if the client lets us.
function S:Keep()
    local learned = KR.char and KR.char.keep
    if type(learned) == "number" then return learned end
    if self.talentKeep == nil then
        self.talentKeep = false
        local tmName = spellName(KR.TACTICAL_MASTERY)
        if tmName and GetNumTalentTabs and GetNumTalents and GetTalentInfo then
            for tab = 1, call(GetNumTalentTabs) or 0 do
                for i = 1, call(GetNumTalents, tab) or 0 do
                    local name, _, _, _, rank = call(GetTalentInfo, tab, i)
                    if name == tmName and type(rank) == "number" then self.talentKeep = rank * 5 end
                end
            end
        end
    end
    return self.talentKeep or 0
end

--------------------------------------------------------------------------------
-- Usability, cooldowns, queued swings
--------------------------------------------------------------------------------

-- usable, notEnoughRage. Both nil when the game won't say.
function S:Usable(key)
    local k = self.known[key]
    if not k then return false end
    if C_Spell and C_Spell.IsSpellUsable then return call(C_Spell.IsSpellUsable, k.id) end
    if IsUsableSpell then return call(IsUsableSpell, k.name) end
end

-- Seconds until the ability is ready (0 when ready or only the global cooldown runs).
function S:CooldownLeft(key)
    local k = self.known[key]
    if not k then return nil end
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = call(C_Spell.GetSpellCooldown, k.id)
        if type(info) == "table" then start, duration = KR.clean(info.startTime), KR.clean(info.duration) end
    elseif GetSpellCooldown then
        start, duration = call(GetSpellCooldown, k.name)
    end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if start == 0 or duration <= 1.5 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- Is Heroic Strike (or Cleave) waiting for the next swing?
function S:Queued(key)
    local k = self.known[key]
    if not k then return false end
    if C_Spell and C_Spell.IsCurrentSpell then return call(C_Spell.IsCurrentSpell, k.id) and true or false end
    return IsCurrentSpell and call(IsCurrentSpell, k.id) and true or false
end

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

-- The aura called `name` on `unit`: count, seconds left (nil when either is unknown).
-- Returns false when it isn't there, nil when the game won't tell.
function S:Aura(unit, name, harmful)
    if not name then return nil end
    local filter = harmful and "HARMFUL" or "HELPFUL"
    for i = 1, 40 do
        local auraName, count, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local raw = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if raw == nil then break end
            auraName = KR.clean(raw.name)
            count, expires = KR.clean(raw.applications), KR.clean(raw.expirationTime)
            if auraName == nil and issecretvalue and issecretvalue(raw.name) then return nil end
        elseif UnitAura then
            local n, _, c, _, _, e = UnitAura(unit, i, filter)
            if n == nil then break end
            if issecretvalue and issecretvalue(n) then return nil end
            auraName, count, expires = n, KR.clean(c), KR.clean(e)
        else
            return nil
        end
        if auraName == name then
            local left = type(expires) == "number" and expires > 0 and math.max(0, expires - GetTime()) or nil
            return true, type(count) == "number" and math.max(count, 1) or 1, left
        end
    end
    return false
end

function S:HasBuff(key)
    local k = self.known[key]
    local name = k and k.name or spellName(KR.AbilityByKey[key].id)
    return self:Aura("player", name, false)
end

-- Sunder Armor stacks on your target (from anyone): count, or nil when unknown.
function S:SunderStacks()
    local name = self.known.sunder and self.known.sunder.name
    if not name or not call(UnitExists, "target") then return nil end
    local found, count = self:Aura("target", name, true)
    if found == nil then return nil end
    return found and count or 0
end

-- The enemy you have targeted: name, classification, level, GUID, dead. nil when there's none.
function S:Target()
    if not call(UnitExists, "target") or not call(UnitCanAttack, "player", "target") then return nil end
    local name = call(UnitName, "target")
    if type(name) ~= "string" then return nil end
    return name, call(UnitClassification, "target"), call(UnitLevel, "target"), call(UnitGUID, "target"), call(UnitIsDead, "target")
end

-- Target health in percent, or nil when it's a secret.
function S:TargetHealth()
    if not call(UnitExists, "target") then return nil end
    local hp, max = call(UnitHealth, "target"), call(UnitHealthMax, "target")
    if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    return 100 * hp / max
end

--------------------------------------------------------------------------------

local function rescan() if KR.active then S:Scan() end end
KR:Listen("SETUP", function() S:Scan() end)
KR:On("SPELLS_CHANGED", rescan)
KR:On("LEARNED_SPELL_IN_TAB", rescan)
KR:On("CHARACTER_POINTS_CHANGED", function()
    S.talentKeep = nil
    if KR.char then KR.char.keep = nil end -- talents changed: learn it again
    rescan()
end)
