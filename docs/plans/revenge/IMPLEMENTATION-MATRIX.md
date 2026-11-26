# Revenge implementation matrix

- Requirements: [REQUIREMENTS.md](REQUIREMENTS.md)
- Integration owner: Claude (the session building the addon)
- Updated: 2026-11-25, planning
- Evidence directory: `docs/plans/revenge/evidence/` (screenshots, Bugsy exports, test notes)

## Implementation coverage

| Row | REQ IDs | Target(s) | Slice / observable result | Dependencies / order | Owner | Implementation files | Status | Validation IDs / remaining work |
|---|---|---|---|---|---|---|---|---|
| IMP-001 | 013, 014, 015, 016, 018 | forever | S01: the addon loads; saved data with defaults and validation; English locale table; "Revenge" settings category with the expiry slider and details-key dropdown; `/revenge` opens it | Q-001 answered; mock-up accepted | Claude | `RevengeTracker/RevengeTracker.toc`, `Core.lua`, `Store.lua`, `Locales/enUS.lua`, `Settings.lua` | verified | V-001 pass; V-002 pass |
| IMP-002 | 001, 002, 017 | forever | S02: an open-world death records the hostile players from the death recap (retried at 0.3, 1 and 2.5 s; same-faction players skipped); instance deaths ignored. `/revenge test` records a test kill by the current target; `/revenge test clear` removes them. Kills by pets alone aren't counted yet | IMP-001 | Claude | `RevengeTracker/Deaths.lua` | implemented | V-001 pass; V-003 not run |
| IMP-013 | 024, 025, 001 | forever | S13: the core source layer: normalized kill records, name cache (GUID → full name, class, level, guild, faction; from target, mouseover and nameplates), merge with deduplication and tombstones (own data wins), and the validating `SubmitForeign` door (`RevengeTracker.SubmitForeign`). Revenge's own deaths flow through it. The trust filter and the own-protocol source (`Sources/Revenge.lua`) arrive with sharing in S05 | IMP-002 | Claude | `RevengeTracker/Identity.lua`, `Merge.lua`, `Foreign.lua`, `Store.lua` | implemented (trust filter: S05) | V-001 pass; V-014 pass offline |
| IMP-018 | 030, 032 | forever | S18: the optional module `RevengeTracker_OtherAddons`: load on demand behind the master switch, prefix routing, pre-checks, bounded queue with a 0.5 ms/frame budget, combat pause, silent `pcall`, per-adapter circuit breaker, status lines; tested with deliberately broken fake adapters | IMP-013, IMP-004, IMP-011 | Claude | `RevengeTracker_OtherAddons/*.toc`, `Host.lua`, `Queue.lua`, `Breaker.lua`; core `Settings.lua` | planned | V-001, V-019 |
| IMP-003 | 003, 004, 012, 021 | forever | S03: hovering a recorded enemy shows the one skull line "(N) You, …, +N more"; holding the details key (Shift by default) adds up to 5 lines (victim · zone · time ago) and redraws on key change; expiry respected. The "Wanted by" line comes with S04 | IMP-013 | Claude | `RevengeTracker/Tooltip.lua` | verified (Wanted line: S04) | V-001 pass; V-004 pass |
| IMP-004 | 011, 012, 013, 021 | forever | S04: settings show the expiry slider, the modifier choice, and the list of recent killers with remove and add-by-name (which marks the player "Wanted by you") | IMP-002 | Claude | `Settings.lua`, `List.lua` | planned | V-001, V-005 |
| IMP-005 | 005, 006, 021 | forever | S05: guild sharing; send own deaths and Wanted players, receive guildmates', deduplicate, rate-limit; catch-up on login if Q-010 is accepted | IMP-002, IMP-004 | Claude | `Share.lua`, `Protocol.lua` | planned | V-001, V-006 |
| IMP-006 | 005, 006, 021 | forever | S06: in-game friends (whisper) and Battle.net friends (game data), with a hello so only friends running Revenge are messaged | IMP-005 | Claude | `Share.lua` | planned | V-001, V-007 |
| IMP-007 | 009 | forever | S07: optional chat alert when a shared death arrives | IMP-005 | Claude | `Alerts.lua` | planned | V-001, V-008 |
| IMP-008 | 007 | forever | S08: skull beside recent killers' nameplates, anchored to whichever nameplate is showing (game default or an addon's), never restyling it | IMP-002 | Claude | `Nameplates.lua` | planned | V-001, V-009 |
| IMP-009 | 008 | forever | S09: optional alert when a recent killer comes into view, with a per-player cooldown | IMP-008 | Claude | `Alerts.lua` | planned | V-001, V-010 |
| IMP-010 | 010, 020 | forever | S10: skull pins on the world map at recent death locations, coloured by group, with hover details and right-click "Dismiss kill" | IMP-002 | Claude | `MapPins.lua` | planned | V-001, V-011 |
| IMP-012 | 019 | forever | S12: the silent alert popup for both alerts: fades after about 4 seconds or on a click | IMP-007, IMP-009 | Claude | `Popup.lua` | planned | V-001, V-013 |
| IMP-014 | 026 | forever | S14: Revenge Book adapter: guild `K`/`R`/`L`/`M`/`X` and time-sliced read-only `DeathNoteDB` import | IMP-018 | Claude | `RevengeTracker_OtherAddons/Adapters/RevengeBook.lua` | planned | V-001, V-015 |
| IMP-015 | 027 | forever | S15: Grudgekeeper adapter: guild `D` and `C`/`O` kill orders, with chunk reassembly | IMP-014 | Claude | `RevengeTracker_OtherAddons/Adapters/Grudgekeeper.lua` | planned | V-001, V-016 |
| IMP-016 | 028 | forever | S16: HeadHunter adapter: party/raid and whispered `D` (with envelopes) from guildmates and friends; `HeadHunter_DB` while loaded | IMP-014 | Claude | `RevengeTracker_OtherAddons/Adapters/HeadHunter.lua` | planned | V-001, V-017 |
| IMP-017 | 029 | forever | S17: Kill on Sight adapter: KoS list from `KillOnSightDB` as Wanted marks | IMP-014 | Claude | `RevengeTracker_OtherAddons/Adapters/KillOnSight.lua` | planned | V-001, V-018 |
| IMP-011 | 016 | forever | S11: GitHub Actions release with the BigWigs packager (zip plus `release.json`); install through instawow | IMP-001 | Claude | `.github/workflows/release.yml`, `.pkgmeta` | planned | V-012 |

Build order (DEC-019, DEC-020: other addons last):
- **Core:** S01 skeleton → S02 recording → S13 core source layer → S03 tooltip → S04 settings list → S05 guild sharing and catch-up → S06 friends and Battle.net → S07 friend-killed alert → S08 nameplate skull → S09 nearby alert → S10 map pins → S12 popup.
- **First release:** S11, with no other-addon code.
- **Other addons:** S18 optional module → S14 Revenge Book → S15 Grudgekeeper → S16 HeadHunter → S17 Kill on Sight. Each adapter is built only if the previous one proved worth it.

Statuses: `planned`, `in progress`, `implemented`, `verified`, `blocked`, `deferred`, `superseded`.

## Validation evidence

| ID | REQ IDs / slice | Target and observed build | Mode | Exact addon revision / dirty-state reference | Procedure / fixture and expected result | Observed result / evidence path | Status |
|---|---|---|---|---|---|---|---|
| V-001 | all / every slice | forever; n/a | static | S01–S03 on `dev/core-s01-s03` | `luacheck .` with `.luacheckrc` (WoW globals): 0 warnings. `python -I tools/check_lua51.py` flags `//`, `goto`, labels, `bit32`, `table.pack`, `utf8` and bitwise operators (luacheck 1.2.0 parses newer Lua, so it misses these; the scanner was self-tested on a file with 5 known problems). Check the TOC file list | S01–S03: luacheck 0 warnings / 0 errors in 9 files; scanner 0 problems; TOC lists all 9 files (2026-11-25) | pass (S01–S03) |
| V-002 | 013, 014, 015 / S01 | forever 1.60.1 | in-game | | Revenge listed and enabled in the AddOns list; open Options › AddOns › Revenge (slider, dropdown); `/revenge` opens it; change both, `/reload`, values kept; no Bugsy errors. Coexistence with Revenge Book and luisjedev's Revenge is optional now (DEC-022) | User, 2026-11-25: all green. `RevengeTracker.lua` was written with every setting and a full-name cache ("First Last" from target, mouseover and nameplates); `!Bugsy.lua` has `problemCount = 0` after 3 sessions | pass |
| V-003 | 001, 002, 017 / S02 | forever 1.60.1 | in-game | | Open-world PvP death: entry recorded. Dungeon or battleground death and a duel: nothing recorded. Bugsy clean | | not run |
| V-004 | 003, 004, 012 / S03 | forever 1.60.1 | in-game | | With sample data, hover the killer: one skull line with the right count and names; hold Shift: detail lines; set the modifier to Off: none; expire a kill: the count drops | User, 2026-11-25: `/revenge test` line "(1) You" with the skull icon; Shift adds the detail line and redraws on press and release; other players show nothing; `/revenge test clear` removes it. Saved data afterwards: no kills, `nextId = 2`. Off and expiry were checked offline only | pass |
| V-005 | 011, 012, 013 / S04 | forever 1.60.1 | in-game | | Remove an entry in settings: gone from tooltip, skull and pins; add a name: listed; settings persist across `/reload` | | not run |
| V-006 | 005, 006, 021 / S05 | forever 1.60.1 | in-game, 2 clients | | Guildmate dies: entry arrives once; a repeat send is ignored. Guildmate adds a name: you see "Wanted by" and their name; with guild sharing off on their side, nothing arrives | | not run |
| V-007 | 005, 006 / S06 | forever 1.60.1 | in-game, 2 clients | | Same with an in-game friend and a Battle.net friend | | not run |
| V-008 | 009 / S07 | forever 1.60.1 | in-game | | Shared death with alert on: one chat line; off: none | | not run |
| V-009 | 007 / S08 | forever 1.60.1 | in-game | | Recorded killer's nameplate shows the skull with the default plates and with one nameplate addon (Q-009), the plate otherwise unchanged; it updates on removal, dismissal and expiry | | not run |
| V-010 | 008 / S09 | forever 1.60.1 | in-game | | Recorded killer comes into view: one alert; no repeat within the cooldown | | not run |
| V-011 | 010, 020 / S10 | forever 1.60.1 | in-game | | World map shows skull pins at sample death positions in the right colours, with hover details; right-click, Dismiss kill: that kill is gone everywhere | | not run |
| V-012 | 016 / S11 | forever 1.60.1 | install | | Tag a release; `instawow install github:weslo/revenge` installs it; AddOns list shows it compatible | | not run |
| V-013 | 019 / S12 | forever 1.60.1 | in-game | | Trigger each alert: one small silent popup, no screen effect; it fades by itself after about 4 seconds and at once on a click; off in settings: none | | not run |
| V-014 | 024, 025 / S13 | offline (Lua 5.1 via lupa 2.8), then forever 1.60.1 | offline tests; in-game later | `dev/core-s01-s03` | `tests/run.py`: 55 tests across identity, merge, foreign door, deaths, tooltip and store, against a mock of the Forever API. Cases include: the same kill from two sources; first name only; 4- and 9-minute skew; zone names in another language; dismissed then re-reported; own data wins; junk records; secret values; recap retries. In game: a malformed message from each prefix causes no Bugsy error (needs S05/S18) | Offline: 55 passed, 0 failed (2026-11-25). The first run found one real bug, zone text splitting kills across languages; fixed. In game: not run | pass (offline) |
| V-015 | 026 / S14 | forever 1.60.1 | static and in-game, 2 clients | | Offline: decode Revenge Book `K`/`R`/`L`/`M`/`X` fixtures. In game: a guildmate running Revenge Book dies or marks someone; it shows once in Revenge; your own death with both addons loaded counts once | | not run |
| V-016 | 027 / S15 | forever 1.60.1 | static and in-game, 2 clients | | Offline: decode `D`, `C` and chunked fixtures. In game: a guildmate's Grudgekeeper death and kill order show in Revenge | | not run |
| V-017 | 028 / S16 | forever 1.60.1 | static and in-game, 2 clients | | Offline: decode group and envelope `D` fixtures. In game: a grouped friend's HeadHunter death shows; a stranger's whispered report is ignored | | not run |
| V-018 | 029 / S17 | forever 1.60.1 | in-game | | With Kill on Sight loaded and a KoS entry, the player shows "Wanted by you" | | not run |
| V-019 | 030, 032 / S18 | offline, then forever 1.60.1 | static and in-game | | Fake adapters that throw on every call, return junk records, take 5 ms per message, and a 500-message flood. Each trips only its own breaker; Bugsy stays empty; nothing appears in chat; Revenge's own features and frame time are unchanged (measured with `debugprofilestop`). Master switch off: foreign-only data hidden at once; after `/reload` the module isn't loaded (`C_AddOns.IsAddOnLoaded` false) | | not run |

Validation statuses: `pass`, `fail`, `not run`, `not applicable` (with reason), `stale`.

## Blocked, deferred or replaced work

| REQ / row IDs | State | Cause or scope decision / source | Next action and owner | Effect on delivery |
|---|---|---|---|---|
| REQ-031 | deferred | Wanted: Dead or... Dead needs its faction channel (against REQ-024) and two libraries (against REQ-018) | Revisit only if the user asks, starting with its guild kill-on-sight list | Its users' data won't reach Revenge |
| Spy family (Q-014) | blocked | No public source for Spy (Forever), True Spy, Spy Guild KOS Sync, PlayerNotes & KoS | User decides on Q-014 | No adapters for them |

## Resume checkpoint

- Updated by / at: Claude, 2026-11-25 (planning)
- Repository / branch: `C:\Users\wesle\Documents\GitHub\revenge`, GitHub `weslo/revenge` (public). GitHub `main` has only the first plan (`09cb1b2`). Local `main` also has the accepted mock-up (`bc05874`, not pushed). Branch `plan/addon-interop` adds the other-addon plan (local)
- Exact HEAD revision: see `git log -1` on `plan/ui-mockup`
- Working tree: clean after the mock-up commit
- Last completed slice: none (planning)
- Last verified state: none
- Current slice and pending edits: S01, S02, S13 and S03 implemented on `dev/core-s01-s03`, static checks pass, nothing tested in game yet. The plan (all of `plan/addon-interop`) is merged into local `main`. The addon folder is linked into the game with a junction: `_forever_\Interface\AddOns\RevengeTracker` → `RevengeTracker\` in this repo
- Next executable action: the user runs V-002, V-003 and V-004 in game:
  - `/reload`; Revenge listed in AddOns; Options › AddOns › Revenge shows the slider and dropdown.
  - Target any player, `/revenge test`, hover them: one skull line; hold Shift: detail line.
  - Check Bugsy (`/bugsy`). The agent reads `WTF\Account\KYMRELL\SavedVariables\RevengeTracker.lua` and `!Bugsy.lua` after a `/reload`.
  - Then S04 (settings list, add by name, Wanted), with tests added to `tests/` as each slice lands. Run them with `.venv\Scripts\python.exe -I tests\run.py` (55 passing as of 2026-11-25).
- Open questions / blockers: Q-009 (at testing). Resolved: Q-001 to Q-008, Q-010 to Q-014 (DEC-021)
- Decisions to retain: DEC-001 to DEC-021 (DEC-020: other addons are low priority, isolated in an optional module, silent on failure, built after the first release; DEC-021: other-addon plan approved as proposed)
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
