# Krakenfriends (TBC Anniversary)

A duo journey tracker for **World of Warcraft: Burning Crusade Anniversary** (client 2.5.6). Turn it on, group up with your friend, and everything you do together is counted:

- **Kills** by creature type (humanoid, beast, undead, demon, …), elites, rares and bosses
- **Killing blows**, items looted and deaths as a friendly rivalry
- **Dungeon runs**: per dungeon, with **heroics listed separately**, plus bosses, time inside and recent runs
- **Loot** by quality (gray to legendary), with names kept for green and better
- **Gold looted** together and your own share
- **Trivia**: time together, quests, levels gained, zones explored, most hunted foe, toughest foe, favorite dungeon
- **Journal**: a timeline of firsts and milestones (first rare, first epic, 1,000 kills, new zones, levels, …)

> This is the `tbc-anniversary` branch. The `master` branch holds the WoW: Forever version.

## Install

Copy the `Krakenfriends` folder (without `tests`) into `World of Warcraft\_anniversary_\Interface\AddOns\`, then type `/kf` in game or click the minimap button.

## How tracking works

- **Together means**: your partner is in your group, online, and either in sight (about 100 yards) or in the same zone. Nothing is counted while you're apart. The status line and the minimap pip show green (together), amber (grouped but apart), or nothing.
- **Kills**: from the combat log plus the `PARTY_KILL` / `UNIT_DIED` events. Any damage from you, your friend or your pets marks a mob as yours, so pet and DoT kills count too, and names come straight from the combat log.
- **Your characters**: all of your characters share one database, so your alts add up automatically.
- **Your friend's characters**: your friend is recognised by **BattleTag** through the Battle.net friends list, so their alts link up on their own. Someone who isn't a Battle.net friend is remembered by character name.
- **Chapters**: every pairing of characters (for example "Krakenhood & Thalianne", or your alt with theirs) is its own chapter, with its own counters, foes, rares, loot, dungeon runs, zones and journal. The window shows the whole journey (all chapters added up) by default. The **Characters** section on the Overview lists each chapter with its level range, kills, runs and time together: click one to filter the whole window to it, and click it again to go back. The selector at the top right does the same. In the combined view, tooltips and journal lines tell you which characters an entry came from.
- **More than one friend**: each friend gets their own journey. Switch between them with the same selector.
- **Both of you can install it.** Each person keeps their own journal.

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
| `/kf debug` | Print every detected kill, loot and run to chat |

## Good to know

- A creature's type and rank are read while it's your target, a nameplate or your mouseover, so **keep enemy nameplates on** (default key: `V`). A kill of something never seen that way still counts, as "Unidentified".
- **Gold together** counts both of your shares: shared loot is split evenly, so the duo's part of each split pile is twice yours.
- **Storage** stays small. Counters are aggregated, and item names are stored once per item, not per drop.

## Tests

`cd tests`, then `npm install` once and `npm test`. This runs the addon headlessly against a mock WoW API: it checks logic, not visuals.
