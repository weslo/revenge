# Revenge requirements

- Project/repository: `C:\Users\wesle\Documents\GitHub\revenge` (local; GitHub repo `revenge`, public, to be created by the agent once the user approves this plan)
- Updated: 2026-11-25, by Claude (planning session)
- Implementation matrix: [IMPLEMENTATION-MATRIX.md](IMPLEMENTATION-MATRIX.md)
- Original request: on a PvP realm, "when hovering an enemy on the opposing faction, [see] whether they've killed you or your friends or guildies recently, so you can get vengeance." Revenge Book does this but "the book interface etc is a little over complicated."
- Goal: a lightweight World of Warcraft: Forever addon that marks enemy players who recently killed you, a friend or a guildmate, mainly through their tooltip, with a few optional extras and plain settings.
- Scope boundaries:
  - No book-style window, scores, ranks, bounties or leaderboards.
  - Forever only. Open-world deaths only.
  - Must run alongside Revenge Book (which the user keeps) and luisjedev's "Revenge" addon without clashing.

## Requirements

| ID | Required behavior or constraint | Origin and source | Priority | Targets | Observable acceptance criteria | State |
|---|---|---|---|---|---|---|
| REQ-001 | When you die to enemy-faction players, record each enemy player in the death recap, marking the one with the killing blow. Store full name (Forever first and last name), realm, class, level, guild if seen, zone, map position and time. | User: original request. Detail: assumption (see Q-002) | 1 | forever | Die to an enemy player in the open world; the killer appears in the settings list with the zone and time | active |
| REQ-002 | Only open-world deaths count: never battlegrounds, arenas, dungeons, raids, scenarios or duels. | User: "Open world only" (2026-11-25) | 1 | forever | A battleground or dungeon death adds nothing; a duel loss adds nothing | active |
| REQ-003 | Hovering an enemy player with recent kills adds a summary line to the tooltip, e.g. "Killed you 2× · killed Bob, Alice". | User: original request | 1 | forever | Hover a recorded killer: the line appears. Hover anyone else: no line | active |
| REQ-004 | The tooltip also shows details of recent kills, up to 3 lines: victim, zone and how long ago. | User: "Details on recent kills in hover tooltip" | 1 | forever | A killer with 4 recent kills shows the 3 newest, then "+1 more" | active |
| REQ-005 | Share your deaths with guildmates, in-game friends and Battle.net friends who run the addon. | User: "Guild + all friends" (2026-11-25) | 2 | forever | A guildmate, an in-game friend and a Battle.net friend, each running Revenge, see your new death in their tooltips | active |
| REQ-006 | Merge deaths shared by others. Accept them only from current guildmates and friends; ignore duplicates; rate-limit senders; keep only killers hostile to you. | Assumption: shared data can be faked or flood; see DEC-008 | 2 | forever | A repeated message adds nothing; a message from a stranger is ignored | active |
| REQ-007 | Recent killers get a subtle mark beside their nameplate. | User: "Subtle nameplate mark" | 3 | forever | A recorded killer's nameplate shows a small icon; others show none | active |
| REQ-008 | Optional alert when a recent killer comes into view (nameplate, target or mouseover): one chat line and a sound, at most once every few minutes per player. | User: "Optional alerts for when an enemy is near" | 3 | forever | With the option on, a recorded killer coming into view alerts once; again only after the cooldown | active |
| REQ-009 | Optional alert when an enemy kills a friend or guildmate anywhere, as soon as their shared death arrives. | User: "...when an enemy kills a friend/guildie anywhere" | 3 | forever | With the option on, a friend's shared death shows one chat line naming victim, killer and zone | active |
| REQ-010 | World map pins at the death locations of recent kills on you, friends and guildmates. Hovering a pin shows who died, the killer and when. | User: "Simple map pins for kills on you or friends/guildies" | 3 | forever | Open the world map in a zone with a recent death: a pin is at the spot; its tooltip names the victim and killer | active |
| REQ-011 | A simple editable list of recent killers in the plain settings menu: see entries and remove them (add-by-hand pending Q-003). | User: "Simple editable list in a plain settings menu" | 2 | forever | Remove an entry in settings: its tooltip line, nameplate mark and pins disappear | active |
| REQ-012 | Kills expire from tooltips, marks, alerts and pins after 7 days by default, adjustable in settings. | User: "7 days default + config in plain settings" | 1 | forever | A kill older than the setting no longer shows. Changing the setting takes effect without `/reload` | active |
| REQ-013 | Plain settings in Options > AddOns > Revenge: the expiry, sharing per channel (guild, friends, Battle.net), tooltip details, nameplate mark, both alerts, map pins, and the list. | User: "plain settings". Suite baseline: options | 1 | forever | Every option above is in the game's AddOns settings, persists across `/reload`, and has a working default | active |
| REQ-014 | All text comes from one English locale table with an English fallback, so translations can be added later. No other languages in the first release. | Assumption, from the suite's localization baseline (user can change) | 2 | forever | No visible text is hard-coded outside the locale file | active |
| REQ-015 | No clashes with other addons: own folder, saved-variable names, slash command, global names and addon-message prefix (see Q-001). | Assumption: luisjedev's Revenge already uses folder `Revenge` and `RevengeDB` | 1 | forever | Revenge, Revenge Book and luisjedev's Revenge load together with no errors or shared data | active |
| REQ-016 | Forever only (interface 16001), released on GitHub with a `release.json` so instawow installs it as `github:<owner>/revenge`. | User: GitHub-first, instawow (earlier sessions) | 2 | forever | `instawow install github:<owner>/revenge` installs the release; the game lists it as compatible | active |
| REQ-017 | Respect Forever's restricted values. Never compare, store or send secret values. When an enemy's identity is hidden, skip them quietly. | Suite: secret-value gate; `UnitGUID` is SecretWhenUnitIdentityRestricted on Forever | 1 | forever | No Lua errors or taint in Bugsy during PvP; restricted units show no line rather than an error | active |
| REQ-018 | Lightweight: no window beyond the settings panel, no bundled libraries unless a requirement needs one, low memory and CPU. | User: wants something simpler than Revenge Book | 1 | forever | Folder well under 300 KB; no noticeable frame-time cost in a busy zone | active |

## Target and API evidence

| Target | Intended client/build/interface | Source commit and evidence | Related REQ IDs | Loading/access/runtime uncertainty |
|---|---|---|---|---|
| forever | 1.60.1.70938 / interface 16001 | Gethe/wow-ui-source `forever` at `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`, via the `wow-api-index` query tool (2026-11-25) | all | Declarations prove existence only. Runtime proof comes from Revenge Book v1.6.4 (installed) and The Terminal List, which use the same calls on Forever |
| forever | as above | Found: `C_DeathRecap.GetRecapEvents`, `PLAYER_DEAD`, `C_ChatInfo.RegisterAddonMessagePrefix` / `SendAddonMessage`, `CHAT_MSG_ADDON`, `C_BattleNet.SendGameData`, `BN_CHAT_MSG_ADDON`, `C_Map.GetBestMapForUnit` / `GetPlayerMapPosition`, `C_NamePlate.GetNamePlateForUnit` | 001, 005, 007, 010 | `UnitGUID` takes `UnitTokenPvPRestrictedForAddOns` and is `SecretWhenUnitIdentityRestricted`: probe in open-world PvP |
| forever | as above | Not in the generated index (FrameXML): `TooltipDataProcessor`, world-map pin templates | 003, 004, 010 | Confirm in the loaded FrameXML and with Revenge Book's working code |

## UI and accepted design

- Mock-up choice and source: **mock-up first** (user, 2026-11-25).
- Accepted design: none yet. The mock-up for review is canvas version 6 (2026-11-25): source in [mockup/](mockup/README.md), live at the private artifact https://claude.ai/artifact/9M4d6XpfKVF8XftFNd8Ncs. It covers the tooltip lines, nameplate mark, settings list, both alerts and map pins, with tweaks for Q-002 (killer rule), Q-003 (add by name) and the mark style.
- Defaults shown in the mock-up, to confirm: 7 days; details, nameplate mark, map pins, both alerts, the alert sound and all three sharing channels on. The killer-nearby alert repeats at most once every 5 minutes per player.
- Relevant REQ IDs: 003, 004, 007–011, 013.
- Style: the game's own tooltip, settings and map-pin look; subtle, no custom skin.

## Options-menu integration and localization (baseline requirements)

- Options discovery: one category "Revenge" in Options > AddOns; `/revenge` opens it.
- Settings lifecycle: account-wide saved variables `RevengeTrackerDB` (name pending Q-001) with defaults and a version field for migrations. Changes apply at once; a reset-to-defaults button.
- Locale architecture: `Locales/enUS.lua` as the base catalog; other locales would override keys, falling back to English.
- Translation coverage: English only (REQ-014).
- Acceptance: REQ-013, REQ-014.

## Controller interaction assessment (required for UI changes)

| UI element or control group | Role | Controller path and visible cues | Target evidence / gaps | Acceptance or explicit user exclusion |
|---|---|---|---|---|
| Tooltip lines, nameplate mark, chat alerts | passive | Not interactive. They appear with the game's own tooltip, nameplates and chat, whatever the input | none | not applicable |
| Settings controls and list | interactive | Built from the game's native settings controls, which carry the settings panel's own gamepad focus and navigation | Confirm the remove button is reachable with a gamepad on Forever | pending check (no controller confirmed) |
| Map pins | passive with hover | Shown on the game's world map; hover details follow the map's own cursor handling | gamepad hover on map pins unverified | pending check |

- Input modes/devices to exercise: mouse and keyboard; gamepad only if the user has one.
- Bindings/settings to preserve: none (the addon adds no key bindings).

## Testing preference

- Route and source: pending, to be asked at testing time. The likely route: the user plays, Bugsy (installed 2026-11-25) catches errors, and the agent reads Bugsy's saved errors and screenshots. Witchcraft is not set up.
- Remaining real-client checks: everything marked in-game in the matrix. Sharing needs a second person or account on the user's guild or friends list. Kill checks need real open-world PvP deaths; a debug-only command will inject sample data for the tooltip, list and pins.
- Controller checks: pending (see above).

## Open questions and assumptions

| ID | Question or assumption | Related REQ IDs | Impact / independent work available | Resolution and source |
|---|---|---|---|---|
| Q-001 | The name the player sees is "Revenge". The internal name is `RevengeTracker` (folder, saved variables, globals), the slash command `/revenge`, and the message prefix `RVNG1`, avoiding luisjedev's `Revenge` folder and `RevengeDB`. Acceptable? | 015, 016 | Blocks the first code slice only | pending (user) |
| Q-002 | Who counts as "the killer": proposal is every enemy player in the death recap, with the killing blow marked. The alternative is the killing blow only. | 001, 003 | Affects tooltip wording; settle in the mock-up | pending (user) |
| Q-003 | Should the settings list also allow adding an enemy by name? (Default: view and remove only.) | 011 | Settle in the mock-up | pending (user) |
| Q-004 | Should Revenge also read Revenge Book's shared messages, so friends using Revenge Book count too? (Default: no; its protocol is undocumented and may change.) | 005, 006 | Later; not in the first release | pending (user) |
| Q-005 | A shared death whose killer is on your own faction (from a Battle.net friend on the other faction) is dropped. | 006 | Implementation detail | assumption (DEC-008) |
| Q-006 | Nameplate mark style: skull, crosshair or dot (the mock-up's tweak)? | 007 | Settle in the mock-up | pending (user) |
| Q-007 | Defaults: everything on (see "UI and accepted design"), or some alerts or sharing channels off by default? | 008, 009, 013 | Settle in the mock-up | pending (user) |

## Decisions and scope changes

| ID / date | Source | Decision or change | Affected REQ IDs | Consequence / successor / checks to repeat |
|---|---|---|---|---|
| DEC-001 / 2026-11-25 | User | Bugsy (`github:Spotnick2/Bugsy`) is the in-game error catcher, instead of BugSack (whose !BugGrabber instawow can't install) | testing | Read errors from `BugsyDB` after `/reload` |
| DEC-002 / 2026-11-25 | User | Share with guild, in-game friends and Battle.net friends | 005, 006 | Three message paths to test |
| DEC-003 / 2026-11-25 | User | Expiry 7 days by default, adjustable | 012 | none |
| DEC-004 / 2026-11-25 | User | Open-world deaths only | 002 | none |
| DEC-005 / 2026-11-25 | User | Name "revenge"; a public GitHub repo, created by the agent once this plan is approved | 015, 016 | See Q-001 for internal names |
| DEC-006 / 2026-11-25 | User | Mock-up before implementation | UI REQs | Mock-up is the next step |
| DEC-007 / 2026-11-25 | User (earlier) | Keep Revenge Book installed alongside | 015 | Test both loaded together |
| DEC-008 / 2026-11-25 | Implementation | Trust rules for shared data: only from guildmates and friends, deduplicated, rate-limited, hostile killers only | 006 | Revisit if friends report missing deaths |

## Completion criteria

- Every active REQ row is implemented and verified in the matrix, or explicitly deferred by the user.
- In-game acceptance by the user on Forever 1.60.1: open-world deaths recorded; tooltip, nameplate, alerts and pins correct; sharing confirmed with at least one guildmate or friend over each channel used; no errors in Bugsy.
- Installs from the GitHub release through instawow.
