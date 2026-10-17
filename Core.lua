local ADDON, KR = ...
Krakenrage = KR -- global handle, handy for /dump Krakenrage.fight

local floor = math.floor

KR.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "0.1.0"

--------------------------------------------------------------------------------
-- Secret-value safety
--
-- Forever runs the Midnight "secret values" system: some reads come back as
-- opaque values that throw on arithmetic, comparison and even ==. The only
-- safe test is issecretvalue(), so every value we read from the game goes
-- through clean() before we look at it, and API calls go through call().
-- A secret read is treated as "don't know": the feature that needed it stays quiet.
--------------------------------------------------------------------------------

local issecretvalue = issecretvalue

local function clean(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
KR.clean = clean

function KR.call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then return nil end
    return clean(a), clean(b), clean(c), clean(d), clean(e), clean(f)
end

function KR.Now()
    local t = GetServerTime and GetServerTime()
    if type(t) ~= "number" then t = time() end
    return floor(t)
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

-- 0:42, 3:05, 1:02:10
function KR.FormatClock(sec)
    sec = floor((sec or 0) + 0.5)
    local h, m, s = floor(sec / 3600), floor(sec / 60) % 60, sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

-- "just now", "5 min ago", "3 h ago", "2 days ago"
function KR.FormatAgo(t)
    local d = KR.Now() - (t or 0)
    if d < 60 then return "just now" end
    if d < 3600 then return ("%d min ago"):format(floor(d / 60)) end
    if d < 86400 then return ("%d h ago"):format(floor(d / 3600)) end
    local days = floor(d / 86400)
    return days == 1 and "yesterday" or ("%d days ago"):format(days)
end

function KR.Percent(part, whole)
    if not whole or whole <= 0 then return nil end
    return floor(100 * (part or 0) / whole + 0.5)
end

function KR.Colorize(text, c)
    return ("|cff%02x%02x%02x%s|r"):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5), text)
end

--------------------------------------------------------------------------------
-- Chat output
--------------------------------------------------------------------------------

local PREFIX = "|cff4fd1c5Kraken|rrage:"

function KR:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. tostring(msg))
end

function KR:Printf(fmt, ...)
    self:Print(fmt:format(...))
end

function KR:Debug(fmt, ...)
    if not (self.db and self.db.settings.debug) then return end
    local args = {}
    for i = 1, select("#", ...) do args[i] = tostring(clean(select(i, ...))) end
    local ok, msg = pcall(string.format, fmt, unpack(args))
    self:Print("|cff8a8f98" .. (ok and msg or fmt) .. "|r")
end

--------------------------------------------------------------------------------
-- Events and internal messages
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local events, listeners, reported = {}, {}, {}
KR.missingEvents = {}

function KR:ReportError(err)
    err = tostring(clean(err) or "?")
    if reported[err] then return end
    reported[err] = true
    if self.db and self.db.settings.debug then self:Print("|cffff5555error:|r " .. err) end
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, err) end
end

local function dispatch(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then KR:ReportError(err) end
end
KR.dispatch = dispatch

-- RegisterEvent on an event this client doesn't have raises, which would abort
-- the rest of the file, so every registration is protected.
function KR:On(event, fn)
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

-- Like On, but the handler only runs once the addon is set up for a warrior.
function KR:OnReady(event, fn)
    return self:On(event, function(...)
        if KR.active then fn(...) end
    end)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = events[event]
    if not list then return end
    for i = 1, #list do dispatch(list[i], ...) end
end)

function KR:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function KR:Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do dispatch(list[i], ...) end
end

--------------------------------------------------------------------------------
-- SavedVariables
--
-- KrakenrageDB (account-wide) holds the settings: where the bar sits, what it shows.
-- KrakenrageCharDB (per character) holds that warrior's fights, which ticks the bar
-- shows (specs differ) and the rage the character keeps on a stance switch.
--------------------------------------------------------------------------------

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
KR.Fill = fill

local DEFAULTS = {
    settings = {
        debug = false,
        toasts = true,     -- a short note after each fight worth coaching
        minimap = { angle = 220, hide = false },
        window = {},
        hud = {
            locked = true, scale = 1,
            fade = true,   -- dim the bar out of combat while there's no rage
            swing = true,  -- the experimental swing timer under the bar
            procs = true,  -- Overpower, Revenge and Execute alerts
            stance = true, -- the stance icon and the "-N rage on a switch" hint
        },
    },
}

local CHAR_DEFAULTS = {
    fights = {}, -- newest last, capped at FIGHT_CAP
    ticks = {},  -- ability key -> true/false, overrides of the default ticks
    keep = nil,  -- rage kept on a stance switch (Tactical Mastery), learned from switches
}

KR.FIGHT_CAP = 200

function KR:LoadDB()
    local db = type(KrakenrageDB) == "table" and KrakenrageDB or { created = KR.Now() }
    fill(db, DEFAULTS)
    KrakenrageDB = db
    local char = type(KrakenrageCharDB) == "table" and KrakenrageCharDB or { created = KR.Now() }
    fill(char, CHAR_DEFAULTS)
    KrakenrageCharDB = char
    self.db, self.char = db, char
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local function isWarrior()
    local _, class = KR.call(UnitClass, "player")
    return class == "WARRIOR"
end

KR:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    KR:LoadDB()
end)

KR:On("PLAYER_LOGIN", function()
    if not KR.db then KR:LoadDB() end
    if not isWarrior() then
        -- Nothing to do for other classes; stay silent apart from the slash command.
        KR.notWarrior = true
        return
    end
    KR.active = true
    KR:Fire("SETUP")
end)

KR:On("PLAYER_ENTERING_WORLD", function()
    if KR.active then KR:Fire("REFRESH") end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    { "/kr", "open or close the coach window" },
    { "/kr lock", "unlock the rage bar to move it, lock it again" },
    { "/kr scale 1.2", "make the bar bigger or smaller (0.5 to 2)" },
    { "/kr reset", "put the bar back in the middle of the screen" },
    { "/kr swing", "show or hide the swing timer (experimental)" },
    { "/kr procs", "turn the Overpower, Revenge and Execute alerts on or off" },
    { "/kr fade", "dim the bar out of combat, or always show it" },
    { "/kr toasts", "turn the note after each fight on or off" },
    { "/kr minimap", "show or hide the minimap button" },
    { "/kr demo", "add or remove sample fights, to preview the coach" },
    { "/kr clear", "forget this character's fights" },
    { "/kr debug", "print what the coach sees to chat" },
}

local function toggle(t, key, label)
    t[key] = not t[key]
    KR:Printf("%s %s.", label, t[key] and "on" or "off")
    KR:Fire("SETTINGS")
end

local commands = {
    lock = function()
        local hud = KR.db.settings.hud
        hud.locked = not hud.locked
        KR:Print(hud.locked and "Rage bar locked." or "Rage bar unlocked: drag it where you want it, then /kr lock.")
        KR:Fire("SETTINGS")
    end,
    scale = function(arg)
        local n = tonumber(arg)
        if not n then return KR:Printf("Bar scale is %.2f. Use /kr scale 0.5 to 2.", KR.db.settings.hud.scale) end
        KR.db.settings.hud.scale = math.max(0.5, math.min(2, n))
        KR:Printf("Bar scale %.2f.", KR.db.settings.hud.scale)
        KR:Fire("SETTINGS")
    end,
    reset = function()
        local hud = KR.db.settings.hud
        hud.point, hud.relPoint, hud.x, hud.y = nil, nil, nil, nil
        KR:Print("Rage bar back in the middle.")
        KR:Fire("SETTINGS")
    end,
    swing = function() toggle(KR.db.settings.hud, "swing", "Swing timer") end,
    procs = function() toggle(KR.db.settings.hud, "procs", "Proc alerts") end,
    fade = function() toggle(KR.db.settings.hud, "fade", "Dimming out of combat") end,
    stance = function() toggle(KR.db.settings.hud, "stance", "Stance icon") end,
    toasts = function() toggle(KR.db.settings, "toasts", "Notes after fights") end,
    minimap = function()
        local m = KR.db.settings.minimap
        m.hide = not m.hide
        KR:Fire("SETTINGS")
    end,
    debug = function() toggle(KR.db.settings, "debug", "Debug output") end,
    demo = function() KR.Coach:ToggleDemo() end,
    clear = function()
        wipe(KR.char.fights)
        KR:Print("Fights forgotten.")
        KR:Fire("FIGHTS")
    end,
    help = function()
        KR:Print("commands:")
        for _, h in ipairs(HELP) do KR:Print(("  |cffffd100%s|r  %s"):format(h[1], h[2])) end
    end,
}

SLASH_KRAKENRAGE1 = "/kr"
SLASH_KRAKENRAGE2 = "/krakenrage"
SlashCmdList.KRAKENRAGE = function(msg)
    msg = strtrim(tostring(msg or "")):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if not KR.active then
        KR:Print(KR.notWarrior and "Krakenrage is made for warriors; it stays asleep on this character." or "not ready yet.")
        return
    end
    if cmd == "" then
        KR.UI:Toggle()
    elseif commands[cmd] then
        commands[cmd](arg)
    else
        commands.help()
    end
end

function Krakenrage_OnAddonCompartmentClick()
    SlashCmdList.KRAKENRAGE("")
end
