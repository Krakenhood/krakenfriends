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
KF.db.settings.sync = false -- the sync has its own section; keep it quiet in the others
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

section("records (hit and crit)")
local pairNow = KF:CurrentPair()
-- on by default; switched off, a perfectly matching cast and target must NOT record anything
check(KF.db.settings.guessRecords == true and KF.db.settings.recordsMigrated == true, "the records are on by default")
SlashCmdList.KRAKENFRIENDS("records")
check(KF.db.settings.guessRecords == false, "/kf records switches them off")
UNITS.target = { guid = "Creature-0-1-0-1-3000-00000300", name = "Training Dummy", hostile = true, ctype = 7, level = 10 }
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-0", 133)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 4242, 4)
check(pairNow.records.me.crit == nil, "nothing is recorded while they are switched off")
-- switch it on with the slash command
SlashCmdList.KRAKENFRIENDS("records")
check(KF.db.settings.guessRecords == true, "/kf records switches them on again")
Advance(2)
UNITS.target = { guid = "Creature-0-1-0-1-3000-00000300", name = "Training Dummy", hostile = true, ctype = 7, level = 10 }
UNITS.nameplate5 = { guid = "Creature-0-1-0-1-3001-00000301", name = "Other Dummy", hostile = true, ctype = 7, level = 10 }
UNITS.party1.target = "nameplate5"
local function hit(unit, flag, amount, school) FireEvent("UNIT_COMBAT", unit, "WOUND", flag, amount, school or 4) end
-- my cast, my target -> mine
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 133)
hit("target", "CRITICAL", 1500)
check(pairNow.records.me.crit and pairNow.records.me.crit.n == 1500 and pairNow.records.me.crit.s == "Fireball", "my crit recorded with its spell")
check(pairNow.records.me.hit and pairNow.records.me.hit.n == 1500, "a crit is also the biggest hit")
-- the same hit delivered again on another token (nameplate of the same guid) must not break anything
UNITS.nameplate6 = UNITS.target
hit("nameplate6", "CRITICAL", 1500)
-- a smaller normal hit changes nothing
Advance(2)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 133)
hit("target", "", 900)
check(pairNow.records.me.hit.n == 1500 and pairNow.records.me.crit.n == 1500, "smaller hit leaves records alone")
-- partner cast on the mob THEY target -> partner's record
Advance(2)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-3", 585)
hit("nameplate5", "CRITICAL", 700, 2) -- Smite is holy
check(pairNow.records.partner.crit and pairNow.records.partner.crit.n == 700 and pairNow.records.partner.crit.s == "Smite", "partner crit credited to the partner")
check(pairNow.records.me.crit.n == 1500, "...and not to me")
-- both cast, both target the same mob -> ambiguous, skipped
Advance(2)
UNITS.party1.target = "target"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 133)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-5", 2136) -- Fire Blast: fire as well
hit("target", "CRITICAL", 9999)
check(pairNow.records.me.crit.n == 1500 and pairNow.records.partner.crit.n == 700, "ambiguous hit is not credited to anyone")
-- stale cast -> skipped
Advance(5)
hit("target", "CRITICAL", 8888)
check(pairNow.records.me.crit.n == 1500, "hit without a recent cast is skipped")
-- damage to friendly targets is ignored
UNITS.party1.hostile = false
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 133)
hit("party1", "CRITICAL", 7777)
check(pairNow.records.me.crit.n == 1500, "damage taken by friends is ignored")
-- secret amounts are ignored
UNITS.party1.target = "nameplate5"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-7", 133)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", SECRET, 4)
check(pairNow.records.me.crit.n == 1500, "secret amount ignored without errors")
-- a bigger crit later gets announced once
Advance(61)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-8", 133)
hit("target", "CRITICAL", 3000)
local announced = 0
for _, e in ipairs(pairNow.log) do if e.k == "record" and e.x:find("crit for 3,000") then announced = announced + 1 end end
check(pairNow.records.me.crit.n == 3000 and announced == 1, "new crit record announced in the journal")
Advance(2)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-9", 133)
hit("target", "CRITICAL", 3600)
local later = 0
for _, e in ipairs(pairNow.log) do if e.k == "record" then later = later + 1 end end
check(pairNow.records.me.crit.n == 3600 and later == 1, "announcements are rate limited")
-- not together -> nothing counts
UNITS.party1.visible = false
C_Map.GetBestMapForUnit = function(u) return u == "player" and 1429 or 1436 end
TickAll()
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-10", 133)
hit("target", "CRITICAL", 50000)
check(pairNow.records.me.crit.n == 3600, "no records while apart")
UNITS.party1.visible = true
C_Map.GetBestMapForUnit = function() return 1429 end
TickAll()
UNITS.party1.hostile = nil

-- /kf records reset clears every record of the journey (and nothing else)
local killsBefore = KF.journey.total.kills
SlashCmdList.KRAKENFRIENDS("records reset")
check(next(pairNow.records.me) == nil and next(pairNow.records.partner) == nil, "/kf records reset clears the records")
check(KF.journey.total.kills == killsBefore, "...and leaves the counters alone")
SlashCmdList.KRAKENFRIENDS("records")
check(KF.db.settings.guessRecords == false, "/kf records switches it off again")
-- re-fill one record so the Overview check below still has something to show
KF:SubmitHit("me", 3600, true, "Fireball", "Training Dummy")
KF:SubmitHit("partner", 700, true, "Smite", "Other Dummy")

-- the Overview shows them, merged across chapters
UI.scope = nil
SlashCmdList.KRAKENFRIENDS("records")
CAPTURE = {}
UI:SelectTab("Overview")
local ovText = table.concat(CAPTURE, " | ")
CAPTURE = nil
SlashCmdList.KRAKENFRIENDS("records")
check(ovText:find("RECORDS") and ovText:find("Biggest crit") and ovText:find("3,600"), "Records block on the Overview")
print("  [records] " .. ovText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("RECORDS.-TRIVIA") or "?")

section("records: claims, the shared column and school matching")
local dp = KF:CurrentPair()
SlashCmdList.KRAKENFRIENDS("records reset")
check(KF.db.settings.guessRecords == false, "the experimental records are off")
UNITS.target = { guid = "Creature-0-1-0-1-3100-00000400", name = "Pack Wolf", hostile = true, ctype = 1, level = 12, threat = { player = 1 } }
UNITS.nameplate7 = { guid = "Creature-0-1-0-1-3101-00000401", name = "Idle Wolf", hostile = true, ctype = 1, level = 12 }
UNITS.party1.target = nil
TickAll()
-- off by default: nothing at all is recorded and the Records block is hidden
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "z0", 133)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 555, 4)
check(dp.records.me.crit == nil and dp.records.partner.crit == nil, "with the feature off (the default) nothing is recorded")
CAPTURE = {}
KF.UI.scope = nil
KF.UI:SelectTab("Overview")
check(not table.concat(CAPTURE, " | "):find("RECORDS"), "...and the Records block is hidden")
CAPTURE = nil
SlashCmdList.KRAKENFRIENDS("records")
check(KF.db.settings.guessRecords == true, "/kf records switches the experimental records on")
Advance(5) -- casts from the earlier tests must not count as recent

-- a hit nobody can explain is never recorded: a passing stranger's holy crit
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 371, 2)
check(dp.records.me.crit == nil and dp.records.partner.crit == nil, "a hit that fits nobody's casts is not recorded")
-- a hit of another school than my last cast is not mine either
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "z1", 133) -- fire
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 372, 2) -- holy
check(dp.records.me.crit == nil, "a holy hit right after my fire spell is not mine")
-- a hit that fits my cast is
Advance(5)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "z2", 133)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 777, 4)
check(dp.records.me.crit and dp.records.me.crit.n == 777 and dp.records.me.crit.s == "Fireball", "a fire hit after my fire spell is mine")
-- a physical ability names no school, which means physical: it claims a physical hit even
-- while I cast fire, and my fire spell claims nothing physical
Advance(5)
UNITS.party1.target = "target"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "z3", 133)  -- my Fireball (fire)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "z4", 78)   -- his Heroic Strike (no school named)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 888, 1)
check(dp.records.partner.crit and dp.records.partner.crit.n == 888 and dp.records.partner.crit.s == "Heroic Strike", "a physical hit goes to the one with the physical ability")
check(dp.records.me.crit.n == 777, "...not to the fire caster")
-- the same hit seen on a second token counts once
UNITS.nameplate6 = UNITS.target
FireEvent("UNIT_COMBAT", "nameplate6", "WOUND", "CRITICAL", 888, 1)
-- in a bigger group nothing is recorded: the others' hits would be in it
Advance(5)
local groupBefore = GROUP.n
GROUP.n = 5
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "z5", 133)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 6000, 4)
check(dp.records.me.crit.n == 777, "nothing is recorded while the group is bigger than two")
GROUP.n = groupBefore
-- a normal hit only raises the hit record
Advance(5)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "z6", 133)
FireEvent("UNIT_COMBAT", "target", "WOUND", "", 900, 4)
check(dp.records.me.hit.n == 900 and dp.records.me.crit.n == 777, "a normal hit raises only the biggest hit")

-- school matching: both of us cast on the same creature
UNITS.party1.target = "target"
Advance(5)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 133)   -- my Fireball (fire)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "c2", 585)   -- his Smite (holy)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1111, 4)
check(dp.records.me.crit.n == 1111 and dp.records.me.crit.s == "Fireball", "a fire hit while he cast a holy spell is mine")
Advance(5)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 133)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "c4", 585)
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 1222, 2)
check(dp.records.partner.crit.n == 1222 and dp.records.partner.crit.s == "Smite", "a holy hit while I cast a fire spell is his")
check(dp.records.me.crit.n == 1111, "...not mine")
Advance(5)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c5", 133)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "c6", 2136)  -- both fire
FireEvent("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 9999, 4)
check(dp.records.me.crit.n == 1111 and dp.records.partner.crit.n == 1222, "two fire casters at once: not recorded for anyone")

-- the shared column is the better of the two; old stored 'together' values are not shown
dp.records.duo.crit = { n = 99999, s = "Holy", t = 1 }
local rec = KF.UI:Lists(KF.journey).records
check(rec.duo.crit.n == 1222 and rec.me.crit.n == 1111 and rec.partner.crit.n == 1222, "the shared column is the better of the two, an old stored value is ignored")
CAPTURE = {}
KF.UI:Refresh()
local on = table.concat(CAPTURE, " | ")
CAPTURE = nil
check(on:find("best guesses") and on:find("Together") and on:find("1,222") and not on:find("99,999"), "Overview: three columns, the stored old value not shown")
dp.records.duo.crit = nil
SlashCmdList.KRAKENFRIENDS("records")
check(KF.db.settings.guessRecords == false, "switched off again")
SlashCmdList.KRAKENFRIENDS("records reset")
-- switching it on redraws the open window by itself (no need to reopen it)
KF:SubmitHit("me", 321, true, "Fire", "Training Dummy")
CAPTURE = {}
SlashCmdList.KRAKENFRIENDS("records")
Advance(1)
check(table.concat(CAPTURE, " | "):find("best guesses"), "/kf records redraws the open window immediately")
CAPTURE = {}
SlashCmdList.KRAKENFRIENDS("records")
Advance(1)
check(not table.concat(CAPTURE, " | "):find("RECORDS"), "...and switching it off hides the block right away")
CAPTURE = nil
SlashCmdList.KRAKENFRIENDS("records reset")

section("messaging test (/kf ping)")
check(PREFIXES and PREFIXES.KRAKENFR, "prefix registered at login")
local chatBefore = #CHAT
-- not in a group -> hint only, nothing sent
local savedGroup = GROUP.n
GROUP.n = 1
SlashCmdList.KRAKENFRIENDS("ping")
check(#SENT == 0 and CHAT[#CHAT]:find("Group up"), "ping without a group only prints a hint")
GROUP.n = savedGroup
-- in a group -> one message goes out and the game's answer is printed
SlashCmdList.KRAKENFRIENDS("ping")
check(#SENT == 1 and SENT[1].prefix == "KRAKENFR" and SENT[1].text:find("^ping|") and SENT[1].chan == "PARTY", "ping is sent to the party")
check(CHAT[#CHAT]:find("restricted = true") and CHAT[#CHAT]:find("Success"), "reports the game's restriction flag and result")
-- no reply -> explained after the timeout
Advance(7)
check(CHAT[#CHAT]:find("No reply yet"), "explains a missing reply")
-- our own echoed message is ignored
local n = #SENT
FireEvent("CHAT_MSG_ADDON", "KRAKENFR", "ping|1.1.1", "PARTY", "Krakenhood-Forever")
check(#SENT == n, "own echoed message is ignored")
-- friend pings us -> we answer
FireEvent("CHAT_MSG_ADDON", "KRAKENFR", "ping|1.1.1", "PARTY", "Thaliadin-Forever")
check(#SENT == n + 1 and SENT[#SENT].text:find("^pong|") and SENT[#SENT].chan == "PARTY", "a friend's ping is answered with a pong")
-- friend answers our ping -> success is reported
SlashCmdList.KRAKENFRIENDS("ping")
FireEvent("CHAT_MSG_ADDON", "KRAKENFR", "pong|1.1.1", "PARTY", "Thaliadin-Forever")
check(KF.messagingWorks == true and CHAT[#CHAT]:find("addon messages work"), "a pong confirms that messaging works")
Advance(7)
check(not CHAT[#CHAT]:find("No reply yet"), "no timeout message after a reply")
-- unrelated prefixes and secret values are ignored
FireEvent("CHAT_MSG_ADDON", "OTHERADDON", "ping|x", "PARTY", "Thaliadin-Forever")
FireEvent("CHAT_MSG_ADDON", "KRAKENFR", SECRET, "PARTY", "Thaliadin-Forever")
check(#SENT == n + 2, "other prefixes and secret text are ignored")
-- /kf status mentions it
SlashCmdList.KRAKENFRIENDS("status")
local sawStatus = false
for i = chatBefore, #CHAT do if CHAT[i]:find("addon messages to your friend: work") then sawStatus = true end end
check(sawStatus, "/kf status reports the messaging result")

section("sync with the friend's copy")
local S = KF.Sync
local j = KF.journey
local me, alt, friend = "Krakenhood-Forever", "Thaliadin-Forever", "Thalianne-Forever"
local myAlt = KF:CurrentPair()                         -- "Krakenhood & Thaliadin"
check(myAlt and myAlt.me == me and myAlt.partner == alt, "the current chapter is Krakenhood & Thaliadin")
KF.db.settings.sync = true
local function say(text, sender) FireEvent("CHAT_MSG_ADDON", "KRAKENFR", text, "PARTY", sender or alt) end
local TAG = j.partnerTag or "Thalia#1234"
local function chat(substring)
    for i = #CHAT, 1, -1 do if CHAT[i]:find(substring, 1, true) then return true end end
    return false
end
local function drain() for _ = 1, 60 do Advance(0.4) end end
drain()

-- before anything: a chapter message without a hello is ignored
local q0 = myAlt.stats.quests
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=50")
check(myAlt.stats.quests == q0, "chapter data without a hello is ignored")

-- a friend's hello, then his numbers: his count is higher, so mine is raised
say("H|1|1.2.0|" .. TAG)
local totalQ = j.total.quests
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=" .. (q0 + 5))
check(myAlt.stats.quests == q0 + 5, "the larger quest count wins")
check(j.total.quests == totalQ + 5, "the journey total grows by the same amount")
-- a lower number does nothing, and so does sending the same thing twice
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=" .. (q0 + 3))
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=" .. (q0 + 5))
check(myAlt.stats.quests == q0 + 5 and j.total.quests == totalQ + 5, "a lower or repeated number changes nothing")

-- his "me" is my "partner": killing blows, deaths, levels and loot are swapped
local kbp, kbm = myAlt.stats.kbPartner, myAlt.stats.kbMe
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|a=" .. (kbp + 7) .. ";p=" .. (kbm + 2) .. ";d=4;f=1;L2=6;P3=2")
check(myAlt.stats.kbPartner == kbp + 7 and myAlt.stats.kbMe == kbm + 2, "his killing blows are my partner's, and the reverse")
check(myAlt.stats.deathsPartner >= 4 and myAlt.stats.deathsMe >= 1, "deaths swapped")
check((myAlt.stats.lootPartner[2] or 0) >= 6 and (myAlt.stats.lootMe[3] or 0) >= 2, "loot by quality swapped")
-- creature types: known ones only
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|y.beast=40;y.nonsense=9;k=" .. (myAlt.stats.kills + 4))
check((myAlt.stats.types.beast or 0) >= 40 and myAlt.stats.types.nonsense == nil, "known creature types merge, unknown ones are ignored")

-- another pair of characters stays its own chapter and never touches this one
local killsBefore, chaptersBefore = myAlt.stats.kills, 0
for _ in pairs(j.pairs) do chaptersBefore = chaptersBefore + 1 end
local totalKills = j.total.kills
say("C|" .. alt .. "|Krakenalt-Forever|WARRIOR|MAGE|k=11;q=2")
local newPair = j.pairs["Krakenalt-Forever & " .. alt]
check(newPair and newPair.stats.kills == 11 and newPair.stats.quests == 2, "an unknown character pair is added as its own chapter")
check(newPair.me == "Krakenalt-Forever" and newPair.partner == alt, "...seen from my side")
check(myAlt.stats.kills == killsBefore, "...and the other chapter is untouched")
check(j.total.kills == totalKills + 11, "...while the journey total counts it")

-- strangers, other protocols, other BattleTags, bad values: ignored
local q1 = myAlt.stats.quests
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=900", "Stranger-Forever")
say("H|2|9.9|" .. TAG)
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=901")
check(myAlt.stats.quests == q1, "a stranger and an unknown protocol are ignored")
say("H|1|1.2.0|Someone#9999")
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=902")
check(myAlt.stats.quests == q1, "another BattleTag is ignored")
say("H|1|1.2.0|" .. TAG)
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=-5;k=abc;e=99999999999;r=")
check(myAlt.stats.quests == q1 and myAlt.stats.elite < 99999999999, "negative, non-numeric and absurd values are ignored")
say(SECRET and "C|x" or "C|x")
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=" .. (q1 + 1))
FireEvent("CHAT_MSG_ADDON", "KRAKENFR", SECRET, "PARTY", alt)
check(myAlt.stats.quests == q1 + 1, "a hidden (secret) message is ignored without errors")

-- the friend's own best hit travels one way, into my partner column
say("Q|" .. alt .. "|" .. me .. "|crit|4321|1790000000|Smite|Pack Wolf")
check(myAlt.records.partner.crit and myAlt.records.partner.crit.n >= 4321 and myAlt.records.partner.crit.s == "Smite", "his best crit arrives in my partner column")
say("Q|" .. alt .. "|" .. me .. "|crit|10|1790000000|Smite|Pack Wolf")
check(myAlt.records.partner.crit.n >= 4321, "...and a smaller one does not replace it")
local mineBefore = myAlt.records.me.crit and myAlt.records.me.crit.n
say("Q|" .. alt .. "|" .. me .. "|crit|99999|1790000000|Smite|Pack Wolf")
check((myAlt.records.me.crit and myAlt.records.me.crit.n) == mineBefore, "...and nothing ever writes into my own column")
say("R|" .. alt .. "|" .. me .. "|crit|88888|1790000000|Fire|Pack Wolf")
check(myAlt.records.duo.crit == nil or myAlt.records.duo.crit.n ~= 88888, "the old shared-record message of version 1.2.0 is ignored")

-- the changes are reported in one line per chapter
Advance(3)
check(chat("synced with Thalia"), "what changed is printed")
check(chat("quests"), "...naming the counters")

-- sending: our chapters, from our side, in small messages
SENT = {}
SlashCmdList.KRAKENFRIENDS("sync")
local again = S:Push()
check(again == false, "an automatic push right after a sync is skipped")
drain()
check(#SENT >= 3 and SENT[1].text:find("^H|1|"), "/kf sync starts with a hello")
local sawChapter, tooBig = false, false
for _, m in ipairs(SENT) do
    if #m.text > 255 then tooBig = true end
    local prefix = "C|" .. me .. "|" .. alt .. "|"
    if m.text:sub(1, #prefix) == prefix then sawChapter = true end
end
check(sawChapter and not tooBig, "our chapter goes out from our side, every message within 255 bytes")
check(SENT[1].prefix == "KRAKENFR" and SENT[1].chan == "PARTY", "sent on the party channel")
local n = #SENT
-- a hello from the friend after a quiet while is answered once
Advance(120)
n = #SENT
say("H|1|1.2.0|" .. TAG)
drain()
check(#SENT > n and SENT[n + 1].text:find("^H|1|"), "a friend's hello is answered with our own journey")
n = #SENT
say("H|1|1.2.0|" .. TAG)
drain()
check(#SENT == n, "...but not again right away (no ping-pong)")

-- when the game says "too fast", the same message is tried again instead of giving up
Advance(120)
SENT = {}
SEND_RESULTS = { 3, 3 }
S:Push(true)
drain()
local first = SENT[1] and SENT[1].text
check(#SENT >= 5 and SENT[2].text == first and SENT[3].text == first and SENT[4].text ~= first, "a throttled message is retried, then the push carries on")
SEND_RESULTS = nil
-- a hard refusal stops the push without errors
Advance(120)
SENT = {}
SEND_RESULTS = { 9 }
S:Push(true)
drain()
check(#SENT == 1, "a refused message stops the push")
SEND_RESULTS = nil

-- big chapters still fit
local big = KF.NewPair("A-Forever", "MAGE", "B-Forever", "PRIEST")
for name in pairs(KF.TypeInfo) do big.stats.types[name] = 123456 end
for q = 0, 5 do big.stats.lootMe[q] = 99999; big.stats.lootPartner[q] = 88888 end
big.stats.kills, big.stats.quests, big.stats.time, big.stats.goldDuo = 999999, 99999, 9999999, 999999999
local fits = true
for _, m in ipairs(S.Messages(big)) do if #m > 255 then fits = false end end
check(fits and #S.Messages(big) >= 2, "a very full chapter is split into messages that fit")

-- off means off: nothing is sent and nothing is taken in
SlashCmdList.KRAKENFRIENDS("sync off")
check(KF.db.settings.sync == false, "/kf sync off")
local q2 = myAlt.stats.quests
say("C|" .. alt .. "|" .. me .. "|WARRIOR|MAGE|q=" .. (q2 + 50))
check(myAlt.stats.quests == q2, "nothing is taken in while syncing is off")
SENT = {}
SlashCmdList.KRAKENFRIENDS("sync")
check(#SENT == 0 and chat("syncing is off"), "nothing is sent while syncing is off")
SlashCmdList.KRAKENFRIENDS("sync on")
check(KF.db.settings.sync == true, "/kf sync on")
KF.db.settings.sync = false

section("names: two-word characters")
do
    local j = KF.journey
    KF:RebuildNames()
    check(KF.DisplayName("Thaliadin-Forever") == "Thaliadin", "a unique first name is shown as it is")
    check(KF.FullName("Naendor-Delorentis") == "Naendor Delorentis", "the full name is the two words")
    check(KF.NormName("Naendor Delorentis") == KF.NormName("naendor-delorentis"), "spellings of one name compare equal")
    -- two of the characters share a first name: the surname's initial tells them apart
    j.chars.me["Miss-Hazecaller"] = { class = "MAGE" }
    j.chars.me["Miss-Zephyrgale"] = { class = "PRIEST" }
    KF:RebuildNames()
    check(KF.DisplayName("Miss-Hazecaller") == "Miss H." and KF.DisplayName("Miss-Zephyrgale") == "Miss Z.", "characters sharing a first name get the surname's initial")
    check(KF.DisplayName("Thaliadin-Forever") == "Thaliadin", "...while other names stay short")
    j.pairs["Miss-Hazecaller & Thaliadin-Forever"] = KF.NewPair("Miss-Hazecaller", "MAGE", "Thaliadin-Forever", "WARRIOR")
    CAPTURE = {}
    KF.UI.scope = nil
    KF.UI:SelectTab("Overview")
    local text = table.concat(CAPTURE, " | ")
    CAPTURE = nil
    check(text:find("Miss H.", 1, true), "the Characters list shows the abbreviated pair")
    j.pairs["Miss-Hazecaller & Thaliadin-Forever"] = nil
    j.chars.me["Miss-Hazecaller"], j.chars.me["Miss-Zephyrgale"] = nil, nil
    KF:RebuildNames()
    check(KF.DisplayName("Miss-Hazecaller") == "Miss", "...and back to the first name once the clash is gone")
end

section("sync: the sender's spelling")
do
    local S = KF.Sync
    local j = KF.journey
    local pair = KF:CurrentPair()
    KF.db.settings.sync = true
    local function from(sender, text) FireEvent("CHAT_MSG_ADDON", "KRAKENFR", text, "PARTY", sender) end
    local TAG = j.partnerTag or "Thalia#1234"
    local chapters = 0
    for _ in pairs(j.pairs) do chapters = chapters + 1 end

    -- Forever delivers two-word names with a space; the keys use a hyphen
    from("Thaliadin Forever", "H|1|1.2.0|" .. TAG)
    local q = pair.stats.quests
    from("Thaliadin Forever", "C|Thaliadin Forever|Krakenhood Forever|WARRIOR|MAGE|q=" .. (q + 2))
    check(pair.stats.quests == q + 2, "a sender written with a space is recognised")
    local after = 0
    for _ in pairs(j.pairs) do after = after + 1 end
    check(after == chapters, "...and its chapter is matched to the existing one, not added twice")
    from("thaliadin-forever", "C|Thaliadin-Forever|Krakenhood-Forever|WARRIOR|MAGE|q=" .. (q + 3))
    check(pair.stats.quests == q + 3, "hyphen and capitals work the same")

    -- someone with the same first name but another surname is not the partner
    from("Thaliadin Smith", "H|1|1.2.0|" .. TAG)
    from("Thaliadin Smith", "C|Thaliadin Smith|Krakenhood Forever|WARRIOR|MAGE|q=" .. (q + 500))
    check(pair.stats.quests == q + 3, "a stranger with the same first name is ignored")
    from("Thaliadin Forever", "H|1|1.2.0|" .. TAG)

    -- our own messages, echoed back by the game in any spelling, are ignored
    KF.messagingWorks = nil
    local n = #SENT
    from("Krakenhood Forever", "pong|1.2.0")
    from("Krakenhood-Forever", "ping|1.2.0")
    check(KF.messagingWorks == nil and #SENT == n, "our own echoed ping and pong are ignored")

    -- with debug on, the raw sender is shown with the verdict
    KF.db.settings.debug = true
    local before = #CHAT
    from("Thaliadin Forever", "H|1|1.2.0|" .. TAG)
    from("Somebody Else", "H|1|1.2.0|" .. TAG)
    KF.db.settings.debug = false
    local sawAccepted, sawIgnored = false, false
    for i = before + 1, #CHAT do
        if CHAT[i]:find('from "Thaliadin Forever"', 1, true) and CHAT[i]:find("accepted", 1, true) then sawAccepted = true end
        if CHAT[i]:find('from "Somebody Else"', 1, true) and CHAT[i]:find("ignored", 1, true) then sawIgnored = true end
    end
    check(sawAccepted and sawIgnored, "debug output names the sender and says accepted or ignored")
    KF.db.settings.sync = false
end

section("sync: lists (a union, never a deletion)")
do
    local S = KF.Sync
    local j = KF.journey
    local pair = KF:CurrentPair()
    KF.db.settings.sync = true
    local TAG = j.partnerTag or "Thalia#1234"
    local H = "Thaliadin Forever"
    local function from(sender, text) FireEvent("CHAT_MSG_ADDON", "KRAKENFR", text, "PARTY", sender) end
    local function L(kind, entries, sender)
        from(sender or H, ("L|%s|Thaliadin-Forever|Krakenhood-Forever|%s"):format(kind, entries))
    end
    local function drain() for _ = 1, 80 do Advance(0.4) end end
    local function sawChat(text)
        for i = #CHAT, 1, -1 do if CHAT[i]:find(text, 1, true) then return true end end
        return false
    end
    from(H, "H|1|1.2.0|" .. TAG)
    local logBefore = #pair.log
    local keepItem = pair.items[5191]

    -- items: added when new, raised when known; his "me" is my "partner"
    L("items", "424242,3,1,2,0,1790000300,1790000400,Test Blade")
    local it = pair.items[424242]
    check(it and it.n == "Test Blade" and it.q == 3 and it.c == 1, "an item only the friend's copy has is added")
    check(it.me == 0 and it.pa == 2, "...with his 'me' count as my partner's")
    L("items", "424242,3,5,1,3,1780000000,1790000500,Test Blade")
    check(it.c == 5 and it.me == 3 and it.pa == 2, "a known item takes the larger counts (swapped), never lower")
    check(it.t == 1780000000 and it.l == 1790000500, "...the earlier first date and the later last date")

    -- rares, bosses, dungeons, zones, creatures, toughest foe
    L("rares", "4242,2,1790000000,35,Test Rare")
    local r = pair.rares[4242]
    check(r and r.c == 2 and r.lv == 35 and r.n == "Test Rare", "a rare is added")
    check(j.firsts["rare:4242"] ~= nil, "...and its journey 'first time' is marked as used")
    check(#pair.log == logBefore, "...without writing a journal entry")
    L("rares", "4242,5,1780000000,35,Test Rare")
    check(r.c == 5 and r.t == 1780000000, "a known rare takes the larger count and the earlier date")
    L("rares", "4242,1,1790000000,10,Test Rare")
    check(r.c == 5 and r.lv == 35, "...and never lower")

    L("bosses", "3,1790000000,Test Boss")
    check(pair.bosses["Test Boss"] and pair.bosses["Test Boss"].c == 3 and j.firsts["boss:Test Boss"], "a boss is added")
    L("dungeons", "36:heroic,2,3600,5,1790000000,The Deadmines (Heroic)")
    local dun = pair.dungeons["36:heroic"]
    check(dun and dun.runs == 2 and dun.time == 3600 and dun.bosses == 5 and dun.n == "The Deadmines (Heroic)", "a heroic dungeon is added under its own key")
    L("dungeons", "36:heroic,1,100,9,1790000000,The Deadmines (Heroic)")
    check(dun.runs == 2 and dun.time == 3600 and dun.bosses == 9, "...each number takes its larger value")
    L("zones", "1790000000,Test Zone")
    check(pair.zones["Test Zone"] == 1790000000 and j.firsts["zone:Test Zone"], "a zone is added")
    L("mobs", "7777,50,12,beast,Test Wolf;8888,3,5,nonsense,Odd Thing")
    check(pair.mobs[7777] and pair.mobs[7777].c == 50 and pair.mobs[7777].ty == "beast", "a creature is added with its type")
    check(pair.mobs[8888] and pair.mobs[8888].ty == "unspecified", "...an unknown type becomes 'unspecified'")
    L("toughest", "40,Big Boss")
    check(pair.toughest and pair.toughest.lv == 40 and pair.toughest.n == "Big Boss", "the toughest foe is taken over")
    L("toughest", "10,Small Fry")
    check(pair.toughest.lv == 40, "...a weaker one doesn't replace it")
    check(pair.items[5191] == keepItem, "nothing that was already there has been replaced or removed")

    -- bad input is ignored without errors
    L("items", ";;,,;x;1,2;66,3,99999999999,0,0,0,0,TooBig;67,9,1,0,0,0,0,BadQuality")
    check(pair.items[66] == nil and pair.items[67] == nil, "malformed, absurd and out-of-range entries are ignored")
    L("items", "555,3,1,0,0,0,0,Stranger Item", "Somebody Else")
    check(pair.items[555] == nil, "a list from a stranger is ignored")
    from(H, "L|weird|Thaliadin-Forever|Krakenhood-Forever|1,2,3")
    from(H, "L|items|Thaliadin-Forever")
    check(true, "an unknown list kind and a cut-off message do nothing")

    -- what changed is reported
    Advance(3)
    check(sawChat("new items") and sawChat("new rares") and sawChat("new bosses"), "the new entries are reported in the sync line")

    -- sending: lists go out once, and again only when they change
    SENT = {}
    SlashCmdList.KRAKENFRIENDS("sync")
    drain()
    local sawItems, big = false, false
    for _, m in ipairs(SENT) do
        if m.text:sub(1, 8) == "L|items|" and m.text:find("424242", 1, true) then sawItems = true end
        if #m.text > 255 then big = true end
    end
    check(sawItems and not big, "/kf sync sends our lists, every message within 255 bytes")
    local function count(prefix)
        local n = 0
        for _, m in ipairs(SENT) do if m.text:sub(1, #prefix) == prefix then n = n + 1 end end
        return n
    end
    Advance(30)
    SENT = {}
    S:Push()
    drain()
    check(count("C|") > 0 and count("L|") == 0, "a later push sends the counters but not unchanged lists")
    pair.items[999001] = { n = "Fresh Find", q = 3, c = 1, me = 1, pa = 0, t = 1790000000, l = 1790000999 }
    Advance(30)
    SENT = {}
    S:Push()
    drain()
    check(count("L|items|") > 0 and count("L|rares|") == 0, "a changed list is sent again, the others are not")
    Advance(100)
    SENT = {}
    from(H, "H|1|1.2.0|" .. TAG)
    drain()
    check(count("L|items|") > 0 and count("L|rares|") > 0, "when the friend says hello again, everything is sent again")
    pair.items[999001] = nil

    -- names are cleaned and big lists are capped
    local weird = KF.NewPair("A-Forever", "MAGE", "B-Forever", "PRIEST")
    weird.items[1] = { n = "A;B,C|D=E", q = 3, c = 1, me = 1, pa = 0, t = 1, l = 1 }
    local cleaned = false
    for _, m in ipairs(S.Messages(weird)) do if m:find("A B C D E", 1, true) then cleaned = true end end
    check(cleaned, "separator characters in names are replaced before sending")
    local bigPair = KF.NewPair("A-Forever", "MAGE", "B-Forever", "PRIEST")
    for i = 1, 500 do
        bigPair.mobs[i] = { n = "Creature " .. i, c = i, lv = 10, ty = "beast" }
        bigPair.items[i] = { n = "Item " .. i, q = 3, c = 1, me = 1, pa = 0, t = i, l = i }
    end
    local items, mobs, fits = 0, 0, true
    for _, m in ipairs(S.Messages(bigPair)) do
        if #m > 255 then fits = false end
        local kind, entries = m:match("^L|(%a+)|[^|]*|[^|]*|(.*)$")
        if kind then
            local n = select(2, entries:gsub(";", ";")) + 1
            if kind == "items" then items = items + n elseif kind == "mobs" then mobs = mobs + n end
        end
    end
    check(fits and items == 200 and mobs == 80, "very long lists are capped (200 items, 80 creatures), every message within 255 bytes")
    KF.db.settings.sync = false
end

section("sync: backup and /kf restore")
do
    local S = KF.Sync
    local id = KF.journey.id
    KF.db.settings.sync = true
    KF.db.backup = nil
    local TAG = KF.journey.partnerTag or "Thalia#1234"
    local H = "Thaliadin Forever"
    local function from(sender, text) FireEvent("CHAT_MSG_ADDON", "KRAKENFRIENDS" and "KRAKENFR", text, "PARTY", sender) end
    local function chapter() return KF:CurrentPair() end
    local function chatHas(text)
        for i = #CHAT, 1, -1 do if CHAT[i]:find(text, 1, true) then return true end end
        return false
    end
    local function oldChapter(b)
        local me, partner = chapter().me, chapter().partner
        for _, p in pairs(b.data.pairs) do if p.me == me and p.partner == partner then return p end end
    end

    -- a batch that changes something leaves a backup of the state just before it
    local q = chapter().stats.quests
    local totalQ = KF.journey.total.quests
    from(H, "H|1|1.2.0|" .. TAG)
    from(H, "C|Thaliadin-Forever|Krakenhood-Forever|WARRIOR|MAGE|q=" .. (q + 40))
    check(chapter().stats.quests == q + 40, "the sync raised the quest count")
    check(KF.db.backup == nil, "the backup is only kept once the batch is over")
    Advance(100)
    local b1 = KF.db.backup
    check(b1 and b1.id == id and b1.t, "a backup exists after a batch that changed something")
    check(oldChapter(b1) and oldChapter(b1).stats.quests == q and b1.data.total.quests == totalQ, "...and holds the state from before that batch")

    -- a batch that changes nothing does not replace it
    from(H, "H|1|1.2.0|" .. TAG)
    from(H, "C|Thaliadin-Forever|Krakenhood-Forever|WARRIOR|MAGE|q=" .. (q + 40))
    Advance(100)
    check(KF.db.backup == b1, "a batch that changed nothing leaves the backup alone")

    -- the next batch that matters replaces it, with the state just before itself
    from(H, "H|1|1.2.0|" .. TAG)
    from(H, "C|Thaliadin-Forever|Krakenhood-Forever|WARRIOR|MAGE|q=" .. (q + 60))
    Advance(100)
    local b2 = KF.db.backup
    check(b2 ~= b1 and oldChapter(b2).stats.quests == q + 40, "the next changing batch replaces it: the backup never reaches further back than that batch")

    -- /kf status mentions it
    SlashCmdList.KRAKENFRIENDS("status")
    check(chatHas("backup for /kf restore"), "/kf status mentions the backup")

    -- restoring asks first, then puts the journey back and keeps tracking
    local popups = #POPUPS
    SlashCmdList.KRAKENFRIENDS("restore")
    check(#POPUPS == popups + 1 and POPUPS[#POPUPS].which == "KRAKENFRIENDS_RESTORE", "/kf restore asks for confirmation")
    check(chapter().stats.quests == q + 60, "...and changes nothing before the answer")
    StaticPopupDialogs.KRAKENFRIENDS_RESTORE.OnAccept()
    check(chapter().stats.quests == q + 40, "accepting puts the journey back to the state before the last sync")
    check(KF.partner and KF.partner.journey == KF.db.journeys[id] and KF.journey == KF.db.journeys[id], "the partner and the window use the restored journey")
    local kills = KF.journey.total.kills
    FireEvent("PARTY_KILL", "Player-1-0000AAAA", "Creature-0-1-0-1-9999-00000999")
    check(KF.journey.total.kills == kills + 1, "tracking carries on in the restored journey")

    -- without a backup there is nothing to restore
    KF.db.backup = nil
    local n = #POPUPS
    SlashCmdList.KRAKENFRIENDS("restore")
    check(#POPUPS == n and chatHas("no backup yet"), "/kf restore without a backup only explains")

    -- a message that fails is skipped and reported; the rest of the sync carries on
    local realOnList = S.OnList
    S.OnList = function() error("boom") end
    ERRORS = {}
    from(H, "H|1|1.2.0|" .. TAG)
    from(H, "L|items|Thaliadin-Forever|Krakenhood-Forever|1,3,1,0,0,0,0,Whatever")
    check(#ERRORS == 1, "a failing message is reported once")
    ERRORS = {}
    S.OnList = realOnList
    local q3 = chapter().stats.quests
    from(H, "C|Thaliadin-Forever|Krakenhood-Forever|WARRIOR|MAGE|q=" .. (q3 + 1))
    check(chapter().stats.quests == q3 + 1, "...and later messages still get through")
    KF.db.settings.sync = false
end

section("sync: round trip through the encoder and decoder")
do
    local S = KF.Sync
    KF.db.settings.sync = true
    local TAG = KF.journey.partnerTag or "Thalia#1234"
    local H = "Thaliadin Forever"
    local function from(text) FireEvent("CHAT_MSG_ADDON", "KRAKENFR", text, "PARTY", H) end

    -- a chapter full of distinctive numbers, as the FRIEND's copy would hold it
    local src = KF.NewPair("Alpha-Forever", "MAGE", "Beta-Forever", "PRIEST")
    local s = src.stats
    s.kills, s.elite, s.rare, s.boss, s.quests, s.runs, s.time, s.goldDuo = 111, 12, 3, 4, 55, 6, 7777, 88888
    s.kbMe, s.kbPartner, s.deathsMe, s.deathsPartner, s.levelsMe, s.levelsPartner = 21, 22, 3, 4, 5, 6
    for q = 0, 5 do s.lootMe[q] = 7 + q; s.lootPartner[q] = 17 + q end
    s.types = { beast = 30, humanoid = 40, undead = 5 }
    src.rares[522] = { n = "Mor Ladim", c = 2, t = 1790000100, lv = 30 }
    src.bosses["Boss One"] = { c = 3, t = 1790000200 }
    src.dungeons[36] = { n = "The Deadmines", runs = 2, time = 900, bosses = 5, last = 1790000300 }
    src.dungeons["36:heroic"] = { n = "The Deadmines (Heroic)", runs = 1, time = 500, bosses = 3, last = 1790000350 }
    src.zones["Zone One"] = 1790000400
    src.mobs[116] = { n = "Defias Bandit", c = 60, ty = "humanoid", lv = 14 }
    src.items[2244] = { n = "Krol Blade", q = 4, c = 2, me = 5, pa = 2, t = 1790000500, l = 1790000600 }
    src.toughest = { n = "Edwin VanCleef", lv = 22 }
    src.records.me.crit = { n = 999, s = "Fireball", d = "Pack Wolf", t = 1790000700, ch = "Alpha" }
    src.records.me.hit = { n = 999, s = "Fireball", d = "Pack Wolf", t = 1790000700, ch = "Alpha" }

    local backup = { id = KF.journey.id, data = KF.DeepCopy(KF.journey) }
    local msgs = S.Messages(src)
    local fits = true
    for _, m in ipairs(msgs) do if #m > 255 then fits = false end end
    check(#msgs >= 8 and fits, "the chapter is encoded into several messages that fit")

    from("H|1|1.2.0|" .. TAG)
    for _, m in ipairs(msgs) do from(m) end
    local got = KF.journey.pairs["Beta-Forever & Alpha-Forever"]
    check(got ~= nil, "the chapter arrives under the receiver's name for the pair")
    local g = got.stats
    check(g.kills == 111 and g.elite == 12 and g.rare == 3 and g.boss == 4 and g.quests == 55 and g.runs == 6 and g.time == 7777 and g.goldDuo == 88888, "shared counters arrive unchanged")
    check(g.kbMe == 22 and g.kbPartner == 21 and g.deathsMe == 4 and g.deathsPartner == 3 and g.levelsMe == 6 and g.levelsPartner == 5, "'me' and 'partner' counters arrive swapped")
    local lootOk = true
    for q = 0, 5 do
        if g.lootPartner[q] ~= 7 + q or g.lootMe[q] ~= 17 + q then lootOk = false end
    end
    check(lootOk, "loot counts by quality arrive swapped")
    check(g.types.beast == 30 and g.types.humanoid == 40 and g.types.undead == 5, "kills by creature type arrive unchanged")
    check(got.rares[522] and got.rares[522].c == 2 and got.rares[522].lv == 30 and got.rares[522].n == "Mor Ladim" and got.rares[522].t == 1790000100, "a rare arrives complete")
    check(got.bosses["Boss One"] and got.bosses["Boss One"].c == 3 and got.bosses["Boss One"].t == 1790000200, "a boss arrives complete")
    check(got.dungeons[36] and got.dungeons[36].runs == 2 and got.dungeons[36].time == 900 and got.dungeons[36].bosses == 5 and got.dungeons[36].last == 1790000300, "a dungeon arrives complete")
    check(got.dungeons["36:heroic"] and got.dungeons["36:heroic"].runs == 1 and got.dungeons["36:heroic"].n == "The Deadmines (Heroic)", "a heroic dungeon keeps its own key")
    check(got.zones["Zone One"] == 1790000400, "a zone arrives with its date")
    check(got.mobs[116] and got.mobs[116].c == 60 and got.mobs[116].ty == "humanoid" and got.mobs[116].lv == 14 and got.mobs[116].n == "Defias Bandit", "a creature arrives complete")
    local it = got.items[2244]
    check(it and it.q == 4 and it.c == 2 and it.me == 2 and it.pa == 5 and it.n == "Krol Blade" and it.t == 1790000500 and it.l == 1790000600, "an item arrives complete, its 'me' and 'partner' swapped")
    check(got.toughest and got.toughest.lv == 22 and got.toughest.n == "Edwin VanCleef", "the toughest foe arrives")
    check(got.records.partner.crit and got.records.partner.crit.n == 999 and got.records.partner.crit.s == "Fireball" and got.records.partner.crit.d == "Pack Wolf", "his own best crit arrives in my partner column")
    check(next(got.records.me) == nil, "...and my own column stays empty")

    -- and sending it again changes nothing
    local before = KF.DeepCopy(got)
    from("H|1|1.2.0|" .. TAG)
    for _, m in ipairs(msgs) do from(m) end
    local same = true
    local function compare(a, b)
        for k, v in pairs(a) do
            if type(v) == "table" then if type(b[k]) ~= "table" or not compare(v, b[k]) then return false end
            elseif b[k] ~= v then return false end
        end
        return true
    end
    check(compare(before, got) and compare(got, before), "applying the same messages again changes nothing")

    -- put the journey back as it was, so the later tests are unaffected
    KF.db.backup = backup
    KF:RestoreBackup()
    KF.db.backup = nil
    KF.db.settings.sync = false
end

section("look: classic (default) and the game's own style")
do
    local UI = KF.UI
    local function chatHas(text)
        for i = #CHAT, 1, -1 do if CHAT[i]:find(text, 1, true) then return true end end
        return false
    end
    check(KF.db.settings.style == "classic" and KF.palette == "classic", "the original teal look is the default")
    check(KF.Theme.accent[1] == 0.31 and KF.Theme.accent[3] == 0.77 and KF.Theme.bg[4] == 0.96, "the Theme carries the teal colours")
    check(UI.backdrop == nil and UI.title == nil, "the window has the teal frame, without the gold border and title")
    check(UI:CreateBackdrop(CreateFrame("Frame")) == "classic", "the classic frame builder is used")

    -- the game's own look, chosen through the saved setting
    KF.db.settings.style = "wow"
    KF:LoadDB()
    local A = KF.Theme.accent
    check(KF.palette == "wow" and A[1] == 1 and A[2] == 0.82 and A[3] == 0, "wow brings the gold of the game's look")
    check(KF.Theme.bg[4] == 0 and KF.Theme.ring[4] == 1, "...the background is left to the backdrop and the icon cut-out stays solid")
    check(UI:CreateBackdrop(CreateFrame("Frame")) == "wow" and UI.backdrop ~= nil and UI.title:GetText() == "Krakenfriends", "...with the gold border and the fantasy-font title")
    -- back to classic
    KF.db.settings.style = "classic"
    KF:LoadDB()
    check(KF.palette == "classic" and KF.Theme.accent[1] == 0.31 and KF.Theme.bg[4] == 0.96, "classic brings the teal colours back")
    check(UI:CreateBackdrop(CreateFrame("Frame")) == "classic" and UI.backdrop == nil and UI.title == nil, "...and the teal frame")
    -- an unknown value falls back to the default
    KF.db.settings.style = "weird"
    KF:LoadDB()
    check(KF.db.settings.style == "classic" and KF.palette == "classic", "an unknown style falls back to the original look")

    -- the command
    local popups = #POPUPS
    SlashCmdList.KRAKENFRIENDS("style")
    check(chatHas("current look: classic") and #POPUPS == popups, "/kf style on its own says which look is active")
    SlashCmdList.KRAKENFRIENDS("style bogus")
    check(#POPUPS == popups and KF.db.settings.style == "classic", "an unknown name changes nothing")
    SlashCmdList.KRAKENFRIENDS("style wow")
    check(KF.db.settings.style == "wow" and #POPUPS == popups + 1 and POPUPS[#POPUPS].which == "KRAKENFRIENDS_RELOAD", "/kf style wow is saved and offers a reload")
    SlashCmdList.KRAKENFRIENDS("style classic")
    check(KF.db.settings.style == "classic" and #POPUPS == popups + 1 and chatHas("already active"), "going back before reloading needs no reload")
    SlashCmdList.KRAKENFRIENDS("status")
    check(chatHas("look: classic"), "/kf status shows the look")

    -- the welcome screen names the other look
    local function welcome()
        CAPTURE = {}
        UI:ReleaseAll()
        UI:BuildWelcome(0)
        local text = table.concat(CAPTURE, " | ")
        CAPTURE = nil
        return text
    end
    check(welcome():find("/kf style wow", 1, true), "in the original look, the welcome screen points to the game's own look")
    KF.db.settings.style = "wow"
    KF:LoadDB()
    check(welcome():find("/kf style classic", 1, true), "in the game's look, it points back to the original")
    KF.db.settings.style = "classic"
    KF:LoadDB()
end

section("records on by default: the one-time step for existing saves")
do
    -- a save from an older version: the records were off by default, and that false was saved
    KF.db.settings.guessRecords = false
    KF.db.settings.recordsMigrated = nil
    KF:LoadDB()
    check(KF.db.settings.guessRecords == true and KF.db.settings.recordsMigrated == true, "an older save is switched on once")
    -- afterwards the player's own choice stays
    SlashCmdList.KRAKENFRIENDS("records")
    check(KF.db.settings.guessRecords == false, "the player switches them off")
    KF:LoadDB()
    check(KF.db.settings.guessRecords == false, "...and a later start doesn't switch them on again")
    KF.db.settings.guessRecords = false -- the later tests expect them off
end

section("save + restore (beta safety net)")
FireEvent("PLAYER_LOGOUT")
check(KrakenfriendsDB.savedAt == math.floor(NOW) and KrakenfriendsCharDB == KrakenfriendsDB, "saved to both globals")
local snapshot = KrakenfriendsDB
KrakenfriendsDB, KrakenfriendsCharDB, KrakenfriendsRestore = nil, nil, snapshot
KF:LoadDB()
check(KF.dbSource == "restore" and KF.db.journeys["Thalia#1234"].total.kills == snapshot.journeys["Thalia#1234"].total.kills, "restore file picked up")
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

