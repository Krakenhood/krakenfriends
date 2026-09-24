-- Loads the addon in TOC order and plays through a session.
local NS = {}
for _, name in ipairs(TOC) do
    local chunk, err = load(FILES[name], "@" .. name)
    if not chunk then error(err) end
    chunk("Krakenfriends", NS)
end
local KF = NS
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL: " .. label) end
end
local MAIN = "Krakenhood-Forever & Thalianne-Forever"
local function P() return KF.journey.pairs[MAIN] end
local function section(t) print("\n== " .. t) end

local ME = "Player-1-0000AAAA"
local PARTNER = "Player-1-0000BBBB"
UNITS.player = { guid = ME, name = "Krakenhood", realm = "Forever", class = "MAGE", level = 14, player = true }

section("login")
FireEvent("ADDON_LOADED", "Krakenfriends")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD", true, false)
check(KF.ready and KF.me.key == "Krakenhood-Forever", "player identity")
check(KF.dbSource == "new", "fresh database")
check(KF.journey == nil, "no journey yet")
check(#KF.missingEvents == 0, "all events registered: " .. table.concat(KF.missingEvents, ","))
SlashCmdList.KRAKENFRIENDS("")
check(KrakenfriendsFrame and KrakenfriendsFrame:IsShown(), "window opens with welcome")

section("group up -> prompt -> journey")
UNITS.party1 = { guid = PARTNER, name = "Thalianne", class = "PRIEST", level = 13, player = true }
BNET = { [PARTNER] = { battleTag = "Thalia#1234" } }
GROUP.n = 2
FireEvent("GROUP_ROSTER_UPDATE")
Advance(2)
check(#POPUPS == 1 and POPUPS[1].which == "KRAKENFRIENDS_START", "start prompt shown")
StaticPopupDialogs.KRAKENFRIENDS_START.OnAccept(nil, POPUPS[1].data)
check(KF.journey and KF.journey.id == "Thalia#1234", "journey keyed by BattleTag")
check(KF.journey.partnerName == "Thalia", "partner display name from BattleTag")
check(KF.partner and KF.partner.unit == "party1", "partner bound to party1")
check(KF.together == true, "together (visible)")
TickAll() -- heartbeat
Advance(2)
TickAll()
check(KF.journey.total.time > 0, "time together accumulates")
check(P().zones["Elwynn Forest"] ~= nil, "zone discovered together")

section("kills")
local MOB1 = "Creature-0-1-0-1-116-00000001"
UNITS.target = { guid = MOB1, name = "Defias Bandit", hostile = true, ctype = 7, level = 15, threat = { player = 1 } }
FireEvent("PLAYER_TARGET_CHANGED")
FireEvent("PLAYER_REGEN_DISABLED")
FireEvent("PARTY_KILL", ME, MOB1)
local s = KF.journey.total
check(s.kills == 1 and s.kbMe == 1 and s.types.humanoid == 1, "my kill counted as humanoid with killing blow")
check(P().mobs[116] and P().mobs[116].n == "Defias Bandit", "foe recorded by npc id")
FireEvent("UNIT_DIED", MOB1)
Advance(1)
check(s.kills == 1, "UNIT_DIED after PARTY_KILL does not double count")

-- partner kill of a mob we never saw (no unit token)
local MOB2 = "Creature-0-1-0-1-3/0-00000002"
MOB2 = "Creature-0-1-0-1-299-00000002"
NAMES_BY_GUID = { [MOB2] = "Young Wolf" }
FireEvent("PARTY_KILL", PARTNER, MOB2)
check(s.kills == 2 and s.kbPartner == 1 and s.types.unknown == 1, "partner kill of unseen mob -> unidentified")

-- pet kill: UNIT_DIED first (engaged mob), PARTY_KILL arrives later
local MOB3 = "Creature-0-1-0-1-524-00000003"
UNITS.nameplate1 = { guid = MOB3, name = "Rockhide Boar", hostile = true, ctype = 1, level = 12, threat = { party1 = 2 } }
FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
FireEvent("UNIT_DIED", MOB3)
Advance(1)
check(s.kills == 3 and s.types.beast == 1, "engaged mob dying via UNIT_DIED counts")
FireEvent("PARTY_KILL", PARTNER, MOB3)
check(s.kills == 3 and s.kbPartner == 2, "late PARTY_KILL adds the killing blow only")

-- a mob we never fought dies nearby: ignored
local MOB4 = "Creature-0-1-0-1-525-00000004"
UNITS.nameplate2 = { guid = MOB4, name = "Other's Boar", hostile = true, ctype = 1, level = 12 }
FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
FireEvent("UNIT_DIED", MOB4)
Advance(1)
check(s.kills == 3, "someone else's mob is not counted")

-- rare with a secret name
local RARE = "Creature-0-1-0-1-522-00000005"
UNITS.target = { guid = RARE, name = SECRET, hostile = true, ctype = 6, level = 35, cls = "rare", threat = { player = 3 } }
FireEvent("PLAYER_TARGET_CHANGED")
FireEvent("PARTY_KILL", ME, RARE)
check(s.kills == 4 and s.rare == 1 and s.types.undead == 1, "rare counted even with a secret name")
check(P().rares[522] ~= nil, "rare listed")

section("loot and gold")
FireEvent("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:2244::::::::15:::::::|h[Krol Blade]|h|r.", "Krakenhood")
FireEvent("CHAT_MSG_LOOT", "Thalianne receives loot: |cff1eff00|Hitem:15210::::::::15:::::::|h[Raider Shortsword]|h|rx2.", "Thalianne")
FireEvent("CHAT_MSG_LOOT", "You receive loot: |cff9d9d9d|Hitem:2934::::::::15:::::::|h[Ruined Leather Scraps]|h|rx3.", "Krakenhood")
FireEvent("CHAT_MSG_LOOT", "Stranger receives loot: |cff0070dd|Hitem:5191::::::::15:::::::|h[Cruel Barb]|h|r.", "Stranger")
check((s.lootMe[4] or 0) == 1, "my epic counted")
check((s.lootPartner[2] or 0) == 2, "partner green x2 counted")
check((s.lootMe[0] or 0) == 3, "gray x3 counted")
check(s.lootPartner[3] == nil, "third party loot ignored")
check(P().items[2244] and P().items[2244].n == "Krol Blade", "epic stored by name")
check(P().items[2934] == nil, "grays not stored by name")
FireEvent("CHAT_MSG_MONEY", "Your share of the loot is 1 Gold, 23 Silver, 45 Copper.")
FireEvent("CHAT_MSG_MONEY", "You loot 50 Copper")
check(s.goldMe == 12395 and s.goldDuo == 24740, ("gold me=%s duo=%s"):format(s.goldMe, s.goldDuo))
FireEvent("CHAT_MSG_MONEY", "You loot 2|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 5|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
check(s.goldMe == 12600, "money with coin textures parsed: " .. s.goldMe)

section("dungeon run")
INSTANCE = { name = "The Deadmines", type = "party", id = 36 }
ZONE = "The Deadmines"
FireEvent("ZONE_CHANGED_NEW_AREA")
check(KF.journey.currentRun and KF.journey.currentRun.n == "The Deadmines", "run started")
check(s.runs == 1, "run counted")
FireEvent("ENCOUNTER_START", 1, "Edwin VanCleef", 1, 5)
local BOSS = "Creature-0-1-0-1-639-00000009"
UNITS.target = { guid = BOSS, name = "Edwin VanCleef", hostile = true, ctype = 7, level = 21, cls = "elite", boss = true, threat = { player = 3 } }
FireEvent("PLAYER_TARGET_CHANGED")
FireEvent("PARTY_KILL", PARTNER, BOSS)
FireEvent("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
FireEvent("BOSS_KILL", 1, "Edwin VanCleef")
check(s.boss == 1, "boss counted once: " .. s.boss)
check(KF.journey.currentRun.bosses == 1 and KF.journey.currentRun.kills == 1, "run tracks kills and bosses")
check(s.elite == 1, "elite counted")
-- corpse run: out and back in within 30 min continues the run
INSTANCE = { name = "Westfall", type = "none", id = 0 }
ZONE = "Westfall"
FireEvent("ZONE_CHANGED_NEW_AREA")
Advance(1, 300)
INSTANCE = { name = "The Deadmines", type = "party", id = 36 }
FireEvent("ZONE_CHANGED_NEW_AREA")
check(s.runs == 1, "re-entering continues the same run")
-- leave for good
INSTANCE = { name = "Westfall", type = "none", id = 0 }
FireEvent("ZONE_CHANGED_NEW_AREA")
Advance(1, 31 * 60)
for _ = 1, 5 do TickAll() end
check(KF.journey.currentRun == nil and #P().runs == 1, "run finished after 30 minutes outside")
check(P().dungeons[36].runs == 1 and P().dungeons[36].bosses == 1, "dungeon summary")

section("deaths, levels, quests")
FireEvent("PLAYER_DEAD")
check(s.deathsMe == 1, "my death")
UNITS.party1.dead = true
FireEvent("UNIT_DIED", PARTNER)
FireEvent("UNIT_HEALTH", "party1")
check(s.deathsPartner == 1, "partner death counted once")
UNITS.party1.dead = false
FireEvent("UNIT_HEALTH", "party1")
UNITS.party1.level = 14
FireEvent("UNIT_LEVEL", "party1")
FireEvent("PLAYER_LEVEL_UP", 15)
check(s.levelsMe == 1 and s.levelsPartner == 1, "levels together")
FireEvent("QUEST_TURNED_IN", 123, 450, 100)
check(s.quests == 1, "quest counted")

section("apart: nothing counts")
UNITS.party1.visible = false
C_Map.GetBestMapForUnit = function(u) return u == "player" and 1429 or 1436 end
TickAll()
check(KF.together == false, "apart when out of sight and in another zone")
local before = s.kills
FireEvent("PARTY_KILL", ME, "Creature-0-1-0-1-116-00000077")
check(s.kills == before, "kills while apart are not counted")
UNITS.party1.visible = true
TickAll()
check(KF.together == true, "together again")

section("milestones and journal")
local kinds = {}
for _, e in ipairs(P().log) do kinds[e.k] = (kinds[e.k] or 0) + 1 end
check(kinds.start == 1 and kinds.rare == 1 and kinds.boss == 1 and kinds.loot == 1 and kinds.dungeon == 1, "journal entries")
check(KF.journey.done["kills:1"] and KF.journey.done["runs:1"] and KF.journey.done["epics:1"], "first-time milestones")
check(P().stats.kills == s.kills, "pair stats mirror totals")

section("UI render")
local UI = KF.UI
for _, tab in ipairs({ "Overview", "Bestiary", "Loot", "Dungeons", "Journal" }) do
    CAPTURE = {}
    UI:SelectTab(tab)
    print(("  [%s] %s"):format(tab, table.concat(CAPTURE, " | "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "g")))
    CAPTURE = nil
end
UI:ToggleMenu(UI.scopeButton)
check(UI.menu:IsShown(), "journey/character menu opens")
UI.menu:Hide()

section("demo + alt characters")
SlashCmdList.KRAKENFRIENDS("demo")
check(KF.db.journeys["demo:Demo"] and UI:ViewedJourney().id == "demo:Demo", "demo shown")
CAPTURE = {}
UI:SelectTab("Overview")
print("  [demo] " .. table.concat(CAPTURE, " | "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "g"))
CAPTURE = nil
SlashCmdList.KRAKENFRIENDS("demo")
check(KF.db.journeys["demo:Demo"] == nil and UI:ViewedJourney().id == "Thalia#1234", "demo removed")
-- partner logs an alt: recognised through the BattleTag
UNITS.party1 = { guid = "Player-1-0000CCCC", name = "Thaliadin", class = "WARRIOR", level = 5, player = true }
BNET["Player-1-0000CCCC"] = { battleTag = "Thalia#1234" }
FireEvent("GROUP_ROSTER_UPDATE")
check(KF.partner and KF.partner.key == "Thaliadin-Forever" and KF.journey.id == "Thalia#1234", "partner alt linked by BattleTag")
check(#POPUPS == 1, "no second prompt for a known partner")

section("alt chapter")
local main = P()
local mainKills = main.stats.kills
UNITS.party1.visible = true
TickAll()
check(KF.together, "together with the alt")
local ALTMOB = "Creature-0-1-0-1-116-00000100"
UNITS.target = { guid = ALTMOB, name = "Defias Bandit", hostile = true, ctype = 7, level = 16, threat = { player = 1 } }
FireEvent("PLAYER_TARGET_CHANGED")
FireEvent("PARTY_KILL", "Player-1-0000CCCC", ALTMOB)
FireEvent("CHAT_MSG_LOOT", "Thaliadin receives loot: |cff0070dd|Hitem:5191::::::::15:::::::|h[Cruel Barb]|h|r.", "Thaliadin")
ZONE = "Elwynn Forest"
FireEvent("ZONE_CHANGED_NEW_AREA")
local altPair = KF.journey.pairs["Krakenhood-Forever & Thaliadin-Forever"]
check(altPair ~= nil, "second chapter created for the alt")
check(altPair.stats.kills == 1 and altPair.stats.kbPartner == 1, "alt chapter counts its own kill")
check(main.stats.kills == mainKills, "main chapter untouched")
check(KF.journey.total.kills == mainKills + 1, "journey total = sum of chapters")
check(altPair.mobs[116].c == 1 and main.mobs[116].c == 1, "foes kept per chapter")
check(altPair.items[5191] and altPair.items[5191].pa == 1, "alt loot in alt chapter")
check(altPair.zones["Elwynn Forest"] ~= nil, "zone visited in alt chapter")
local zoneLogs = 0
for _, p in pairs(KF.journey.pairs) do for _, e in ipairs(p.log) do if e.x == "Discovered Elwynn Forest together" then zoneLogs = zoneLogs + 1 end end end
check(zoneLogs == 1, "journey-first zone logged only once across chapters")
UNITS.party1.level = 6
FireEvent("UNIT_LEVEL", "party1")
check(altPair.stats.levelsPartner == 1, "alt level-up counted in alt chapter")
check(altPair.lvMin == 5 and altPair.lvMax == 14, "alt chapter level range: " .. tostring(altPair.lvMin) .. "-" .. tostring(altPair.lvMax))

local UI = KF.UI
local function strip(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "g")) end
UI.scope = nil
local L = UI:Lists(KF.journey)
check(L.multi and L.mobs[116].c == 2, "merged view sums foes across chapters")
check(L.items[5191].by["Krakenhood-Forever & Thaliadin-Forever"] == 1, "merged items remember their chapter")
UI.scope = MAIN
L = UI:Lists(KF.journey)
check(not L.multi and L.mobs[116].c == 1 and L.items[5191] == nil, "scoped view shows only that chapter")
UI.scope = nil
CAPTURE = {}
UI:SelectTab("Overview")
local text = strip(table.concat(CAPTURE, " | "))
CAPTURE = nil
check(text:find("CHARACTERS") and text:find("playing now"), "Characters section with live marker")
print("  [overview] " .. text)
CAPTURE = {}
UI:SelectTab("Journal")
text = strip(table.concat(CAPTURE, " | "))
CAPTURE = nil
check(text:find("Krakenhood & Thaliadin") and text:find("Krakenhood & Thalianne"), "journal tags entries with their chapter")
print("  [journal, all] " .. text:sub(1, 500))
UI.scope = MAIN
CAPTURE = {}
UI:Refresh()
text = strip(table.concat(CAPTURE, " | "))
CAPTURE = nil
check(not text:find("Krakenhood & Thaliadin"), "scoped journal hides other chapters")
check(text:find("Thalianne") ~= nil, "scoped header shows the chapter's characters")
print("  [journal, main chapter] " .. text:sub(1, 300))
UI.scope = nil

section("save + restore (beta safety net)")
FireEvent("PLAYER_LOGOUT")
check(KrakenfriendsDB.savedAt == NOW and KrakenfriendsCharDB == KrakenfriendsDB, "saved to both globals")
local snapshot = KrakenfriendsDB
KrakenfriendsDB, KrakenfriendsCharDB, KrakenfriendsRestore = nil, nil, snapshot
KF:LoadDB()
check(KF.dbSource == "restore" and KF.db.journeys["Thalia#1234"].total.kills == s.kills, "restore file picked up")
local older = CopyTable(snapshot); older.savedAt = 1
KrakenfriendsDB, KrakenfriendsCharDB, KrakenfriendsRestore = snapshot, nil, older
KF:LoadDB()
check(KF.dbSource == "account", "newer account save wins over a stale restore")

section("helpers")
check(KF.Tracker.toPattern("%s receives loot: %sx%d.", true) == "^(.-) receives loot: (.-)x(%d+)%.$", "pattern conversion")
check(KF.FormatMoney(1234567, true):find("^123") ~= nil, "short money")
check(KF.FormatDuration(3600 * 26 + 60) == "1d 2h", "duration")
check(KF.clean(SECRET) == nil, "clean() drops secrets")

print(("\nRESULT: %d passed, %d failed, %d runtime errors"):format(passed, failed, #ERRORS))
if failed > 0 or #ERRORS > 0 then error("tests failed") end

