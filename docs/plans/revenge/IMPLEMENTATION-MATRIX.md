# Revenge implementation matrix

- Requirements: [REQUIREMENTS.md](REQUIREMENTS.md)
- Integration owner: Claude (the session building the addon)
- Updated: 2026-11-25, planning
- Evidence directory: `docs/plans/revenge/evidence/` (screenshots, Bugsy exports, test notes)

## Implementation coverage

| Row | REQ IDs | Target(s) | Slice / observable result | Dependencies / order | Owner | Implementation files | Status | Validation IDs / remaining work |
|---|---|---|---|---|---|---|---|---|
| IMP-001 | 013, 014, 015, 016, 018 | forever | S01: the addon loads; saved data with defaults; English locale table; empty "Revenge" settings category; `/revenge` opens it | Q-001 answered; mock-up accepted | Claude | `RevengeTracker.toc`, `Core.lua`, `Locales/enUS.lua`, `Settings.lua` | planned | V-001, V-002 |
| IMP-002 | 001, 002, 017 | forever | S02: an open-world death records the enemy players from the death recap; instance and duel deaths are ignored; a debug-only command injects sample deaths | IMP-001 | Claude | `Deaths.lua`, `Store.lua` | planned | V-001, V-003 |
| IMP-003 | 003, 004, 012 | forever | S03: hovering a recorded enemy shows the summary and up to 3 detail lines, respecting expiry | IMP-002 | Claude | `Tooltip.lua` | planned | V-001, V-004 |
| IMP-004 | 011, 012, 013 | forever | S04: settings show the expiry slider and the list of recent killers with a remove button | IMP-002 | Claude | `Settings.lua`, `List.lua` | planned | V-001, V-005 |
| IMP-005 | 005, 006 | forever | S05: guild sharing; send own deaths, receive guildmates', deduplicate, rate-limit | IMP-002 | Claude | `Share.lua`, `Protocol.lua` | planned | V-001, V-006 |
| IMP-006 | 005, 006 | forever | S06: in-game friends (whisper) and Battle.net friends (game data), with a hello so only friends running Revenge are messaged | IMP-005 | Claude | `Share.lua` | planned | V-001, V-007 |
| IMP-007 | 009 | forever | S07: optional chat alert when a shared death arrives | IMP-005 | Claude | `Alerts.lua` | planned | V-001, V-008 |
| IMP-008 | 007 | forever | S08: subtle nameplate mark on recent killers | IMP-002 | Claude | `Nameplates.lua` | planned | V-001, V-009 |
| IMP-009 | 008 | forever | S09: optional alert when a recent killer comes into view, with a per-player cooldown | IMP-008 | Claude | `Alerts.lua` | planned | V-001, V-010 |
| IMP-010 | 010 | forever | S10: world map pins at recent death locations, with hover details | IMP-002 | Claude | `MapPins.lua` | planned | V-001, V-011 |
| IMP-011 | 016 | forever | S11: GitHub Actions release with the BigWigs packager (zip plus `release.json`); install through instawow | IMP-001 | Claude | `.github/workflows/release.yml`, `.pkgmeta` | planned | V-012 |

Statuses: `planned`, `in progress`, `implemented`, `verified`, `blocked`, `deferred`, `superseded`.

## Validation evidence

| ID | REQ IDs / slice | Target and observed build | Mode | Exact addon revision / dirty-state reference | Procedure / fixture and expected result | Observed result / evidence path | Status |
|---|---|---|---|---|---|---|---|
| V-001 | all / every slice | forever; n/a | static | per slice | `luacheck` with a `.luacheckrc` for WoW globals: 0 warnings. A Lua 5.1 syntax scan for `//`, `goto`, `::label::`, `bit32`, `table.pack` and `utf8` (luacheck 1.2.0 parses newer Lua, so it doesn't catch these). Check the TOC file list | | not run |
| V-002 | 013, 014, 015 / S01 | forever 1.60.1 | in-game | | Load with Revenge Book and luisjedev's Revenge enabled; open Options > AddOns > Revenge; `/reload`; no Bugsy errors | | not run |
| V-003 | 001, 002, 017 / S02 | forever 1.60.1 | in-game | | Open-world PvP death: entry recorded. Dungeon or battleground death and a duel: nothing recorded. Bugsy clean | | not run |
| V-004 | 003, 004, 012 / S03 | forever 1.60.1 | in-game | | With sample data, hover the killer: summary and details lines; expire one: line gone | | not run |
| V-005 | 011, 012, 013 / S04 | forever 1.60.1 | in-game | | Remove an entry in settings: gone from tooltip, marks and pins; settings persist across `/reload` | | not run |
| V-006 | 005, 006 / S05 | forever 1.60.1 | in-game, 2 clients | | Guildmate dies: entry arrives once; a repeat send is ignored | | not run |
| V-007 | 005, 006 / S06 | forever 1.60.1 | in-game, 2 clients | | Same with an in-game friend and a Battle.net friend | | not run |
| V-008 | 009 / S07 | forever 1.60.1 | in-game | | Shared death with alert on: one chat line; off: none | | not run |
| V-009 | 007 / S08 | forever 1.60.1 | in-game | | Recorded killer's nameplate shows the mark; it updates on removal and expiry | | not run |
| V-010 | 008 / S09 | forever 1.60.1 | in-game | | Recorded killer comes into view: one alert; no repeat within the cooldown | | not run |
| V-011 | 010 / S10 | forever 1.60.1 | in-game | | World map shows pins at sample death positions, with hover details | | not run |
| V-012 | 016 / S11 | forever 1.60.1 | install | | Tag a release; `instawow install github:<owner>/revenge` installs it; AddOns list shows it compatible | | not run |

Validation statuses: `pass`, `fail`, `not run`, `not applicable` (with reason), `stale`.

## Blocked, deferred or replaced work

| REQ / row IDs | State | Cause or scope decision / source | Next action and owner | Effect on delivery |
|---|---|---|---|---|
| all IMP rows | waiting | Mock-up first (DEC-006); internal name pending (Q-001) | Claude builds the mock-up; user reviews it and answers Q-001 to Q-003 | No code until then |

## Resume checkpoint

- Updated by / at: Claude, 2026-11-25 (planning)
- Repository / branch: `C:\Users\wesle\Documents\GitHub\revenge`; not yet a git repository; GitHub repo not yet created
- Exact HEAD revision: no commit
- Working tree: `docs/plans/revenge/REQUIREMENTS.md` and `IMPLEMENTATION-MATRIX.md` only
- Last completed slice: none
- Last verified state: none
- Current slice and pending edits: none
- Next executable action: build the UI mock-up (REQ-003, 004, 007–011, 013) with sample data; get the user's acceptance and answers to Q-001 to Q-003; then `git init`, create the public GitHub repo with `gh repo create`, commit the plan, and start IMP-001
- Open questions / blockers: Q-001 (blocks IMP-001), Q-002, Q-003 (settle in the mock-up), Q-004 (later)
- Decisions to retain: DEC-001 to DEC-008
- Testing choice: pending; Bugsy installed for error capture
- Controller assessment: settings list and map pins pending checks; everything else passive
- Options/localization: REQ-013 and REQ-014; English only
- Read next: REQUIREMENTS.md (requirements, open questions), this checkpoint, then the accepted mock-up
- Drift since verification: none

## Coverage reconciliation

- Requirements missing matrix rows: none (REQ-017 and REQ-018 are cross-cutting and checked in V-001 and V-003)
- Implemented requirements awaiting acceptance: none
- Unresolved target-specific gaps: `UnitGUID` identity restriction in PvP (REQ-017); `TooltipDataProcessor` and map-pin templates not in the generated index
- Remaining requested work: all
