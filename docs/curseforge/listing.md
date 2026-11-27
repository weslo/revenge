# CurseForge listing (draft)

What to enter when creating the project in CurseForge's author dashboard (World of Warcraft).
The logo is [logo.png](logo.png), drawn by `tools/make_logo.py`.

## Name

**Revenge Tracker** is suggested. "Revenge" alone may already be taken on CurseForge (luisjedev's
"Revenge" addon), and the addon's folder is `RevengeTracker`. In game it's still called "Revenge".

## Summary

> See who killed you, your friends and your guildmates, right on their tooltip. For WoW: Forever.

## Categories

PvP as the main category. Tooltip and Map & Minimap fit as extras, if the dashboard offers them.

## License

The repository has no license yet, so pick one:
- **All Rights Reserved** keeps every right.
- **MIT** lets others reuse the code freely.

Whichever you pick, a LICENSE file in the repository should match.

## Source

https://github.com/weslo/revenge, with issues at https://github.com/weslo/revenge/issues.

## Description

Paste the text below in the description's Markdown mode.

---

**Revenge** is a lightweight, tooltip-first revenge tracker for **World of Warcraft: Forever**. When
you hover an enemy player, it tells you whether they recently killed you, a friend or a guildmate.

> ☠ (3) You, Mira, Tavish

It's early and being tested by a small group. Reports are welcome on
[GitHub](https://github.com/weslo/revenge/issues).

### What it does

- **Your deaths:** when an enemy player kills you in the open world, Revenge records who did it,
  from the game's death recap. Deaths in dungeons, raids and battlegrounds aren't recorded.
- **The tooltip:** an enemy's tooltip shows how many recent deaths they caused and whose. Hold
  **Shift** for the details: who, where and how long ago.
- **Wanted:** mark a player Wanted with `/revenge add First Last` or from the settings. Your
  guildmates and friends running Revenge see "Wanted by" your name.
- **Sharing:** your deaths and Wanted marks reach guildmates, in-game friends and Battle.net friends
  who run Revenge, and theirs reach you. When you log in, they send what you missed.
- **Alerts:**
  - when a recent killer or a Wanted player comes into view;
  - when an enemy kills a friend or guildmate.

  Each shows as a small, silent popup that fades by itself, and in chat.
- **Nameplates:** a small skull beside a recent killer's nameplate. The nameplate itself is left
  alone, whether it's the game's or another addon's.
- **The world map:** skulls where recent deaths happened: coral for you, blue for friends, yellow
  for guildmates. Hover one for who and when, or right-click it to dismiss that kill.
- **Other PvP addons:** what guildmates and friends share through **Revenge Book**,
  **Grudgekeeper** or **HeadHunter** counts too, and so does your own **Kill on Sight** list. Each
  death still counts once, however many addons reported it.

### Settings

Everything is under **Options › AddOns › Revenge**:
- how long kills show (7 days by default);
- the details key;
- the skulls, the map, each alert;
- each sharing channel, each other addon;
- a list of recent killers, where you can add or remove players.

`/revenge` opens it.

### What it shares, and with whom

- **What's shared:** only what's yours: your own deaths (who killed you, where and when) and the
  players you marked Wanted. Nothing is passed on second-hand, and each channel can be switched off.
- **Who it's shared with:** guildmates, and friends who run Revenge. Nothing comes from or goes to
  strangers.
- **Other addons:** their data is optional, and it's never passed on. If one of them changes its
  format and stops making sense, Revenge quietly stops reading it for the session.

### Install

The download holds two folders:
- **`RevengeTracker`** is Revenge itself.
- **`RevengeTracker_OtherAddons`** is optional. It reads other addons' data, and Revenge loads it
  only while "Use data from other addons" is on.

### Commands

- `/revenge` opens the settings.
- `/revenge add First Last` marks a player Wanted by you.
- `/revenge others` shows which other addons' data is in use; add `on` or `off` to switch it.
- `/revenge log on` keeps a diagnostic log to look at later; `off` stops it and `clear` empties it.
- `/revenge test` records a test kill by your target.
- `/revenge test share` records one and sends it to your guild.
- `/revenge test clear` removes test kills.
