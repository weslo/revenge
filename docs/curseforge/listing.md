# CurseForge listing

Revenge is on CurseForge as **Easy Revenge**, project ID **1836789**
(https://www.curseforge.com/wow/addons/easy-revenge, visible once a moderator approves it).
This is what the listing says, for editing it later in CurseForge's author dashboard.
The logo is [logo.png](logo.png), 400×400 as CurseForge asks, drawn by `tools/make_logo.py`.

## Name

**Easy Revenge**, slug `easy-revenge`. It says what the addon is meant to be: the easiest,
simplest, most automatic social revenge tracker. In game it's still called "Revenge", and its
folder is `RevengeTracker`.

"Revenge" and "Revenge Tracker" were both taken on CurseForge. CurseForge also rejects a name with
a version or the game's name in it. The name and slug can be changed later on the project's
**General** tab.

## Summary

> See who killed you, your friends and your guildmates right on their tooltip, tracked and shared automatically in WoW: Forever.

One sentence, as CurseForge prefers.

## Categories

PvP as the main category, with Map & Minimap and Tooltip as extras (up to four).

## License and distribution

- **License:** MIT License, matching [LICENSE](../../LICENSE).
- **Distribution:** allow distribution to 3rd party, so other addon managers can offer it too.

## Source

The GitHub link is https://github.com/weslo/revenge, with issues at
https://github.com/weslo/revenge/issues. Comments on CurseForge are off.

## The first file

CurseForge reviews a new project only once it has a file. Upload the newest release's zip
(`Revenge-v0.5.0-forever.zip` as of v0.5.0, from https://github.com/weslo/revenge/releases/latest) on
the project's **Files** tab:
- **Game version:** WoW Forever, 1.60.1.
- **Release type:** Release.
- **Changelog:** that version's section of [CHANGELOG.md](../../CHANGELOG.md).

## Later releases

Each pushed version tag uploads to CurseForge from CI, after the GitHub release
(`.github/workflows/build.yml`). The packager reads the project from `## X-Curse-Project-ID` in
`RevengeTracker/RevengeTracker.toc`. It needs a CurseForge API token, which the owner creates at
https://authors.curseforge.com/#/settings/api-tokens and stores as the repository secret
`CF_API_TOKEN`; without it, the upload is skipped. Don't also turn on CurseForge's own packaging
webhook, or each release would be uploaded twice.

## Description

Paste the text below in the description's Markdown mode. Each paragraph and list item is one
line, because CurseForge's Markdown shows every line break.

---

**Easy Revenge** (just "Revenge" in game) is the simplest way to track world PvP revenge in **World of Warcraft: Forever**. There's nothing to set up: it records who killed you, shares it with your guild and friends automatically, and shows it right on the enemy's tooltip.

> ☠ (3) You, Mira, Tavish

It's early and being tested by a small group. Reports are welcome on [GitHub](https://github.com/weslo/revenge/issues).

### What it does

- **Your deaths:** when an enemy player kills you in the open world, Revenge records who did it, from the game's death recap. Deaths in dungeons, raids and battlegrounds aren't recorded.
- **The tooltip:** an enemy's tooltip shows how many recent deaths they caused and whose. Hold **Shift** for the details: who, where and how long ago.
- **Wanted:** mark a player Wanted with `/revenge add First Last` or from the settings. Your guildmates and friends running Revenge see "Wanted by" your name.
- **Sharing:** your deaths and Wanted marks reach guildmates, in-game friends and Battle.net friends who run Revenge, and theirs reach you. When you log in, they send what you missed.
- **Alerts:**
  - when a recent killer or a Wanted player comes into view;
  - when an enemy kills a friend or guildmate.

  Each shows as a small, silent popup that fades by itself, and in chat.
- **Nameplates:** a small skull beside a recent killer's nameplate. The nameplate itself is left alone, whether it's the game's or another addon's.
- **The world map:** skulls where recent deaths happened: coral for you, blue for friends, yellow for guildmates. Hover one for who and when, or right-click it to dismiss that kill.
- **Other PvP addons:** what guildmates and friends share through **Revenge Book**, **Grudgekeeper** or **HeadHunter** counts too, and so does your own **Kill on Sight** list. Each death still counts once, however many addons reported it.

### Settings

Everything is under **Options › AddOns › Revenge**:
- how long kills show (7 days by default);
- the details key;
- the skulls, the map, each alert;
- each sharing channel, each other addon;
- a list of recent killers, where you can add or remove players.

`/revenge` opens it.

### What it shares, and with whom

- **What's shared:** only what's yours: your own deaths (who killed you, where and when) and the players you marked Wanted. Nothing is passed on second-hand, and each channel can be switched off.
- **Who it's shared with:** guildmates, and friends who run Revenge. Nothing comes from or goes to strangers.
- **Other addons:** their data is optional, and it's never passed on. If one of them changes its format and stops making sense, Revenge quietly stops reading it for the session.

### Install

The download holds two folders:
- **`RevengeTracker`** is Revenge itself.
- **`RevengeTracker_OtherAddons`** is optional. It reads other addons' data, and Revenge loads it only while "Use data from other addons" is on.

### Commands

- `/revenge` opens the settings.
- `/revenge add First Last` marks a player Wanted by you.
- `/revenge others` shows which other addons' data is in use; add `on` or `off` to switch it.
- `/revenge log on` keeps a diagnostic log to look at later; `off` stops it and `clear` empties it.
- `/revenge test` records a test kill by your target.
- `/revenge test share` records one and sends it to your guild.
- `/revenge test clear` removes test kills.
