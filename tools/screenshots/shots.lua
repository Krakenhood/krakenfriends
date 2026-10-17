-- Plays practice mode headless and records what the addon would show at a few
-- moments, as JSON for shots.js to draw. Runs on tests/mock.lua.

local function json(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local out = {}
            for i, x in ipairs(v) do out[i] = json(x) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = json(tostring(k)) .. ":" .. json(x) end
        return "{" .. table.concat(out, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"'
    elseif t == "number" then
        return tostring(v)
    elseif t == "boolean" then
        return tostring(v)
    end
    return "null"
end

-- strips the game's colour codes, keeping which parts were coloured
local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local NS = {}
for _, name in ipairs(TOC) do assert(load(FILES[name], "@" .. name))("Krakenrage", NS) end
local KR = NS
UNITS.player = { guid = "Player-1-0000AAAA", name = "Krakenhood", realm = "Forever", class = "MAGE", level = 30, player = true }
FireEvent("ADDON_LOADED", "Krakenrage")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD", true, false)
local S, C, H = KR.Spells, KR.Coach, KR.Hud

-- the bar as it is right now
local function hud()
    local rage, max = S:Rage()
    local st = S:Stance()
    local out = { rage = rage, max = max, stance = st and st.key, keep = S:Keep(), ticks = {}, procs = {} }
    for _, t in ipairs(H.ticks) do
        local g = { cost = t.cost, icons = {} }
        for _, ic in ipairs(t.icons) do
            g.icons[#g.icons + 1] = {
                key = ic.ability.key, short = ic.ability.short,
                ready = H:Ready(ic.ability, ic.known, rage, st and st.key) and true or false,
                queued = ic.ability.swing and S:Queued(ic.ability.key) or false,
            }
        end
        out.ticks[#out.ticks + 1] = g
    end
    local done = KR.Swing:Progress()
    if done then
        out.swing = done
        out.swingColor = "gold"
        if S:Queued("hs") then out.swingColor = (rage and H:MainShort(rage - S:Known("hs").cost)) and "bad" or "warn" end
    end
    if C.execute then out.procs[#out.procs + 1] = { kind = "ex", label = "Execute" } end
    local left = C:Window("op")
    if left then out.procs[#out.procs + 1] = { kind = "op", label = "Overpower", left = left } end
    out.swap = (rage and rage > out.keep) and (rage - out.keep) or nil
    out.target = C.fight and select(1, S:Target())
    out.hp = S:TargetHealth()
    return out
end

local SHOTS = {}
local function Run(sec)
    for _ = 1, math.floor(sec * 10 + 0.5) do
        Advance(0.1)
        TickAll()
        local onUpdate = KR.Hud.frame and KR.Hud.frame:GetScript("OnUpdate")
        if onUpdate then onUpdate(KR.Hud.frame, 0.1) end
    end
end

-- twelve sample fights first, so the history has trends
SlashCmdList.KRAKENRAGE("practice")
SlashCmdList.KRAKENRAGE("demo")

local want = {
    -- a dodge, Overpower lit, rage enough for Mortal Strike's tick or Heroic Strike queued
    op = function(h) return #h.procs == 1 and h.procs[1].kind == "op" and h.procs[1].left < 4 and (h.rage or 0) >= 20 and h.stance == "battle" end,
    -- the Execute phase with rage for an Execute
    ex = function(h) for _, p in ipairs(h.procs) do if p.kind == "ex" then return (h.rage or 0) >= 15 and h.swingColor == "gold" end end end,
    -- full rage in the sloppy fight
    full = function(h) return (h.rage or 0) >= 100 end,
    -- Heroic Strike queued
    hs = function(h) return h.swingColor and h.swingColor ~= "gold" and #h.procs == 0 end,
}
local toastShot
for _ = 1, 950 do
    Run(0.1)
    local h = hud()
    for name, fn in pairs(want) do
        if not SHOTS[name] and h.target and fn(h) then SHOTS[name] = h end
    end
    if not toastShot and KrakenrageToast and KrakenrageToast:IsShown() then
        toastShot = { grade = KrakenrageToast.grade:GetText(), title = KrakenrageToast.title:GetText(), text = KrakenrageToast.text:GetText() }
    end
end
SlashCmdList.KRAKENRAGE("practice")

-- the coach: the sloppy practice fight, the history, the bar's settings
local fights = KR.char.fights
local sloppy
for i = #fights, 1, -1 do if fights[i].practice and fights[i].op.missed > 0 then sloppy = fights[i]; break end end
local function fightData(r)
    local tips = {}
    for _, t in ipairs(C:Tips(r)) do tips[#tips + 1] = { level = t.level, text = plain(t.text) } end
    local parts = {}
    for _, p in ipairs(C:Parts(r)) do parts[#parts + 1] = { label = p.label, value = p.value } end
    return {
        target = r.target, cls = r.cls, dur = KR.FormatClock(r.dur), ago = KR.FormatAgo(r.t), practice = r.practice or false,
        grade = C.Grade(r.score), score = r.score, parts = parts, tips = tips,
        spent = plain(KR.UI.SpentLine(r)), stances = plain(KR.UI.StanceLine(r)),
    }
end
local history = {}
for i = #fights, math.max(1, #fights - 11), -1 do
    local r = fights[i]
    history[#history + 1] = { grade = C.Grade(r.score), score = r.score, target = r.target, cls = r.cls, dur = KR.FormatClock(r.dur), ago = KR.FormatAgo(r.t), practice = r.practice or false }
end
local trends = {}
for _, tr in ipairs(C:Trends()) do trends[#trends + 1] = { label = tr.label, now = tr.now, before = tr.before, better = tr.better, fmt = tr.fmt } end

-- the bar page lists every ability the pretend warrior knows; practice is off now, so start it again for that
SlashCmdList.KRAKENRAGE("practice")
local abilities = {}
for _, a in ipairs(KR.Abilities) do
    local k = S:Known(a.key)
    if k and k.cost > 0 then abilities[#abilities + 1] = { key = a.key, short = a.short, name = k.name, cost = k.cost, on = H:TickEnabled(a.key) } end
end
local settings = KR.db.settings.hud
SlashCmdList.KRAKENRAGE("practice")

SHOT_JSON = json({
    hud = SHOTS, toast = toastShot, fight = sloppy and fightData(sloppy), history = history, trends = trends, total = #fights,
    abilities = abilities, settings = { locked = settings.locked, swing = settings.swing, procs = settings.procs, stance = settings.stance, fade = settings.fade, toasts = KR.db.settings.toasts, minimap = not KR.db.settings.minimap.hide },
    errors = #ERRORS,
})
