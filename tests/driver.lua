-- Loads the addon in TOC order and plays through fights.
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL: " .. label) end
end
local function section(t) print("\n== " .. t) end

local function loadAddon()
    local NS = {}
    for _, name in ipairs(TOC) do
        local chunk, err = load(FILES[name], "@" .. name)
        if not chunk then error(err) end
        chunk("Krakenrage", NS)
    end
    return NS
end

-- plays `sec` seconds in steps of 0.1, with the coach's ticker and the bar's update running
local function Run(sec, KR)
    local steps = math.floor(sec * 10 + 0.5)
    for _ = 1, steps do
        Advance(0.1)
        TickAll()
        if KR and KR.Hud.frame then
            local onUpdate = KR.Hud.frame:GetScript("OnUpdate")
            if onUpdate then onUpdate(KR.Hud.frame, 0.1) end
        end
    end
end

local function SetRage(n)
    RAGE = n
    FireEvent("UNIT_POWER_UPDATE", "player", "RAGE")
end

local function Cast(id)
    FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
end

--------------------------------------------------------------------------------
section("not a warrior: stays asleep")
UNITS.player = { guid = "Player-1-0000AAAA", name = "Krakenmage", realm = "Forever", class = "MAGE", level = 20, player = true }
local MAGE = loadAddon()
FireEvent("ADDON_LOADED", "Krakenrage")
FireEvent("PLAYER_LOGIN")
check(MAGE.active ~= true and MAGE.notWarrior, "inactive for a mage")
check(MAGE.Hud.frame == nil, "no bar for a mage")
SlashCmdList.KRAKENRAGE("")
check(CHAT[#CHAT]:find("made for warriors") ~= nil, "slash command explains")

section("practice mode on a mage")
SlashCmdList.KRAKENRAGE("practice")
check(MAGE.practice and MAGE.active, "practice wakes the addon")
check(MAGE.Hud.frame and MAGE.Hud.frame:IsShown(), "the bar is there")
local pc = {}
for _, t in ipairs(MAGE.Hud.ticks) do pc[#pc + 1] = t.cost end
check(table.concat(pc, ",") == "5,12,15,30", "the pretend warrior's ticks: " .. table.concat(pc, ","))
local sawOP, sawEx, sawCap, sawSwing, sawToast = false, false, false, false, false
for i = 1, 950 do -- two fights and their breaks
    Run(0.1, MAGE)
    if TRACE and i % 10 == 0 then
        local f = MAGE.Coach.fight
        print(("  t=%3d rage=%3s stance=%s fight=%s op=%s ex=%s"):format(i / 10, tostring(MAGE.Spells:Rage()), tostring(MAGE.Spells:StanceKey()), tostring(f ~= nil), tostring(MAGE.Coach.windows.op ~= nil), tostring(MAGE.Coach.execute)))
    end
    if MAGE.Coach.windows.op then sawOP = true end
    if MAGE.Coach.execute then sawEx = true end
    if MAGE.Spells:Rage() == 100 then sawCap = true end
    if MAGE.Swing:Progress() then sawSwing = true end
    if KrakenrageToast and KrakenrageToast:IsShown() then sawToast = true end
end
check(sawOP and sawEx and sawCap and sawSwing, ("Overpower %s, Execute %s, full rage %s, swings %s"):format(tostring(sawOP), tostring(sawEx), tostring(sawCap), tostring(sawSwing)))
local pf = MAGE.char.fights
check(#pf == 2 and pf[1].practice and pf[2].practice, "two practice fights graded: " .. #pf)
if #pf == 2 then
    local sloppy, clean = pf[1], pf[2]
    print(("  sloppy: %s %s, clean: %s %s"):format(MAGE.Coach.Grade(sloppy.score), tostring(sloppy.score), MAGE.Coach.Grade(clean.score), tostring(clean.score)))
    print(("  sloppy capped %.1f loss %d exec.hs %d | clean sunder %s shout %s exec %d"):format(sloppy.capped, sloppy.stanceLoss, sloppy.exec.hs, tostring(clean.sunder and clean.sunder.max), tostring(clean.shout and clean.shout.up), clean.exec.casts))
    print(("  op sloppy win %d used %d missed %d starved %d other %d | clean win %d used %d missed %d starved %d"):format(sloppy.op.win, sloppy.op.used, sloppy.op.missed, sloppy.op.starved, sloppy.op.other, clean.op.win, clean.op.used, clean.op.missed, clean.op.starved))
    check(clean.score > sloppy.score, "the clean fight grades better")
    check(sloppy.op.missed >= 1 and clean.op.missed == 0 and clean.op.used >= 1, "Overpower missed only in the sloppy fight")
    check(sloppy.capped >= 3 and sloppy.stanceLoss > 0 and sloppy.exec.hs == 1, "the sloppy fight's mistakes")
    check(clean.sunder.max == 5 and clean.shout and clean.shout.up > 25, "the clean fight's Sunders and Battle Shout")
    check(clean.exec.casts >= 2, "Executes in the clean fight")
    for _, t in ipairs(MAGE.Coach:Tips(sloppy)) do print("    " .. t.level .. ": " .. t.text) end
end
check(sawToast, "the note after a practice fight")
FireEvent("PLAYER_REGEN_DISABLED") -- a real fight
check(not MAGE.practice and not MAGE.active, "a real fight ends practice")
check(not MAGE.Hud.frame:IsShown(), "the bar goes away again")
FireEvent("PLAYER_REGEN_ENABLED")
check(#MAGE.char.fights == 2, "nothing recorded from the real fight")
KrakenrageToast:Hide()

--------------------------------------------------------------------------------
section("warrior login")
KrakenrageDB, KrakenrageCharDB = nil, nil
UNITS.player = { guid = "Player-1-0000BBBB", name = "Krakenhood", realm = "Forever", class = "WARRIOR", level = 30, player = true }
-- what this warrior knows: Heroic Strike talented down to 12 rage
KNOWN = { [78] = 12, [845] = 20, [5308] = 15, [12294] = 30, [7386] = 15, [7384] = 5, [6572] = 5, [6673] = 10, [772] = 10, [2687] = 0, [100] = 0 }
RAGE, STANCE = 0, 1
local KR = loadAddon()
FireEvent("ADDON_LOADED", "Krakenrage")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD", true, false)
local S, C, H = KR.Spells, KR.Coach, KR.Hud
check(KR.active, "active for a warrior")
check(#KR.missingEvents == 0, "all events registered: " .. table.concat(KR.missingEvents, ","))
check(S:Known("hs") and S:Known("hs").cost == 12, "Heroic Strike at its talented cost")
check(S:Known("bt") == nil and S:Known("ww") == nil, "unknown abilities left out")
check(S:KeyOf(7384) == "overpower", "casts recognised by name")
check(S:StanceKey() == "battle", "stance read")
check(H.frame ~= nil, "bar built")
local costs = {}
for _, t in ipairs(H.ticks) do costs[#costs + 1] = t.cost end
check(table.concat(costs, ",") == "5,12,15,30", "one tick per cost: " .. table.concat(costs, ","))
check(#H.ticks[1].icons == 2 and #H.ticks[3].icons == 2, "Overpower+Revenge and Execute+Sunder share a tick")

section("ticks light up with the rage you have")
SetRage(20)
local hs, ms, op = KR.AbilityByKey.hs, KR.AbilityByKey.ms, KR.AbilityByKey.overpower
check(H:Ready(hs, S:Known("hs"), 20, "battle") == true, "Heroic Strike affordable at 20")
check(H:Ready(ms, S:Known("ms"), 20, "battle") == false, "Mortal Strike not at 20")
COOLDOWN[12294] = { GT - 1, 6 }
check(H:Ready(ms, S:Known("ms"), 40, "battle") == false, "Mortal Strike on cooldown stays dark")
COOLDOWN[12294] = nil
check(H:Ready(op, S:Known("overpower"), 20, "battle") == false, "Overpower dark without a dodge")
H:Update()
check(KR.Hud.rageText:GetText() == "20", "rage shown on the bar")
H:SetTickEnabled("rend", true)
check(#H.ticks == 5, "Rend's tick added")
H:SetTickEnabled("rend", false)
check(#H.ticks == 4 and KR.char.ticks.rend == nil, "back to the default, nothing saved")

--------------------------------------------------------------------------------
section("a fight")
local MOB = "Creature-0-1-0-1-116-00000001"
UNITS.target = { guid = MOB, name = "Defias Pillager", hostile = true, level = 31, cls = "elite", hp = 100 }
AURAS.player.HELPFUL = { { name = "Battle Shout" } }
FireEvent("PLAYER_TARGET_CHANGED")
FireEvent("PLAYER_REGEN_DISABLED")
check(C.fight ~= nil, "fight started")
FireEvent("PLAYER_ENTER_COMBAT")
check(KR.Swing.attacking, "auto-attack on")
Run(1, KR)

-- Overpower: the target dodges, you use it
FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
check(C.windows.op ~= nil, "a dodge opens the Overpower chance")
Run(0.5, KR)
check(H:Ready(op, S:Known("overpower"), 20, "battle") == true, "Overpower lights up")
Cast(7384)
check(C.windows.op == nil and C.fight.op.used == 1, "Overpower used")

-- and once you let it go by
Run(1.5, KR)
FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
Run(5.2, KR)
check(C.windows.op == nil and C.fight.op.missed == 1, "an unused chance is missed")

-- a dodge with too little rage is "starved", not missed
SetRage(2)
FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
Run(5.2, KR)
check(C.fight.op.starved == 1 and C.fight.op.missed == 1, "too little rage: starved")

-- swing timer: a rage gain that isn't from a hit taken is your swing
local seen = KR.Swing.seen
SetRage(14)
check(KR.Swing.seen == seen + 1, "rage from a hit counts as a swing")
FireEvent("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
Run(2, KR)
FireEvent("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
SetRage(20)
check(KR.Swing.seen == seen + 1, "rage from being hit isn't a swing")
check(KR.Swing:Progress() ~= nil, "swing progress known")

-- Heroic Strike that leaves too little for Mortal Strike
SetRage(35)
Run(2.1, KR)
QUEUED[78] = true
H:Update()
check(KR.Hud.swing:IsShown(), "swing bar shown")
RAGE = 23
Cast(78)
QUEUED[78] = nil
Run(0.1, KR)
check(C.fight.hs == 1 and C.fight.starved == 1, "Heroic Strike left Mortal Strike short")

-- full rage for 3 seconds
SetRage(100)
Run(3.5, KR)
check(C.fight.capped >= 2.9, "time at full rage counted: " .. C.fight.capped)

-- stance switch to Defensive with Tactical Mastery keeping 10
SetRage(40)
STANCE = 2
FireEvent("UPDATE_SHAPESHIFT_FORM")
SetRage(10)
check(C.fight.stanceLoss == 30 and C.fight.swaps == 1, "switch cost 30 rage")
check(KR.char.keep == 10 and S:Keep() == 10, "learned the rage you keep")
H:Update()
check(not KR.Hud.swapText:IsShown(), "no switch cost shown at the rage you keep")
SetRage(30)
H:Update()
check(KR.Hud.swapText:IsShown() and KR.Hud.swapText:GetText() == "-20 on switch", "switch cost shown: " .. tostring(KR.Hud.swapText:GetText()))

-- Revenge after a parry
FireEvent("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
check(C.windows.rv ~= nil, "a parry opens Revenge")
Cast(6572)
check(C.fight.rv.used == 1, "Revenge used")

-- back to Battle Stance, Sunder Armor to five
STANCE = 1
FireEvent("UPDATE_SHAPESHIFT_FORM")
for i = 1, 5 do
    Cast(7386)
    AURAS.target.HARMFUL = { { name = "Sunder Armor", count = i } }
    Run(1.5, KR)
end
check(C.fight.sunder.max == 5 and C.fight.sunder.to5 ~= nil, "five Sunders, timed")

-- Execute phase, with one Heroic Strike in it
SetRage(30)
UNITS.target.hp = 15
Run(0.3, KR)
check(C.execute == true, "Execute phase seen")
check(KR.Hud.ticks ~= nil, "ticks still there")
Cast(5308)
Cast(78)
Run(3, KR)
check(C.fight.exec.casts == 1 and C.fight.exec.hs == 1 and C.fight.exec.time >= 3, "Execute phase counted")
AURAS.player.HELPFUL = {}
Run(2, KR)

-- the fight ends
UNITS.target.dead = true
FireEvent("PLAYER_LEAVE_COMBAT")
FireEvent("PLAYER_REGEN_ENABLED")
check(C.fight == nil, "fight over")
local r = KR.char.fights[#KR.char.fights]
check(r and r.target == "Defias Pillager" and r.cls == "elite", "fight kept with its foe")
check(r.dur >= 30, "duration " .. tostring(r and r.dur))
check(r.shout and r.shout.up < r.dur and r.shout.up > 0, "Battle Shout uptime")
check(r.score and r.score > 0 and r.score < 100, "graded: " .. tostring(r and r.score))
check(r.spent.hs == 24 and r.spent.ms == nil, "rage spent per ability")
local tips = C:Tips(r)
local text = {}
for _, t in ipairs(tips) do text[#text + 1] = t.level .. ": " .. t.text end
print("  tips:\n    " .. table.concat(text, "\n    "))
check(#tips >= 4, "several tips")
check(tips[1].level == "bad", "worst tips first")
local joined = table.concat(text, "\n")
check(joined:find("Overpower chance went by") ~= nil, "tip: missed Overpower")
check(joined:find("rage sat full") ~= nil, "tip: rage wasted")
check(joined:find("Stance switches cost you 30") ~= nil, "tip: stance switch")
check(joined:find("Heroic Strike during the Execute") ~= nil, "tip: Heroic Strike in Execute")
check(joined:find("Five Sunder Armors") ~= nil, "tip: Sunder")
check(KrakenrageToast and KrakenrageToast:IsShown(), "note after the fight shown")
check(KrakenrageToast.grade:GetText() == C.Grade(r.score), "note shows the grade")

section("short fights aren't kept")
local n = #KR.char.fights
UNITS.target.dead = false
FireEvent("PLAYER_REGEN_DISABLED")
Cast(78)
Run(3, KR)
FireEvent("PLAYER_REGEN_ENABLED")
check(#KR.char.fights == n, "a 3-second fight is dropped")

section("secrets")
RAGE = SECRET
UNITS.target.hp = SECRET
AURAS.player.HELPFUL = { { name = SECRET } }
FireEvent("PLAYER_REGEN_DISABLED")
FireEvent("UNIT_POWER_UPDATE", "player", "RAGE")
FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
Cast(SECRET)
Run(2, KR)
H:Update()
check(S:Rage() == nil, "secret rage reads as unknown")
check(KR.Hud.rageText:GetText() == "", "no number for secret rage")
FireEvent("PLAYER_REGEN_ENABLED")
check(#ERRORS == 0, "no errors with secret values")
RAGE = 0
UNITS.target.hp = 100
AURAS.player.HELPFUL = {}

--------------------------------------------------------------------------------
section("coach window")
SlashCmdList.KRAKENRAGE("")
check(KrakenrageFrame and KrakenrageFrame:IsShown(), "window opens")
check(KR.UI.page == "fight" and KR.UI.grade:GetText() == C.Grade(r.score), "last fight shown with its grade")
CAPTURE = {}
KR.UI:Show("history")
local hist = table.concat(CAPTURE, "\n")
CAPTURE = nil
check(hist:find("Defias Pillager") ~= nil, "history lists the fight")
KR.UI:Show("bar")
check(#KR.UI.tickChecks >= 8, "a tick box for each known ability with a cost")
KR.UI:Show("fight", 1)
check(KR.UI.viewing == 1, "a fight picked from the history")

section("demo and trends")
SlashCmdList.KRAKENRAGE("demo")
check(#KR.char.fights == n + 12, "demo fights added")
local trends = C:Trends()
check(#trends >= 3 and trends[1].label == "Grade", "trends computed")
local better
for _, tr in ipairs(trends) do if tr.label == "Overpower used" then better = tr.better end end
check(better == true, "the demo warrior gets better at Overpower")
SlashCmdList.KRAKENRAGE("demo")
check(#KR.char.fights == n, "demo fights removed")

section("commands")
SlashCmdList.KRAKENRAGE("lock")
check(KR.db.settings.hud.locked == false, "unlocked")
SlashCmdList.KRAKENRAGE("lock")
check(KR.db.settings.hud.locked == true, "locked again")
SlashCmdList.KRAKENRAGE("scale 5")
check(KR.db.settings.hud.scale == 2, "scale clamped")
SlashCmdList.KRAKENRAGE("swing")
check(KR.db.settings.hud.swing == false, "swing timer off")
SlashCmdList.KRAKENRAGE("help")
SlashCmdList.KRAKENRAGE("clear")
check(#KR.char.fights == 0, "fights forgotten")

section("helpers")
check(C.Grade(96) == "S" and C.Grade(86) == "A" and C.Grade(10) == "D" and C.Grade(nil) == "-", "grades")
check(KR.FormatClock(62) == "1:02" and KR.FormatClock(3725) == "1:02:05", "clock")
check(KR.clean(SECRET) == nil, "clean() drops secrets")

print(("\nRESULT: %d passed, %d failed, %d runtime errors"):format(passed, failed, #ERRORS))
if failed > 0 or #ERRORS > 0 then error("tests failed") end
