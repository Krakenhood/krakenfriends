# Krakenfriends

A duo journey tracker for **World of Warcraft: Forever**. Turn it on, group up with your friend, and everything you do together is counted:

- **Kills** by creature type (humanoid, beast, undead, demon, …), elites, rares and bosses
- **Killing blows**, items looted and deaths as a friendly rivalry
- **Dungeon runs**: per dungeon, bosses, time inside, recent runs
- **Loot** by quality (gray to legendary), with names kept for green and better
- **Gold looted** together and your own share
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
| `/kf debug` | Print every detected kill, loot and run to chat |

## Good to know

- **No combat log on Forever.** Addons can't read the combat log there, so kills come from the `PARTY_KILL` and `UNIT_DIED` events. A creature's type and rank are read while it's your target, a nameplate or your mouseover, so **keep enemy nameplates on** (default key: `V`). A kill of something never seen that way still counts, as "Unidentified".
- **Gold together** counts both of your shares: shared loot is split evenly, so the duo's part of each split pile is twice yours.
- **Storage** stays small. Counters are aggregated, and item names are stored once per item, not per drop.

## Beta safety net (beta only)

The Forever beta (1.60.x) writes SavedVariables to disk but **does not load them back** on the next launch: a known beta bug. Until it's fixed:

1. Play as usual and log out normally.
2. **Before the next launch**, double-click `tools\Restore-Journey.cmd`. It copies your latest save into the addon as `Restore.lua`, which Krakenfriends loads at login. Every save it sees is also kept in `WTF\Krakenfriends-Backups`.

Krakenfriends also mirrors its data per character, so a `/reload` inside one session keeps your progress even on the beta. On the live game none of this is needed: the newest save always wins. If you carry the addon over from the beta and want a fresh start on live, clear out `Restore.lua` first (leave the file, empty it).
