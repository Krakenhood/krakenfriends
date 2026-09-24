local _, KF = ...
local call, clean = KF.call, KF.clean

--------------------------------------------------------------------------------
-- Who is who
--
-- All your characters share one account-wide database, so your alts add up
-- automatically. Your friend is recognised by BattleTag (through the
-- Battle.net friends list) whenever possible, so their alts link up on their
-- own; characters that aren't Battle.net friends are remembered by name-realm.
--------------------------------------------------------------------------------

function KF:InitPlayer()
    local name, realm = call(UnitFullName, "player")
    realm = realm or call(GetNormalizedRealmName) or ""
    local _, class = call(UnitClass, "player")
    local _, tag = call(BNGetInfo)
    self.me = {
        name = name or call(UnitName, "player") or "?",
        realm = realm,
        guid = call(UnitGUID, "player"),
        class = class,
        tag = tag,
    }
    self.me.key = self.me.name .. "-" .. realm
    self:LocalizeTypes()
    self:RefreshJourney()
end

function KF:GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if not call(UnitIsUnit, unit, "player") then units[#units + 1] = unit end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function unitIdentity(unit)
    local name, realm = call(UnitFullName, unit)
    if not name or name == "" or name == UNKNOWNOBJECT then return end
    if not realm or realm == "" then realm = KF.me.realm end
    return name .. "-" .. realm, name
end

local function battleTagFor(guid)
    if not (guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID) then return end
    local info = call(C_BattleNet.GetAccountInfoByGUID, guid)
    if type(info) == "table" then return clean(info.battleTag) end
end

function KF:FindJourney(key, guid)
    local journeys = self.db.journeys
    for _, j in pairs(journeys) do
        if j.chars.partner[key] then return j end
    end
    local tag = battleTagFor(guid)
    if tag then
        for _, j in pairs(journeys) do
            if j.partnerTag == tag then return j, tag end
        end
    end
    return nil, tag
end

function KF:BindPartner(c)
    local j = c.journey
    local _, class = call(UnitClass, c.unit)
    local level = call(UnitLevel, c.unit)
    local prev = self.partner
    local p = (prev and prev.guid == c.guid) and prev or {}
    p.unit, p.guid, p.key, p.name, p.journey = c.unit, c.guid, c.key, c.name, j
    p.class = class or p.class
    p.level = level or p.level
    if p.dead == nil then p.dead = call(UnitIsDeadOrGhost, c.unit) or false end
    self.partner = p

    local tag = c.tag or battleTagFor(c.guid)
    if tag and not j.partnerTag then j.partnerTag = tag end

    local now = time()
    local theirs = j.chars.partner[c.key] or {}
    theirs.class, theirs.level, theirs.seen = p.class or theirs.class, p.level or theirs.level, now
    j.chars.partner[c.key] = theirs
    local mine = j.chars.me[self.me.key] or {}
    mine.class, mine.level, mine.seen = self.me.class, call(UnitLevel, "player") or mine.level, now
    j.chars.me[self.me.key] = mine
    j.lastPartnerChar, j.lastMyChar = c.key, self.me.key
    self.db.active = j.id
end

-- The chapter for the two characters playing right now ("Krakenhood &
-- Thalianne"). Everything tracked lands here as well as in the journey total.
function KF:CurrentPair()
    local j, p = self.journey, self.partner
    if not (j and p and p.journey == j) then return end
    local key = self.me.key .. " & " .. p.key
    local pair = j.pairs[key]
    if not pair then
        pair = KF.NewPair(self.me.key, self.me.class, p.key, p.class)
        j.pairs[key] = pair
    end
    return pair, key
end

-- Level range the two characters were played at, shown per chapter.
function KF:NoteLevels()
    local pair = self:CurrentPair()
    if not pair then return end
    for _, level in ipairs({ call(UnitLevel, "player") or 0, self.partner.level or 0 }) do
        if level > 0 then
            pair.lvMin = math.min(pair.lvMin or level, level)
            pair.lvMax = math.max(pair.lvMax or level, level)
        end
    end
end

-- The tracked journey while your partner is around, otherwise the one you
-- played last (for display only: nothing is counted without your partner).
function KF:RefreshJourney()
    local db = self.db
    local j = self.partner and self.partner.journey or db.journeys[db.active or ""]
    if not j then
        for _, cand in pairs(db.journeys) do
            if not j or (cand.lastActive or 0) > (j.lastActive or 0) then j = cand end
        end
    end
    self.journey = j
    self:Fire("UPDATE")
end

function KF:ScanGroup()
    if not self.ready then return end
    local prevGUID = self.partner and self.partner.guid
    local found
    for _, unit in ipairs(self:GroupUnits()) do
        local guid = call(UnitGUID, unit)
        local key, name = unitIdentity(unit)
        if guid and key then
            local j, tag = self:FindJourney(key, guid)
            if j and (not found or j.id == self.db.active) then
                found = { unit = unit, guid = guid, key = key, name = name, tag = tag, journey = j }
            end
        end
    end

    if found then self:BindPartner(found) else self.partner = nil end
    if prevGUID ~= (found and found.guid) then
        self:Debug("partner: %s", found and found.key or "none")
    end
    self:RefreshJourney()
    if found then self:NoteLevels() end
    self:UpdateTogether()
    if not found then self:MaybePrompt() end
    self:Fire("PARTNER")
end

--------------------------------------------------------------------------------
-- Starting a journey
--------------------------------------------------------------------------------

if StaticPopupDialogs then
    StaticPopupDialogs.KRAKENFRIENDS_START = {
        text = "|cff4fd1c5Kraken|rfriends\n\nStart a journey with |cffffffff%s|r?\nKills, loot, dungeons and more are counted whenever you two play together.",
        button1 = "Start journey",
        button2 = "Not now",
        button3 = "Never",
        OnAccept = function(_, data) KF:StartJourneyWith(data.unit, data.guid) end,
        OnAlt = function(_, data) KF.db.ignored[data.key] = true end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local prompted = {}

-- In a two-person group with someone new, offer to start a journey.
function KF:MaybePrompt()
    if not IsInGroup() or IsInRaid() or GetNumGroupMembers() ~= 2 then return end
    local unit = "party1"
    local guid = call(UnitGUID, unit)
    local key, name = unitIdentity(unit)
    if not (guid and key) or prompted[key] or self.db.ignored[key] then return end
    prompted[key] = true
    C_Timer.After(1.5, function()
        if self.partner or call(UnitGUID, unit) ~= guid then return end
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopup_Show("KRAKENFRIENDS_START", name, nil, { unit = unit, guid = guid, key = key })
        else
            self:Printf("grouped with %s. Type /kf partner to start your journey together.", name)
        end
    end)
end

function KF:StartJourneyWith(unit, guid)
    if call(UnitGUID, unit) ~= guid then
        unit = nil
        for _, u in ipairs(self:GroupUnits()) do
            if call(UnitGUID, u) == guid then unit = u break end
        end
        if not unit then return end
    end
    local key, name = unitIdentity(unit)
    if not key then return end
    self.db.ignored[key] = nil

    local j, tag = self:FindJourney(key, guid)
    if j then
        self.db.active = j.id
        self:Printf("you're already on a journey with %s.", j.partnerName or name)
    else
        tag = tag or battleTagFor(guid)
        local id = tag or ("char:" .. key)
        j = self.db.journeys[id] or self:NewJourney(id, tag and tag:match("^[^#]+") or name, tag)
        local _, class = call(UnitClass, unit)
        j.chars.partner[key] = { class = class, level = call(UnitLevel, unit), seen = time() }
        self.db.active = j.id
        self:BindPartner({ unit = unit, guid = guid, key = key, name = name, tag = tag, journey = j })
        self:RefreshJourney()
        self:Log("start", ("Your journey with %s began"):format(j.partnerName))
        self:Printf("journey with %s started. Have fun out there!", j.partnerName)
    end
    self:ScanGroup()
end

function KF:SetPartnerCommand(arg)
    local units = self:GroupUnits()
    if #units == 0 then
        self:Print("group up with your friend first, then use /kf partner.")
        return
    end
    arg = strtrim(arg or ""):lower()
    local pick
    for _, unit in ipairs(units) do
        local _, name = unitIdentity(unit)
        if arg ~= "" then
            if name and name:lower() == arg then pick = unit end
        elseif call(UnitIsUnit, unit, "target") then
            pick = unit
        end
    end
    if not pick and arg == "" and #units == 1 then pick = units[1] end
    if not pick then
        self:Print("couldn't tell who you mean. Target your friend, or use /kf partner Name.")
        return
    end
    self:StartJourneyWith(pick, call(UnitGUID, pick))
end

--------------------------------------------------------------------------------
-- Together or apart
--
-- Counting only happens while your partner is in your group, online and near
-- you: within sight (about 100 yards) or at least in the same zone.
--------------------------------------------------------------------------------

function KF:UpdateTogether()
    local p = self.partner
    if p and call(UnitGUID, p.unit) ~= p.guid then
        return self:ScanGroup() -- roster shifted under us
    end
    local together = false
    if p and call(UnitIsConnected, p.unit) then
        if call(UnitIsVisible, p.unit) then
            together = true
        elseif C_Map and C_Map.GetBestMapForUnit then
            local mine = call(C_Map.GetBestMapForUnit, "player")
            together = mine ~= nil and mine == call(C_Map.GetBestMapForUnit, p.unit)
        end
    end
    if together ~= self.together then
        self.together = together
        self:Debug("together: %s", together)
        self:Fire("TOGETHER", together)
    end
end

function KF:PartnerPetGUID()
    local p = self.partner
    if not p then return end
    local pet = p.unit:gsub("^party", "partypet"):gsub("^raid", "raidpet")
    return call(UnitGUID, pet)
end

function KF:PrintStatus()
    local p, j = self.partner, self.journey
    self:Printf("v%s, data source: %s", self.version, self.dbSource or "?")
    if p then
        self:Printf("partner: %s (%s), %s", KF.ClassText(p.name, p.class), p.unit,
            self.together and "|cff5cdb78together: tracking|r" or "|cff8a8f98apart: paused|r")
    else
        self:Print("partner: nobody from your journeys is in your group" .. (j and (" (last journey: " .. (j.partnerName or "?") .. ")") or ""))
    end
    if j then
        self:Printf("journey: %s kills, %s together, %d dungeon runs", KF.FormatNumber(j.total.kills), KF.FormatDuration(j.total.time), j.total.runs)
    end
    if #self.missingEvents > 0 then
        self:Print("not available on this client: " .. table.concat(self.missingEvents, ", "))
    end
end

--------------------------------------------------------------------------------

local lastBNetScan = 0

KF:On("GROUP_ROSTER_UPDATE", function() KF:ScanGroup() end)
KF:On("PLAYER_ENTERING_WORLD", function() KF:ScanGroup() end)
KF:On("UNIT_CONNECTION", function() KF:UpdateTogether() end)
KF:On("BN_FRIEND_INFO_CHANGED", function()
    -- a friend's BattleTag may only resolve once their presence loads
    if KF.partner or not IsInGroup() or GetTime() - lastBNetScan < 5 then return end
    lastBNetScan = GetTime()
    KF:ScanGroup()
end)
