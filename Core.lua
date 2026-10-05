local ADDON, KF = ...
Krakenfriends = KF -- global handle, handy for /dump Krakenfriends.partner

local floor = math.floor
local DB_VERSION = 1
local LOG_CAP = 400

KF.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"

--------------------------------------------------------------------------------
-- Secret-value safety
--
-- Forever runs the Midnight "secret values" system: some reads come back as
-- opaque values that throw on arithmetic, comparison and even ==. The only
-- safe test is issecretvalue(), so every value we read from the game goes
-- through clean() before we look at it, and API calls go through call().
--------------------------------------------------------------------------------

local issecretvalue = issecretvalue

local function clean(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
KF.clean = clean

function KF.call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return clean(a), clean(b), clean(c), clean(d)
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

function KF.FormatNumber(n)
    n = floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s, k = tostring(n), nil
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

function KF.FormatMoney(copper, short)
    copper = floor(copper or 0)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if short then
        if g > 0 then return KF.FormatNumber(g) .. GOLD_ICON end
        if s > 0 then return s .. SILVER_ICON end
        return c .. COPPER_ICON
    end
    local parts = {}
    if g > 0 then parts[#parts + 1] = KF.FormatNumber(g) .. GOLD_ICON end
    if s > 0 then parts[#parts + 1] = s .. SILVER_ICON end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER_ICON end
    return table.concat(parts, " ")
end

function KF.FormatDuration(sec)
    sec = floor(sec or 0)
    local d, h, m = floor(sec / 86400), floor(sec / 3600) % 24, floor(sec / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

function KF.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

function KF.Colorize(text, r, g, b)
    return ("|cff%02x%02x%02x%s|r"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5), text)
end

function KF.ClassText(text, class)
    return KF.Colorize(text or "?", KF.ClassColor(class))
end

--------------------------------------------------------------------------------
-- Chat output
--------------------------------------------------------------------------------

local PREFIX = "|cff4fd1c5Kraken|rfriends:"

function KF:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. tostring(msg))
end

function KF:Printf(fmt, ...)
    self:Print(fmt:format(...))
end

function KF:Debug(fmt, ...)
    if not (self.db and self.db.settings.debug) then return end
    local args = {}
    for i = 1, select("#", ...) do args[i] = tostring(select(i, ...)) end
    local ok, msg = pcall(string.format, fmt, unpack(args))
    self:Print("|cff8a8f98" .. (ok and msg or fmt) .. "|r")
end

--------------------------------------------------------------------------------
-- Events and internal messages
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local events, listeners, reported = {}, {}, {}
KF.missingEvents = {}

function KF:ReportError(err)
    err = tostring(clean(err) or "?")
    if reported[err] then return end
    reported[err] = true
    if self.db and self.db.settings.debug then self:Print("|cffff5555error:|r " .. err) end
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, err) end
end

local function dispatch(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then KF:ReportError(err) end
end

-- RegisterEvent on an event this client doesn't have raises, which would abort
-- the rest of the file, so every registration is protected.
function KF:On(event, fn)
    if not events[event] then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            table.insert(self.missingEvents, event)
            return false
        end
        events[event] = {}
    end
    table.insert(events[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = events[event]
    if not list then return end
    for i = 1, #list do dispatch(list[i], ...) end
end)

function KF:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function KF:Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do dispatch(list[i], ...) end
end

--------------------------------------------------------------------------------
-- Journeys and stats
--------------------------------------------------------------------------------

function KF.NewStats()
    return {
        kills = 0, kbMe = 0, kbPartner = 0, elite = 0, rare = 0, boss = 0,
        types = {}, lootMe = {}, lootPartner = {},
        goldMe = 0, goldDuo = 0,
        deathsMe = 0, deathsPartner = 0,
        quests = 0, runs = 0, time = 0,
        levelsMe = 0, levelsPartner = 0,
    }
end

local function fill(t, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            fill(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
    return t
end

-- A journey is you + one friend. Each pairing of characters ("Krakenhood &
-- Thalianne") is a chapter with its own counters and lists; the journey
-- total is the sum of its chapters.
local JOURNEY_TEMPLATE = {
    chars = { me = {}, partner = {} },
    total = KF.NewStats(),
    pairs = {}, firsts = {}, done = {},
}

local PAIR_TEMPLATE = {
    stats = KF.NewStats(),
    mobs = {}, rares = {}, bosses = {}, dungeons = {}, runs = {}, zones = {}, items = {}, log = {},
    records = { me = {}, partner = {} }, -- biggest hit and crit per player: { n = amount, s = spell, d = target, t = time, ch = character }
}

local function upgradeJourney(j)
    fill(j, JOURNEY_TEMPLATE)
    for _, pair in pairs(j.pairs) do fill(pair, PAIR_TEMPLATE) end
    return j
end

function KF.NewPair(me, meClass, partner, partnerClass)
    local now = time()
    return fill({ me = me, meClass = meClass, partner = partner, partnerClass = partnerClass, started = now, last = now }, PAIR_TEMPLATE)
end

function KF:NewJourney(id, partnerName, partnerTag)
    local now = time()
    local j = upgradeJourney({
        id = id, partnerName = partnerName, partnerTag = partnerTag,
        started = now, lastActive = now,
    })
    self.db.journeys[id] = j
    return j
end

local function bump(stats, field, amount, sub)
    if sub ~= nil then
        local t = stats[field]
        if type(t) ~= "table" then t = {}; stats[field] = t end
        t[sub] = (t[sub] or 0) + amount
    else
        stats[field] = (stats[field] or 0) + amount
    end
end

-- Adds to the journey total and to the current character pairing.
function KF:Add(field, amount, sub)
    local j = self.journey
    if not j then return end
    amount = amount or 1
    bump(j.total, field, amount, sub)
    local pair = self:CurrentPair()
    if pair then
        bump(pair.stats, field, amount, sub)
        pair.last = time()
    end
    j.lastActive = time()
end

-- Journal entries belong to the chapter they happened in.
function KF:Log(kind, text)
    local pair = self:CurrentPair()
    if not pair or not text then return end
    local log = pair.log
    log[#log + 1] = { t = time(), k = kind, x = text }
    while #log > LOG_CAP do table.remove(log, 1) end
    self:Fire("UPDATE")
end

-- True the first time something happens anywhere in the journey (first
-- visit to a zone, first kill of a rare, ...), across all chapters.
function KF:First(kind, key)
    local j = self.journey
    local id = kind .. ":" .. tostring(key)
    if not j or j.firsts[id] then return false end
    j.firsts[id] = time()
    return true
end

-- Records: the biggest hit and the biggest crit for each player, kept per
-- character pair. `who` is "me" or "partner".
local lastRecordToast = {}

function KF:SubmitHit(who, amount, crit, spell, target)
    local pair = self:CurrentPair()
    if not pair or type(amount) ~= "number" or amount <= 0 then return end
    local recs = pair.records
    recs[who] = recs[who] or {}
    local p = self.partner
    local char = who == "me" and self.me.name or (p and p.name) or "?"
    local changed

    for _, kind in ipairs(crit and { "hit", "crit" } or { "hit" }) do
        local old = recs[who][kind]
        if not old or amount > old.n then
            recs[who][kind] = { n = amount, s = spell, d = target, t = time(), ch = char }
            changed = true
            -- announce clear improvements of a crit record, at most once a minute per player
            if kind == "crit" and old and old.n >= 20 and amount >= old.n * 1.2 then
                local now = GetTime()
                if now - (lastRecordToast[who] or -60) >= 60 then
                    lastRecordToast[who] = now
                    local text = ("%s crit for %s%s"):format(who == "me" and "You" or char, KF.FormatNumber(amount), spell and (" with " .. spell) or "")
                    self:Log("record", text)
                    self:Toast("New crit record!", text, "kills")
                end
            end
        end
    end
    if changed then self:Fire("UPDATE") end
end

function KF:Toast(title, text, icon)
    if self.db.settings.toasts and self.ShowToast then
        self.ShowToast(title, text, icon)
    end
end

function KF:CheckMilestones()
    local j = self.journey
    if not j then return end
    for _, m in ipairs(self.Milestones) do
        local value = m.value and m.value(j.total) or j.total[m.id] or 0
        for _, step in ipairs(m.steps) do
            if value < step then break end
            local key = m.id .. ":" .. step
            if not j.done[key] then
                j.done[key] = true
                local text = m.label(step)
                self:Log("milestone", text)
                self:Toast("Milestone", text, m.icon)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- SavedVariables
--
-- The live game keeps KrakenfriendsDB (account-wide). The same table is also
-- mirrored into KrakenfriendsCharDB, and tools\Restore-Journey can feed a copy
-- back in as KrakenfriendsRestore: both exist because the Forever beta does
-- not read SavedVariables back. At load we take whichever snapshot is newest.
--------------------------------------------------------------------------------

local DEFAULTS = {
    settings = { debug = false, toasts = true, minimap = { angle = 205, hide = false }, window = {} },
    journeys = {},
    ignored = {},
}

function KF:LoadDB()
    local db, source
    local candidates = {
        { KrakenfriendsDB, "account" },
        { KrakenfriendsCharDB, "character" },
        { KrakenfriendsRestore, "restore" },
    }
    for _, c in ipairs(candidates) do
        local t = c[1]
        if type(t) == "table" and type(t.journeys) == "table" then
            if not db or (t.savedAt or 0) > (db.savedAt or 0) then db, source = t, c[2] end
        end
    end
    if not db then db, source = { created = time() }, "new" end

    fill(db, DEFAULTS)
    db.created = db.created or time()
    db.version = DB_VERSION
    for _, j in pairs(db.journeys) do upgradeJourney(j) end

    KrakenfriendsDB, KrakenfriendsCharDB, KrakenfriendsRestore = db, db, nil
    self.db, self.dbSource = db, source
end

--------------------------------------------------------------------------------
-- Demo journey: fills the window with sample data so the UI can be seen
-- without playing. Never tracked, removed again with /kf demo.
--------------------------------------------------------------------------------

local DEMO_ID = "demo:Demo"

function KF:ToggleDemo()
    local db = self.db
    if db.journeys[DEMO_ID] then
        db.journeys[DEMO_ID] = nil
        if self.UI.viewId == DEMO_ID then self.UI.viewId, self.UI.scope = nil, nil end
        self:RefreshJourney()
        self:Print("Demo journey removed.")
        return
    end

    local now, day = time(), 86400
    local j = self:NewJourney(DEMO_ID, "Thalia", "Thalia#1234")
    j.started = now - day * 11
    local me, alt, friend = self.me.key, "Krakenalt-Demo", "Thalianne-Demo"
    j.chars.me[me] = { class = self.me.class, level = 24 }
    j.chars.me[alt] = { class = "WARRIOR", level = 9 }
    j.chars.partner[friend] = { class = "PRIEST", level = 23 }
    j.lastPartnerChar = friend

    -- chapter 1: your main with Thalianne
    local main = KF.NewPair(me, self.me.class, friend, "PRIEST")
    main.started, main.last, main.lvMin, main.lvMax = j.started, now - 3600, 1, 24
    local s = main.stats
    s.kills, s.kbMe, s.kbPartner = 1873, 1004, 869
    s.elite, s.rare, s.boss = 212, 9, 14
    s.types = { humanoid = 802, beast = 541, undead = 203, elemental = 88, demon = 41, dragonkin = 12, mechanical = 64, giant = 9, critter = 23, unspecified = 6, player = 4 }
    s.lootMe = { [0] = 402, [1] = 610, [2] = 57, [3] = 9, [4] = 1 }
    s.lootPartner = { [0] = 388, [1] = 575, [2] = 49, [3] = 7 }
    s.goldMe, s.goldDuo = 1234567, 2398112
    s.deathsMe, s.deathsPartner = 7, 11
    s.quests, s.runs, s.time = 214, 12, 3600 * 41 + 1260
    s.levelsMe, s.levelsPartner = 18, 17
    main.mobs = {
        [116] = { n = "Defias Bandit", c = 84, ty = "humanoid", lv = 15 },
        [299] = { n = "Young Wolf", c = 21, ty = "beast", lv = 3 },
        [948] = { n = "Rotting Dead", c = 44, ty = "undead", lv = 22 },
        [40] = { n = "Kobold Miner", c = 39, ty = "humanoid", lv = 7 },
        [515] = { n = "Murloc Raider", c = 33, ty = "humanoid", lv = 11 },
    }
    main.toughest = { n = "Edwin VanCleef", lv = 21 }
    main.rares = { [522] = { n = "Mor'Ladim", c = 1, t = now - day * 3, lv = 35 }, [503] = { n = "Lord Malathrom", c = 1, t = now - day, lv = 31 } }
    main.bosses = { ["Edwin VanCleef"] = { c = 2, t = now - day * 4 }, ["Mutanus the Devourer"] = { c = 1, t = now - day * 2 } }
    main.dungeons = { [36] = { n = "The Deadmines", runs = 3, time = 7400, bosses = 17, last = now - day * 4 }, [43] = { n = "Wailing Caverns", runs = 2, time = 6800, bosses = 10, last = now - day * 2 } }
    main.runs = { { n = "Wailing Caverns", start = now - day * 2, dur = 3500, kills = 96, bosses = 6, deaths = 1 }, { n = "The Deadmines", start = now - day * 4, dur = 2380, kills = 84, bosses = 6, deaths = 0 } }
    main.zones = { ["Elwynn Forest"] = j.started, ["Westfall"] = now - day * 8, ["Duskwood"] = now - day * 3 }
    main.records = {
        me = { hit = { n = 1432, s = "Fireball", d = "Edwin VanCleef", t = now - day * 4, ch = self.me.name },
               crit = { n = 2871, s = "Fireball", d = "Edwin VanCleef", t = now - day * 4, ch = self.me.name } },
        partner = { hit = { n = 986, s = "Smite", d = "Mor'Ladim", t = now - day * 3, ch = "Thalianne" },
                    crit = { n = 1934, s = "Smite", d = "Mor'Ladim", t = now - day * 3, ch = "Thalianne" } },
    }
    main.items = {
        [2244] = { n = "Krol Blade", q = 4, c = 1, me = 1, t = now - day * 2, l = now - day * 2 },
        [5191] = { n = "Cruel Barb", q = 3, c = 1, pa = 1, t = now - day * 4, l = now - day * 4 },
        [6505] = { n = "Crescent Staff", q = 3, c = 1, me = 1, t = now - day * 2, l = now - day * 2 },
        [15210] = { n = "Raider Shortsword", q = 2, c = 2, me = 1, pa = 1, t = now - day * 9, l = now - day * 6 },
    }
    main.log = {
        { t = j.started, k = "start", x = "Your journey with Thalia began" },
        { t = now - day * 8, k = "zone", x = "Discovered Westfall together" },
        { t = now - day * 4, k = "boss", x = "Defeated Edwin VanCleef for the first time" },
        { t = now - day * 3, k = "rare", x = "Slew Mor'Ladim (rare)" },
        { t = now - day * 2, k = "loot", x = self.me.name .. " found |cffa335eeKrol Blade|r" },
        { t = now - 3600, k = "milestone", x = "1,000 kills together" },
    }

    -- chapter 2: a fresh alt with the same friend
    local second = KF.NewPair(alt, "WARRIOR", friend, "PRIEST")
    second.started, second.last, second.lvMin, second.lvMax = now - day * 2, now - day, 1, 9
    local a = second.stats
    a.kills, a.kbMe, a.kbPartner = 214, 131, 83
    a.types = { beast = 120, humanoid = 88, critter = 6 }
    a.lootMe, a.lootPartner = { [0] = 40, [1] = 61, [2] = 5 }, { [0] = 37, [1] = 52, [2] = 3 }
    a.goldMe, a.goldDuo = 18400, 35100
    a.deathsMe, a.quests, a.time, a.levelsMe = 1, 31, 3600 * 3 + 900, 8
    second.mobs = { [299] = { n = "Young Wolf", c = 40, ty = "beast", lv = 3 }, [80] = { n = "Kobold Laborer", c = 31, ty = "humanoid", lv = 4 } }
    second.zones = { ["Elwynn Forest"] = second.started }
    second.records = {
        me = { hit = { n = 61, s = "Heroic Strike", d = "Young Wolf", t = now - day, ch = "Krakenalt" },
               crit = { n = 122, s = "Heroic Strike", d = "Kobold Laborer", t = now - day, ch = "Krakenalt" } },
        partner = { hit = { n = 48, s = "Smite", d = "Young Wolf", t = now - day, ch = "Thalianne" },
                    crit = { n = 96, s = "Smite", d = "Defias Thug", t = now - day, ch = "Thalianne" } },
    }
    second.items = { [15210] = { n = "Raider Shortsword", q = 2, c = 1, me = 1, t = now - day, l = now - day } }
    second.log = {
        { t = second.started + 1800, k = "level", x = "Krakenalt reached level 5" },
        { t = now - day, k = "level", x = "Krakenalt reached level 9" },
    }

    j.pairs[me .. " & " .. friend] = main
    j.pairs[alt .. " & " .. friend] = second
    for _, pair in pairs(j.pairs) do
        for field, v in pairs(pair.stats) do
            if type(v) == "table" then
                for k, n in pairs(v) do j.total[field][k] = (j.total[field][k] or 0) + n end
            else
                j.total[field] = j.total[field] + v
            end
        end
    end
    self.UI.viewId, self.UI.scope = DEMO_ID, nil
    self:RefreshJourney()
    self:Print("Demo journey created. Type |cff4fd1c5/kf demo|r again to remove it.")
    self.UI:Show()
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

if StaticPopupDialogs then
    StaticPopupDialogs.KRAKENFRIENDS_RESET = {
        text = "Reset your journey with %s?\n\nAll counters and history for this journey are erased. This cannot be undone.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, id) KF:ResetJourney(id) end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
    }
end

function KF:ResetJourney(id)
    local old = id and self.db.journeys[id]
    if not old then return end
    local j = self:NewJourney(id, old.partnerName, old.partnerTag)
    j.chars = old.chars
    self:RefreshJourney()
    self:Print("Journey reset. A fresh start!")
end

local HELP = {
    "|cff4fd1c5/kf|r: open or close the journey window",
    "|cff4fd1c5/kf partner [name]|r: set your journey partner (target, name, or your only group member)",
    "|cff4fd1c5/kf status|r: show what is being tracked right now",
    "|cff4fd1c5/kf demo|r: add or remove a demo journey to preview the window",
    "|cff4fd1c5/kf minimap|r: show or hide the minimap button",
    "|cff4fd1c5/kf toasts|r: turn milestone pop-ups on or off",
    "|cff4fd1c5/kf reset|r: reset the journey shown in the window",
    "|cff4fd1c5/kf debug|r: print tracking details to chat",
}

function KF:Slash(input)
    local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local settings = self.db.settings
    if cmd == "" or cmd == "show" then
        self.UI:Toggle()
    elseif cmd == "partner" then
        self:SetPartnerCommand(rest)
    elseif cmd == "status" then
        self:PrintStatus()
    elseif cmd == "demo" then
        self:ToggleDemo()
    elseif cmd == "minimap" then
        settings.minimap.hide = not settings.minimap.hide
        self:Fire("SETTINGS")
        self:Print("Minimap button " .. (settings.minimap.hide and "hidden." or "shown."))
    elseif cmd == "toasts" then
        settings.toasts = not settings.toasts
        self:Print("Milestone pop-ups " .. (settings.toasts and "on." or "off."))
    elseif cmd == "debug" then
        settings.debug = not settings.debug
        self:Print("Debug output " .. (settings.debug and "on." or "off."))
    elseif cmd == "reset" then
        local j = self.UI:ViewedJourney()
        if j then StaticPopup_Show("KRAKENFRIENDS_RESET", j.partnerName or "your partner", nil, j.id) end
    else
        self:Print("commands:")
        for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
    end
end

SLASH_KRAKENFRIENDS1 = "/kf"
SLASH_KRAKENFRIENDS2 = "/krakenfriends"
SlashCmdList.KRAKENFRIENDS = function(input) KF:Slash(input) end

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------

KF:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    KF:LoadDB()
end)

KF:On("PLAYER_LOGIN", function()
    KF:InitPlayer()
    KF.ready = true
    KF:Fire("LOGIN")
    if KF.dbSource == "restore" or KF.dbSource == "character" then
        KF:Printf("restored your journeys from the %s backup (saved %s).", KF.dbSource,
            date("%d %b %H:%M", KF.db.savedAt or time()))
    end
end)

KF:On("PLAYER_LOGOUT", function()
    if not KF.db then return end
    KF:Fire("LOGOUT")
    KF.db.savedAt = time()
    KrakenfriendsDB, KrakenfriendsCharDB = KF.db, KF.db
end)
