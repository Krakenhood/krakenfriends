# Krakenfriends

A duo journey tracker for **World of Warcraft: Forever**. Turn it on, group up with your friend, and everything you do together is counted:

- **Kills** by creature type (humanoid, beast, undead, demon, …), elites, rares and bosses
- **Killing blows**, items looted and deaths as a friendly rivalry
- **Dungeon runs**: per dungeon, bosses, time inside, recent runs
- **Loot** by quality (gray to legendary), with names kept for green and better
- **Gold looted** together and your own share
- **Records**: the biggest hit and biggest crit in the fights you share ("Together", counted only while the group is just the two of you). On Forever, who dealt a hit can't be known, so the shared record is the reliable one; per-player columns for you and your friend are experimental there (`/kf records`). See Known issues
- **Trivia**: time together, quests, levels gained, zones explored, most hunted foe, toughest foe, favorite dungeon
- **Journal**: a timeline of firsts and milestones (first rare, first epic, 1,000 kills, new zones, levels, …)

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
| `/kf records` | Switch the experimental hit and crit records on or off (`/kf records reset` clears them) |
| `/kf ping` | Test whether the addon can message your friend's copy (both need the same or a newer version) |
| `/kf debug` | Print every detected kill, loot and run to chat |

## Good to know

- **No combat log on Forever.** Addons can't read the combat log there, so kills come from the `PARTY_KILL` and `UNIT_DIED` events. A creature's type and rank are read while it's your target, a nameplate or your mouseover, so **keep enemy nameplates on** (default key: `V`). A kill of something never seen that way still counts, as "Unidentified".
- **Gold together** counts both of your shares: shared loot is split evenly, so the duo's part of each split pile is twice yours.
- **Storage** stays small. Counters are aggregated, and item names are stored once per item, not per drop.

## Known issues and limits

- **No sync between players.** The two copies of the addon don't talk to each other; each player keeps their own journal. Addon-to-addon messages are possible in WoW (`C_ChatInfo.SendAddonMessage`), but the Forever beta reports outgoing addon messages as restricted, and it's untested whether they're actually blocked. A sync (for example your friend's exact gold) needs a test between two real clients first.
- **Quest counts can differ between two players.** The game only reports your own quest turn-ins, and a turn-in counts only while your partner is online and with you. If one of you logs off before the other hands in the same quest, the two counts differ by one until the next quest.
- **"Gold together" is an estimate.** Group loot is split evenly, so the duo total is counted as twice your share.
- **Creature types need a look at the creature.** A kill's type is read while it's your target, a nameplate or your mouseover. Anything never seen that way counts as "Unidentified".
- **One partner at a time.** Several journeys (one per friend) are supported, but only one partner is tracked at once, and the start-a-journey prompt appears only in a two-person group. Use `/kf partner Name` in bigger groups.
- **Per-player hit and crit records are unreliable on Forever (off by default).** Without a combat log, the game reports how much damage a creature took, its crit flag and its damage school, but not who dealt it, and this client can't see your friend's casts. So the **Together** record (the biggest hit or crit on any creature one of you is fighting, counted only while the group is exactly the two of you) is the one to trust; it can still include pet, passing strangers' and damage-over-time hits. The per-player columns are a guess from "cast a spell a moment ago with that creature targeted, in a damage school that fits": two players of the same school hitting at the same moment can't be told apart, and each copy of the addon may credit the same hit to its own player. They stay off unless you switch them on with `/kf records` (`/kf records reset` clears the records). The Anniversary (TBC) version reads exact hits from the combat log and doesn't have this problem.
- **Untested at scale.** Verified with a headless test suite and by the author in the Forever beta; boss detection, heavy combat performance and unusual group setups haven't been tested widely. Bug reports are welcome in the issue tracker.

