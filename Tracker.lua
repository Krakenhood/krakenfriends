local _, KF = ...
local call, clean = KF.call, KF.clean

local T = {}
KF.Tracker = T

local RUN_TIMEOUT = 30 * 60 -- a dungeon run survives this long outside (corpse runs, repairs)
local FORGET_AFTER = 10 * 60

local mobs = {}     -- guid -> what we know about a hostile unit we've seen
local counted = {}  -- guid -> { t, by } for kills already recorded
local lastBoss = {} -- boss name -> time, so ENCOUNTER_END, BOSS_KILL and the kill itself count once
local lastPartnerDeath = 0

--------------------------------------------------------------------------------
-- Reading units
--
-- Forever has no combat log for addons. Kills come from the PARTY_KILL and
-- UNIT_DIED events, which only carry GUIDs, so we remember what each hostile
-- unit was (name, creature type, rank) while it's visible as a target,
-- nameplate or mouseover, and whether it was fighting one of us.
--------------------------------------------------------------------------------

local function guidParts(guid)
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

local function describe(unit, guid)
    local _, npc = guidParts(guid)
    local info = { name = call(UnitName, unit), npc = npc, seen = time() }
    if call(UnitIsPlayer, unit) then
        info.type = "player"
    else
        local _, typeID = call(UnitCreatureType, unit)
        info.type = typeID and KF.CreatureTypes[typeID] or "unspecified"
    end
    info.cls = call(UnitClassification, unit)
    info.level = call(UnitLevel, unit)
    info.boss = call(UnitIsBossMob, unit) or info.cls == "worldboss"
    return info
end

function T:FightingUs(unit)
    local p = KF.partner
    if call(UnitThreatSituation, "player", unit) or call(UnitThreatSituation, "pet", unit) then return true end
    if p and call(UnitThreatSituation, p.unit, unit) then return true end
    local target = unit .. "target"
    return call(UnitIsUnit, target, "player") or call(UnitIsUnit, target, "pet")
        or (p and call(UnitIsUnit, target, p.unit)) or false
end

function T:ScanUnit(unit)
    unit = clean(unit)
    if not unit or not call(UnitExists, unit) then return end
    local guid = call(UnitGUID, unit)
    if not guid then return end
    local info = mobs[guid]
    if not info then
        if call(UnitIsUnit, unit, "player") or not call(UnitCanAttack, "player", unit) then return end
        info = describe(unit, guid)
        mobs[guid] = info
    else
        info.seen = time()
    end
    if not info.engaged and not call(UnitIsTapDenied, unit) and self:FightingUs(unit) then
        info.engaged = true
    end
    return info
end

local SCAN_UNITS = { "target", "focus", "mouseover", "pettarget", "targettarget" }

function T:ScanAll()
    for i = 1, #SCAN_UNITS do self:ScanUnit(SCAN_UNITS[i]) end
    if KF.partner then self:ScanUnit(KF.partner.unit .. "target") end
    for i = 1, 40 do self:ScanUnit("nameplate" .. i) end
end

function T:DescribeGUID(guid)
    local unit = UnitTokenFromGUID and call(UnitTokenFromGUID, guid)
    if unit then
        local info = describe(unit, guid)
        mobs[guid] = info
        return info
    end
    local kind, npc = guidParts(guid)
    return { name = call(UnitNameFromGUID, guid), npc = npc, type = kind == "Player" and "player" or "unknown", seen = time() }
end

function T:Prune()
    local cutoff = time() - FORGET_AFTER
    for guid, info in pairs(mobs) do
        if (info.seen or 0) < cutoff then mobs[guid] = nil end
    end
    for guid, c in pairs(counted) do
        if c.t < cutoff then counted[guid] = nil end
    end
end

--------------------------------------------------------------------------------
-- Kills
--------------------------------------------------------------------------------

function T:RecordKill(guid, by, via)
    local seen = counted[guid]
    if seen then
        -- UNIT_DIED got here first; PARTY_KILL still knows who landed the blow
        if by and not seen.by then
            seen.by = by
            if by == "me" then KF:Add("kbMe") elseif by == "partner" then KF:Add("kbPartner") end
            KF:Fire("UPDATE")
        end
        return
    end
    if not KF.together then return end

    local info = mobs[guid] or self:DescribeGUID(guid)
    counted[guid] = { t = time(), by = by }
    local j, pair = KF.journey, KF:CurrentPair()

    KF:Add("kills")
    KF:Add("types", 1, info.type or "unknown")
    if by == "me" then KF:Add("kbMe") elseif by == "partner" then KF:Add("kbPartner") end

    local cls = info.cls
    if cls == "elite" or cls == "rareelite" or cls == "worldboss" then KF:Add("elite") end
    if cls == "rare" or cls == "rareelite" then self:RecordRare(info) end

    local key = info.npc or info.name
    if key then
        local m = pair.mobs[key]
        if not m then
            m = { n = info.name, c = 0, ty = info.type }
            pair.mobs[key] = m
        end
        m.c = m.c + 1
        m.n = m.n or info.name
        if info.level and info.level > (m.lv or 0) then m.lv = info.level end
    end
    if info.name and info.level and info.type ~= "critter" and info.level > ((pair.toughest and pair.toughest.lv) or 0) then
        pair.toughest = { n = info.name, lv = info.level }
    end

    local run = j.currentRun
    if run and run.inside then run.kills = (run.kills or 0) + 1 end
    -- where the game reports encounters, ENCOUNTER_END is the better boss signal
    if info.boss and not (run and run.encounters) then self:RecordBoss(info.name) end

    KF:Debug("kill: %s [%s, %s] blow: %s, via %s", info.name, info.type, cls, by or "?", via)
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

function T:RecordRare(info)
    KF:Add("rare")
    local pair = KF:CurrentPair()
    local key = info.npc or info.name or "?"
    local r = pair.rares[key]
    if not r then
        r = { n = info.name, c = 0, t = time(), lv = info.level }
        pair.rares[key] = r
    end
    r.c = r.c + 1
    if KF:First("rare", key) then
        KF:Log("rare", info.name and ("Slew %s (rare)"):format(info.name) or "Slew a rare")
        KF:Toast("Rare slain!", info.name or "A rare foe falls.", "rare")
    end
end

function T:RecordBoss(name)
    if not name or not KF.together then return end
    local now = time()
    if lastBoss[name] and now - lastBoss[name] < 120 then return end
    lastBoss[name] = now

    KF:Add("boss")
    local j, pair = KF.journey, KF:CurrentPair()
    local b = pair.bosses[name]
    if not b then
        b = { c = 0, t = now }
        pair.bosses[name] = b
    end
    b.c = b.c + 1
    if KF:First("boss", name) then
        KF:Log("boss", ("Defeated %s for the first time"):format(name))
    end
    local run = j.currentRun
    if run then
        run.bosses = (run.bosses or 0) + 1
        local owner = j.pairs[run.pair] or pair
        local d = owner.dungeons[run.id]
        if d then d.bosses = (d.bosses or 0) + 1 end
    end
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

function T:OnPartyKill(attackerGUID, targetGUID)
    attackerGUID, targetGUID = clean(attackerGUID), clean(targetGUID)
    local p = KF.partner
    if not targetGUID or not p or targetGUID == KF.me.guid or targetGUID == p.guid then return end
    local by = "group"
    if attackerGUID then
        if attackerGUID == KF.me.guid or attackerGUID == call(UnitGUID, "pet") then
            by = "me"
        elseif attackerGUID == p.guid or attackerGUID == KF:PartnerPetGUID() then
            by = "partner"
        end
    end
    self:RecordKill(targetGUID, by, "PARTY_KILL")
end

-- Covers kills PARTY_KILL misses (pets, DoTs, a helpful NPC finishing it off),
-- but only for units we saw fighting one of us.
function T:OnUnitDied(guid)
    guid = clean(guid)
    local p = KF.partner
    if not guid or not p or guid == KF.me.guid then return end
    if guid == p.guid then return self:PartnerDied() end
    local info = mobs[guid]
    if counted[guid] or not (info and info.engaged) then return end
    C_Timer.After(0.3, function() T:RecordKill(guid, nil, "UNIT_DIED") end)
end

function T:OnTargetDied()
    if not KF.partner then return end
    local guid = call(UnitGUID, "target")
    local info = guid and mobs[guid]
    if not info or counted[guid] or not info.engaged or call(UnitIsTapDenied, "target") then return end
    C_Timer.After(0.3, function() T:RecordKill(guid, nil, "PLAYER_TARGET_DIED") end)
end

--------------------------------------------------------------------------------
-- Loot and gold, parsed with the client's own (localized) chat strings
--------------------------------------------------------------------------------

local P = {}

local function toPattern(fmt, anchored)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
    return anchored and ("^" .. p .. "$") or p
end
T.toPattern = toPattern

local function patterns(...)
    local list = {}
    for i = 1, select("#", ...) do
        local p = toPattern(select(i, ...), true)
        if p then list[#list + 1] = p end
    end
    return list
end

local function match(text, pattern)
    if pattern then return text:match(pattern) end
end

function T:BuildPatterns()
    P.lootSelfMulti = toPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.", true)
    P.lootSelf      = toPattern(LOOT_ITEM_SELF or "You receive loot: %s.", true)
    P.lootMulti     = toPattern(LOOT_ITEM_MULTIPLE or "%s receives loot: %sx%d.", true)
    P.loot          = toPattern(LOOT_ITEM or "%s receives loot: %s.", true)
    P.moneySplit    = patterns(LOOT_MONEY_SPLIT or "Your share of the loot is %s.", LOOT_MONEY_SPLIT_GUILD)
    P.moneySolo     = patterns(YOU_LOOT_MONEY or "You loot %s", YOU_LOOT_MONEY_GUILD)
    P.gold          = toPattern(GOLD_AMOUNT or "%d Gold")
    P.silver        = toPattern(SILVER_AMOUNT or "%d Silver")
    P.copper        = toPattern(COPPER_AMOUNT or "%d Copper")
    P.reset         = toPattern(INSTANCE_RESET_SUCCESS or "%s has been reset.", true)
end

local function parseMoney(s)
    local function amount(pattern, icon)
        local n = match(s, pattern) or s:match("(%d+)%s*|T[^|]*" .. icon)
        return tonumber(n) or 0
    end
    return amount(P.gold, "Gold") * 10000 + amount(P.silver, "Silver") * 100 + amount(P.copper, "Copper")
end
T.parseMoney = parseMoney

local function qualityOf(link, itemID)
    local q = C_Item and call(C_Item.GetItemQualityByID, itemID)
    if type(q) == "number" then return q end
    q = tonumber(link:match("|cnIQ(%d)"))
    if q then return q end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if hex and ITEM_QUALITY_COLORS then
        hex = hex:lower()
        for quality, c in pairs(ITEM_QUALITY_COLORS) do
            if type(c) == "table" and type(c.hex) == "string" and c.hex:lower():find(hex, 1, true) then return quality end
        end
    end
    return 1
end

function T:IsPartnerName(name, guid)
    local p = KF.partner
    if not p then return false end
    if guid and guid == p.guid then return true end
    return name == p.name or name == p.key or name:match("^([^%-]+)") == p.name
end

function T:OnLoot(text, _, _, _, _, _, _, _, _, _, _, guid)
    text = clean(text)
    if not text or not KF.together then return end
    local link, qty = match(text, P.lootSelfMulti)
    if not link then link = match(text, P.lootSelf) end
    local who = link and "me"
    if not link then
        local name
        name, link, qty = match(text, P.lootMulti)
        if not name then name, link = match(text, P.loot) end
        if not (name and self:IsPartnerName(name, clean(guid))) then return end
        who = "partner"
    end
    local itemID = link and tonumber(link:match("item:(%d+)"))
    if itemID then self:RecordItem(who, itemID, link, tonumber(qty) or 1) end
end

function T:RecordItem(who, itemID, link, qty)
    local q = qualityOf(link, itemID)
    KF:Add(who == "me" and "lootMe" or "lootPartner", qty, q)
    if q >= 2 then
        local pair, now = KF:CurrentPair(), time()
        local item = pair.items[itemID]
        if not item then
            item = { n = link:match("%[(.-)%]"), q = q, c = 0, t = now }
            pair.items[itemID] = item
        end
        item.c, item.l = item.c + qty, now
        if who == "me" then item.me = (item.me or 0) + qty else item.pa = (item.pa or 0) + qty end
        if q >= 4 then
            local _, r, g, b = KF.QualityInfo(q)
            local text = ("%s found %s"):format(who == "me" and KF.me.name or KF.partner.name, KF.Colorize(item.n or "?", r, g, b))
            KF:Log("loot", text)
            KF:Toast("Epic find!", text, "epic")
        end
    end
    KF:Debug("loot: %s x%s (quality %s) by %s", link, qty, q, who)
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

function T:OnMoney(text)
    text = clean(text)
    if not text or not KF.together then return end
    for _, pattern in ipairs(P.moneySplit) do
        local s = text:match(pattern)
        if s then return self:RecordMoney(parseMoney(s), true) end
    end
    for _, pattern in ipairs(P.moneySolo) do
        local s = text:match(pattern)
        if s then return self:RecordMoney(parseMoney(s), false) end
    end
end

-- Group loot money is split evenly, so the duo's part of a split pile is
-- twice your share.
function T:RecordMoney(copper, split)
    if copper <= 0 then return end
    KF:Add("goldMe", copper)
    KF:Add("goldDuo", split and copper * 2 or copper)
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

--------------------------------------------------------------------------------
-- Dungeon runs: entering a dungeon with your partner in the group starts a
-- run. Stepping out and back in (corpse run) continues it; entering another
-- dungeon, resetting it, or 30 minutes outside ends it.
--------------------------------------------------------------------------------

function T:CheckInstance()
    local j = KF.journey
    if not j then return end
    local ok, name, itype, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not ok then return end
    name, itype, instanceID = clean(name), clean(itype), clean(instanceID)
    local dungeon = (itype == "party" or itype == "raid") and instanceID or nil
    local run, now = j.currentRun, time()

    if run then
        local stale = not run.inside and now - (run.last or 0) > RUN_TIMEOUT
        if stale or (dungeon and dungeon ~= run.id) then
            self:FinishRun(j)
            run = nil
        else
            run.inside = dungeon == run.id
            if run.inside then run.last = now end
        end
    end
    if dungeon and not run and KF.partner then
        self:StartRun(j, dungeon, name)
    end
end

function T:StartRun(j, id, name)
    local pair, pairKey = KF:CurrentPair()
    if not pair then return end
    local now = time()
    j.currentRun = { id = id, n = name, pair = pairKey, start = now, last = now, inside = true, kills = 0, bosses = 0, deaths = 0 }
    KF:Add("runs")
    local d = pair.dungeons[id]
    if not d then
        d = { n = name, runs = 0, time = 0, bosses = 0 }
        pair.dungeons[id] = d
    end
    d.runs, d.last, d.n = d.runs + 1, now, name or d.n
    if KF:First("dungeon", id) then
        KF:Log("dungeon", ("First run through %s"):format(name or "a dungeon"))
    end
    KF:Debug("run started: %s (#%s)", name, d.runs)
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

function T:FinishRun(j)
    local run = j.currentRun
    if not run then return end
    j.currentRun = nil
    local owner = j.pairs[run.pair]
    if not owner then return end
    local dur = math.max(0, (run.last or run.start) - run.start)
    local d = owner.dungeons[run.id]
    if d then d.time = (d.time or 0) + dur end
    table.insert(owner.runs, 1, { n = run.n, start = run.start, dur = dur, kills = run.kills, bosses = run.bosses, deaths = run.deaths })
    while #owner.runs > 30 do table.remove(owner.runs) end
    KF:Debug("run finished: %s, %ss", run.n, dur)
    KF:Fire("UPDATE")
end

function T:OnSystemMessage(text)
    text = clean(text)
    local j = KF.journey
    local run = j and j.currentRun
    if not (text and run and P.reset) or run.inside then return end
    if text:match(P.reset) == run.n then self:FinishRun(j) end
end

--------------------------------------------------------------------------------
-- Deaths, levels, quests, zones
--------------------------------------------------------------------------------

local function currentRunInside()
    local run = KF.journey and KF.journey.currentRun
    return run and run.inside and run
end

function T:PartnerDied()
    local p = KF.partner
    if not p then return end
    p.dead = true
    local now = GetTime()
    if now - lastPartnerDeath < 15 then return end
    lastPartnerDeath = now
    if not KF.together then return end
    KF:Add("deathsPartner")
    local run = currentRunInside()
    if run then run.deaths = run.deaths + 1 end
    KF:Fire("UPDATE")
end

function T:OnPlayerDead()
    if not KF.together then return end
    KF:Add("deathsMe")
    local run = currentRunInside()
    if run then run.deaths = run.deaths + 1 end
    KF:Fire("UPDATE")
end

-- Backup for UNIT_DIED: watch the partner's dead state flip.
function T:OnUnitHealth(unit)
    local p = KF.partner
    if not p or unit ~= p.unit then return end
    local dead = call(UnitIsDeadOrGhost, unit)
    if dead and not p.dead then
        self:PartnerDied()
    elseif dead == false then
        p.dead = false
    end
end

function T:OnLevelUp(level)
    level = clean(level)
    local p = KF.partner
    if not (level and p) then return end
    local mine = p.journey.chars.me[KF.me.key]
    if mine then mine.level = level end
    KF:NoteLevels()
    if not KF.together then return end
    KF:Add("levelsMe")
    KF:Log("level", ("%s reached level %s"):format(KF.me.name, level))
end

function T:OnUnitLevel(unit)
    local p = KF.partner
    if not p or unit ~= p.unit then return end
    local level = call(UnitLevel, unit)
    if not level then return end
    local old = p.level
    p.level = level
    local theirs = p.journey.chars.partner[p.key]
    if theirs then theirs.level = level end
    KF:NoteLevels()
    if old and level > old and KF.together then
        KF:Add("levelsPartner")
        KF:Log("level", ("%s reached level %s"):format(p.name, level))
    end
end

function T:OnQuestTurnedIn()
    if not KF.together then return end
    KF:Add("quests")
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

function T:CheckZone()
    if not KF.together then return end
    local zone = call(GetRealZoneText)
    local pair = KF:CurrentPair()
    if not zone or zone == "" or not pair then return end
    pair.zones[zone] = pair.zones[zone] or time()
    if KF:First("zone", zone) then
        KF:Log("zone", ("Discovered %s together"):format(zone))
    end
end

--------------------------------------------------------------------------------
-- Heartbeat: together-check, time together, run timeouts
--------------------------------------------------------------------------------

local lastTick, ticks = 0, 0

local function heartbeat()
    local now = GetTime()
    local elapsed = now - lastTick
    lastTick = now
    KF:UpdateTogether()
    -- skip long gaps (loading screens) rather than guess
    if KF.together and elapsed < 10 then KF:Add("time", elapsed) end
    ticks = ticks + 1
    if ticks % 5 == 0 then
        T:CheckInstance()
        T:Prune()
        KF:CheckMilestones()
    end
    KF:Fire("TICK")
end

local scanTicker

KF:Listen("LOGIN", function()
    T:BuildPatterns()
    lastTick = GetTime()
    C_Timer.NewTicker(2, function()
        local ok, err = pcall(heartbeat)
        if not ok then KF:ReportError(err) end
    end)
end)

KF:Listen("TOGETHER", function(together)
    if together then
        T:CheckZone()
        T:CheckInstance()
    end
end)

KF:Listen("PARTNER", function() T:CheckInstance() end)

--------------------------------------------------------------------------------

local function whenReady(fn)
    return function(...)
        if KF.ready then fn(...) end
    end
end

local function scanWithPartner(unit)
    if KF.partner then T:ScanUnit(unit) end
end

KF:On("PARTY_KILL", whenReady(function(a, t) T:OnPartyKill(a, t) end))
KF:On("UNIT_DIED", whenReady(function(guid) T:OnUnitDied(guid) end))
KF:On("PLAYER_TARGET_DIED", whenReady(function() T:OnTargetDied() end))

KF:On("PLAYER_TARGET_CHANGED", whenReady(function() scanWithPartner("target") end))
KF:On("UPDATE_MOUSEOVER_UNIT", whenReady(function() scanWithPartner("mouseover") end))
KF:On("NAME_PLATE_UNIT_ADDED", whenReady(scanWithPartner))
KF:On("UNIT_THREAT_LIST_UPDATE", whenReady(scanWithPartner))
KF:On("UNIT_TARGET", whenReady(function(unit)
    local p = KF.partner
    if p and unit == p.unit then T:ScanUnit(unit .. "target") end
end))

KF:On("PLAYER_REGEN_DISABLED", whenReady(function()
    if scanTicker or not KF.partner then return end
    T:ScanAll()
    scanTicker = C_Timer.NewTicker(0.5, function() pcall(T.ScanAll, T) end)
end))
KF:On("PLAYER_REGEN_ENABLED", function()
    if scanTicker then scanTicker:Cancel(); scanTicker = nil end
end)

KF:On("CHAT_MSG_LOOT", whenReady(function(...) T:OnLoot(...) end))
KF:On("CHAT_MSG_MONEY", whenReady(function(text) T:OnMoney(text) end))
KF:On("CHAT_MSG_SYSTEM", whenReady(function(text) T:OnSystemMessage(text) end))

KF:On("ENCOUNTER_START", whenReady(function()
    local run = KF.journey and KF.journey.currentRun
    if run then run.encounters = true end
end))
KF:On("ENCOUNTER_END", whenReady(function(_, name, _, _, success)
    if clean(success) == 1 then T:RecordBoss(clean(name)) end
end))
KF:On("BOSS_KILL", whenReady(function(_, name) T:RecordBoss(clean(name)) end))

KF:On("PLAYER_DEAD", whenReady(function() T:OnPlayerDead() end))
KF:On("UNIT_HEALTH", whenReady(function(unit) T:OnUnitHealth(unit) end))
KF:On("PLAYER_LEVEL_UP", whenReady(function(level) T:OnLevelUp(level) end))
KF:On("UNIT_LEVEL", whenReady(function(unit) T:OnUnitLevel(unit) end))
KF:On("QUEST_TURNED_IN", whenReady(function() T:OnQuestTurnedIn() end))
KF:On("ZONE_CHANGED_NEW_AREA", whenReady(function() T:CheckZone(); T:CheckInstance() end))
KF:On("PLAYER_ENTERING_WORLD", whenReady(function() T:CheckZone(); T:CheckInstance() end))
