# Krakenfriends

A duo journey tracker for **World of Warcraft: Forever**. Turn it on, group up with your friend, and everything you do together is counted:

- **Kills** by creature type (humanoid, beast, undead, demon, …), elites, rares and bosses
- **Killing blows**, items looted and deaths as a friendly rivalry
- **Dungeon runs**: per dungeon, bosses, time inside, recent runs
- **Loot** by quality (gray to legendary), with names kept for green and better
- **Gold looted** together and your own share
- **Records** (experimental on Forever, on by default): the biggest hit and biggest crit of each of you, and the better of the two in the middle. The game doesn't say who dealt a hit, so this is a guess; `/kf records` switches it off. See Known issues
- **Trivia**: time together, quests, levels gained, zones explored, most hunted foe, toughest foe, favorite dungeon
- **Journal**: a timeline of firsts and milestones (first rare, first epic, 1,000 kills, new zones, levels, …)
- **Sync with your friend**: your two copies swap their numbers now and then, and each keeps the larger one, so counts like quests stay in step even when one of you logged off first. Creatures, rares, bosses, dungeons, zones and items either of you found are merged too. `/kf restore` undoes the last sync that changed something
- **Two looks**: the original teal look by default, and the game's own style (gold border on dark stone, a fantasy-font title, the game's gold) as `/kf style wow`, which matches KrakenChat. Switching asks for a reload, because the colours are built into the window

## Install

Copy the `Krakenfriends` folder into the game's `Interface\AddOns` folder:

- Beta: `World of Warcraft\_classic_beta_\Interface\AddOns\Krakenfriends`
- Live (from November 4): the same path under the Forever game folder

Then type `/kf` in game, or click the minimap button (or the addon compartment entry, if your client has one).

## How tracking works

- **Together means**: your partner is in your group, online, and either in sight (about 100 yards) or in the same zone. Nothing is counted while you're apart. The status line and the minimap pip show green (together), amber (grouped but apart), or nothing.
- **Your characters**: all of your characters share one database, so your alts add up automatically.
- **Your friend's characters**: your friend is recognised by **BattleTag** through the Battle.net friends list, so their alts link up on their own. Someone who isn't a Battle.net friend is remembered by character name.
- **Chapters**: every pairing of characters (for example "Krakenhood & Thalianne", or your alt with theirs) is its own chapter, with its own counters, foes, rares, loot, dungeon runs, zones and journal. The window shows the whole journey (all chapters added up) by default. The **Characters** section on the Overview lists each chapter with its level range, kills, runs and time together: click one to filter the whole window to it, and click it again to go back. The selector at the top right does the same. In the combined view, tooltips and journal lines tell you which characters an entry came from.
- **More than one friend**: each friend gets their own journey. Switch between them with the same selector.
- **Both of you can install it.** Each person keeps their own journal. Forever restricts addon-to-addon messages, so the two copies don't sync.

## Commands

| Command | What it does |
| --- | --- |
| `/kf` | Open or close the window |
| `/kf partner [name]` | Start a journey with your target, a named group member, or your only group member |
| `/kf status` | Show whether tracking is active and why |
| `/kf demo` | Add or remove a demo journey, to preview the window |
| `/kf minimap` | Show or hide the minimap button |
| `/kf toasts` | Turn milestone pop-ups on or off |
| `/kf reset` | Reset the journey shown in the window |
| `/kf records` | Switch the experimental hit and crit records on or off, on by default (`/kf records reset` clears them) |
| `/kf sync` | Send your journey to your friend now (`/kf sync off` and `on` switch the automatic syncing) |
| `/kf restore` | Put your journey back to how it was just before the last sync that changed something (asks first) |
| `/kf style wow` / `classic` | The game's own gold-and-stone look, or the original teal one (the default); asks to reload the interface |
| `/kf ping` | Test whether the addon can message your friend's copy (both need the same or a newer version) |
| `/kf debug` | Print every detected kill, loot and run to chat |

## Good to know

- **No combat log on Forever.** Addons can't read the combat log there, so kills come from the `PARTY_KILL` and `UNIT_DIED` events. A creature's type and rank are read while it's your target, a nameplate or your mouseover, so **keep enemy nameplates on** (default key: `V`). A kill of something never seen that way still counts, as "Unidentified".
- **Gold together** counts both of your shares: shared loot is split evenly, so the duo's part of each split pile is twice yours.
- **Storage** stays small. Counters are aggregated, and item names are stored once per item, not per drop.

## Known issues and limits

- **Syncing is new.** When you two meet, now and then while you play (only if something changed), and after a dungeon run, the copies exchange kills, quests, runs, bosses, rares, time together, killing blows, deaths, levels, loot counts by quality, kills by creature type, and each player's own best hit and crit (when the experimental records are on), and merge the lists of creatures hunted, rares, bosses, dungeons, zones and items found. Counters take the larger number and are never lowered; a list entry either copy has is added to the other, with the earlier first date and the later last date; nothing is ever deleted. Your journey is matched to your friend's by BattleTag and each chapter by the exact pair of characters (your "Krakenhood & Thalianne" is their "Thalianne & Krakenhood"), so chapters never mix; a chapter you don't have yet is added as it is. Before a sync changes anything the addon keeps a backup, and `/kf restore` puts it back. Both of you need the addon at the same or a newer version. Not synced: the journal (both copies already write the same events). The addon only sends while it is grouped with your journey partner, a few small messages at a time over the party channel (`/kf ping` tests that your friend's copy answers).
- **Quest counts can differ between two players.** The game only reports your own quest turn-ins, and a turn-in counts only while your partner is online and with you. If one of you logs off before the other hands in the same quest, the two counts differ by one until the next quest.
- **"Gold together" is an estimate.** Group loot is split evenly, so the duo total is counted as twice your share.
- **Creature types need a look at the creature.** A kill's type is read while it's your target, a nameplate or your mouseover. Anything never seen that way counts as "Unidentified".
- **One partner at a time.** Several journeys (one per friend) are supported, but only one partner is tracked at once, and the start-a-journey prompt appears only in a two-person group. Use `/kf partner Name` in bigger groups.
- **Hit and crit records are experimental on Forever (on by default).** Without a combat log, the game reports how much damage a creature took, its crit flag and its damage school, but not who dealt it, and the numbers cover anyone hitting a creature in view (a passing stranger included). They are a guess (`/kf records` switches them off): a hit is recorded only if one of you "claims" it, meaning you cast a spell a moment ago, have that creature targeted, and the spell's damage school fits the hit (a spell that names no school is physical). A hit that fits neither player's casts, like a stranger's or a pet's, is not recorded at all. Each copy only sees its own player's casts, so each records its own player; the sync hands your best hit and crit to your friend's copy for his column, one way only, so the two copies never overwrite each other. The middle is the better of the two. It still goes wrong when two of you use the same school at the same moment, or a stranger's hit has the school of a spell you just cast; auto-attacks, pets and damage over time aren't counted. It only counts while the group is exactly the two of you. `/kf records reset` clears the records. The Anniversary (TBC) version reads exact hits from the combat log and doesn't have this problem.
- **Untested at scale.** Verified with a headless test suite and by the author in the Forever beta; boss detection, heavy combat performance and unusual group setups haven't been tested widely. Bug reports are welcome in the issue tracker.

