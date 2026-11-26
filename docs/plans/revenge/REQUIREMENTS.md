# Revenge requirements

- Project/repository: `C:\Users\wesle\Documents\GitHub\revenge` (GitHub `weslo/revenge`, public; work is tracked in its Issues, DEC-026)
- Updated: 2026-11-26, by Claude (DEC-027, release packaging)
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
| REQ-001 | When you die to enemy-faction players, record every enemy player in the death recap as a killer. Don't separate the killing blow from helpers. Store full name (Forever first and last name, resolved through the name cache because the death recap gives first names only), realm, class, level, guild if seen, zone, map position and time. | User: original request; mock-up comment "Treat all participants in the kill as killers" (DEC-009) | 1 | forever | Die to two enemy players in the open world; both appear in the settings list with the zone and time | active |
| REQ-002 | Only open-world deaths count: never battlegrounds, arenas, dungeons, raids, scenarios or duels. | User: "Open world only" (2026-11-25) | 1 | forever | A battleground or dungeon death adds nothing; a duel loss adds nothing | active |
| REQ-003 | Hovering an enemy player with recent kills adds one line to the tooltip: a skull, the total of their recent kills, then up to 3 victim names and "+N more", e.g. "💀 (5) You, Mira, Tavish, +1 more". | User: original request; mock-up comment "simplify this tooltip info a ton. One line" (DEC-010) | 1 | forever | Hover a recorded killer: exactly one line appears. Hover anyone else: no line | active |
| REQ-004 | While a modifier key is held (Shift by default; Ctrl, Alt or off in settings), the tooltip also lists recent kills, one line each: victim, zone and how long ago (up to 5, then "+N more"). | User: "Details on recent kills in hover tooltip"; mock-up comment "An optional modifier key (shift) expands the details" (DEC-010) | 1 | forever | Hover with Shift: the lines appear; release Shift: they go. With the setting off, Shift does nothing | active |
| REQ-005 | Share your deaths and the players you've marked Wanted (REQ-021) with guildmates, in-game friends and Battle.net friends who run the addon, each channel following its sharing setting. | User: "Guild + all friends" (2026-11-25); "these should sync to friends/guildies if relevant sharing is on" (DEC-015) | 2 | forever | A guildmate, an in-game friend and a Battle.net friend, each running Revenge, see your new death and your new Wanted player in their tooltips | active |
| REQ-006 | Merge deaths shared by others. Accept them only from current guildmates and friends; ignore duplicates; rate-limit senders; keep only killers hostile to you. | Assumption: shared data can be faked or flood; see DEC-008 | 2 | forever | A repeated message adds nothing; a message from a stranger is ignored | active |
| REQ-007 | Recent killers get a small skull beside their nameplate. Revenge never resizes, recolours or replaces the nameplate, and places the skull beside whichever nameplate is showing: the game's own or a nameplate addon's (Threat Plates, Plater, Platynator, Kui and others) as best it can. | User: "Subtle nameplate mark"; mock-up comment "let's not fully override the style of nameplates" (DEC-011) | 3 | forever | A recorded killer's nameplate shows the skull, with the plate otherwise unchanged, with the default nameplates and with at least one nameplate addon | active |
| REQ-008 | Optional alert when a recent killer comes into view (nameplate, target or mouseover): one chat line and a sound, at most once every few minutes per player. | User: "Optional alerts for when an enemy is near" | 3 | forever | With the option on, a recorded killer coming into view alerts once; again only after the cooldown | active |
| REQ-009 | Optional alert when an enemy kills a friend or guildmate anywhere, as soon as their shared death arrives. | User: "...when an enemy kills a friend/guildie anywhere" | 3 | forever | With the option on, a friend's shared death shows one chat line naming victim, killer and zone | active |
| REQ-010 | World map pins at the death locations of recent kills on you, friends and guildmates. Every pin is a skull, coloured by group (you, friend, guildmate), so it can't be mistaken for other map markers. Hovering a pin shows who died, the killer and when. | User: "Simple map pins for kills on you or friends/guildies"; mock-up comment "use skulls in all of these" (DEC-012) | 3 | forever | Open the world map in a zone with a recent death: a skull is at the spot; its tooltip names the victim and killer | active |
| REQ-011 | A simple editable list of recent killers in the plain settings menu: see entries, remove them, and add a player by name, which marks them Wanted by you (REQ-021). | User: "Simple editable list in a plain settings menu"; mock-up comment "Include an 'add by name'" (DEC-013) | 2 | forever | Remove an entry: its tooltip line, skull and pins disappear. Add a name: it's listed as "Wanted by you" | active |
| REQ-012 | Kills expire from tooltips, marks, alerts and pins after 7 days by default, adjustable in settings. | User: "7 days default + config in plain settings" | 1 | forever | A kill older than the setting no longer shows. Changing the setting takes effect without `/reload` | active |
| REQ-013 | Plain settings in Options > AddOns > Revenge: the expiry; the details modifier key; nameplate skull; map pins; both alerts; whether alerts show as a popup, in chat, or both; the killer-nearby sound; sharing per channel (guild, friends, Battle.net); and the list. | User: "plain settings"; mock-up comments. Suite baseline: options | 1 | forever | Every option above is in the game's AddOns settings, persists across `/reload`, and has a working default | active |
| REQ-014 | All text comes from one English locale table with an English fallback, so translations can be added later. No other languages in the first release. | Assumption, from the suite's localization baseline (user can change) | 2 | forever | No visible text is hard-coded outside the locale file | active |
| REQ-015 | No clashes with other addons: own folder, saved-variable names, slash command, global names and addon-message prefix (see Q-001). | Assumption: luisjedev's Revenge already uses folder `Revenge` and `RevengeDB` | 1 | forever | Revenge, Revenge Book and luisjedev's Revenge load together with no errors or shared data | active |
| REQ-016 | Forever only (interface 16001), released on GitHub with a `release.json` so instawow installs it as `github:<owner>/revenge`. | User: GitHub-first, instawow (earlier sessions) | 2 | forever | `instawow install github:<owner>/revenge` installs the release; the game lists it as compatible | active |
| REQ-017 | Respect Forever's restricted values. Never compare, store or send secret values. When an enemy's identity is hidden, skip them quietly. | Suite: secret-value gate; `UnitGUID` is SecretWhenUnitIdentityRestricted on Forever | 1 | forever | No Lua errors or taint in Bugsy during PvP; restricted units show no line rather than an error | active |
| REQ-018 | Lightweight: no window beyond the settings panel and the small alert popup, no bundled libraries unless a requirement needs one, low memory and CPU. | User: wants something simpler than Revenge Book | 1 | forever | Folder well under 300 KB; no noticeable frame-time cost in a busy zone | active |
| REQ-019 | Alerts (REQ-008, REQ-009) can also show as a subtle popup, on by default: small, near the top of the screen, silent, no screen-wide effects, fades after about 4 seconds, and fades at once when clicked. | User: mock-up comment "let's include an optional subtle popup that's defaulted to on" (DEC-014) | 3 | forever | An alert shows one small popup with no sound or screen effect; it fades by itself, and at once on a click; it can be switched off | active |
| REQ-020 | Right-clicking a map pin offers "Dismiss kill", which removes that one kill everywhere: tooltip count, skull, list and map. | User: mock-up comment "Add option to right click -> dismiss kill" (DEC-012) | 3 | forever | Dismiss one of two kills by a player: the count drops by one; dismiss the last: the player's line, skull and pin go | active |
| REQ-024 | All incoming data goes through one source layer: normalized records (KillReport, WantedMark, Withdrawal) → trust filter → identity resolution → merge → store. Revenge's own source is in the core. Other addons' adapters live in the optional module (REQ-032) and enter only through a validating `SubmitForeign` call. Listen only: never send in another addon's format, answer its handshakes or join its channels. | User: DEC-019, DEC-020 | 1 (core layer); 4 (adapters) | forever | Disable any one adapter: the rest keep working; a malformed message from any source is dropped without a Lua error | active |
| REQ-025 | Deduplicate across sources and channels: the same victim, a shared killer, times within 2 minutes (exact) or 10 minutes (otherwise), and the same map when both give a map ID make one kill. Zone names are ignored, since other addons send them in their user's game language. Same target and adder make one Wanted mark. Dismissals stick across sources. | User: "deduplicates as best as possible" (DEC-019) | 1 | forever | The same death reported by Revenge and Revenge Book counts once; a dismissed kill re-reported by another addon stays dismissed | active |
| REQ-026 | Revenge Book adapter: guild messages `K`, `R`, `L` (kills on guildmates), `M` (Wanted), `X` (withdrawn), plus a time-sliced read-only import of `DeathNoteDB` (own, guild and friends' books) after login and at most every 10 minutes while it's loaded. | User: "like RevengeBook" (DEC-019); evidence in [OTHER-ADDONS.md](OTHER-ADDONS.md) | 4 (first adapter) | forever | A guildmate running only Revenge Book dies to an enemy: that enemy shows the kill in your tooltip; a friend's kill stored in your Revenge Book shows too | active |
| REQ-027 | Grudgekeeper adapter: guild `D` (deaths) and `C` kill orders (open: "Wanted by" the poster; closed: withdrawn), with reassembly of chunked messages. | DEC-019; evidence in OTHER-ADDONS.md | 5 | forever | A guildmate running Grudgekeeper dies or posts a kill order: it shows in Revenge | active |
| REQ-028 | HeadHunter adapter: `D` death reports by PARTY/RAID or whisper (including envelopes) whose victim is the sender and a guildmate or friend, plus `HeadHunter_DB` while it's loaded. | DEC-019; evidence in OTHER-ADDONS.md | 5 | forever | A grouped friend running HeadHunter dies: the kill shows in Revenge | active |
| REQ-029 | Kill on Sight adapter: its KoS list from `KillOnSightDB` saved data, as "Wanted by" its adder. | DEC-019; evidence in OTHER-ADDONS.md | 5 | forever | With Kill on Sight loaded, a player on its KoS list shows "Wanted by you" | active |
| REQ-030 | Settings group "Other addons": a master switch **Use data from other addons** (also `/revenge others off`), then one switch per adapter (on by default), each with a status line. Shift details mark kills that came only from another addon ("via Revenge Book", Q-013). | DEC-019, DEC-020; assumption on display | 4 | forever | Master switch off: foreign-only data disappears at once, and after `/reload` the module isn't loaded. An adapter off: its data stops arriving. Status shows reports this session | active |
| REQ-032 | Other-addon support is low priority and isolated. It's a separate load-on-demand folder (`RevengeTracker_OtherAddons`) that the core never depends on. Errors and unparseable input are swallowed silently: nothing in chat, popups or the error handler. A per-adapter circuit breaker trips after 5 errors, a parse-failure rate over 50% of the last 50 messages, or 3 budget overruns. Foreign work runs behind Revenge's own, from a bounded queue (200), in slices of at most 0.5 ms per frame, paused in combat. Saved-data imports are time-sliced and capped, at most every 10 minutes. Revenge's own data wins any conflict. | User: DEC-020 | 1 (as a constraint) | forever | Fault injection: an adapter that throws, a flood of malformed messages and a deliberately slow adapter each leave Revenge's features, frame time and Bugsy untouched, and trip only that adapter's breaker. With the module disabled, no other-addon code runs | active |
| REQ-031 | Wanted: Dead or... Dead adapter. | DEC-019 | none | forever | none | **deferred**: its data travels on a faction-wide channel Revenge won't join (REQ-024) and needs two bundled libraries (REQ-018); revisit only for its guild kill-on-sight list if asked |
| REQ-022 | Catch-up: when a guildmate or friend running Revenge comes online, the two exchange what the other is missing (kills within the expiry, and Wanted players), compactly and rate-limited. | User: agreed to the catch-up proposal (DEC-017) | 2 | forever | A friend offline during your death logs in later and still sees it within a minute; a long list doesn't flood chat throttling | active |
| REQ-023 | Wanted entries don't expire. The person who added one can withdraw it, and the withdrawal is shared. Removing someone else's Wanted entry only hides it for you. | User: agreed to the proposal (DEC-018) | 2 | forever | Mira withdraws her Wanted entry: it disappears for you. You remove Mira's: it's gone for you only, still there for Mira | active |
| REQ-021 | A player added by name is **Wanted**. Their tooltip line and alerts read "💀 Wanted by {name}", where {name} is whoever added them ("you" for your own). They get the nameplate skull too. A player with both kills and a Wanted mark shows the kills line, then the Wanted line. | User: "change the text to 💀 Wanted by {x} where x is the name of the person who added it" (DEC-015) | 2 | forever | Add a name yourself: "Wanted by you". A friend adds one: you see "Wanted by" and the friend's name in the tooltip, the alert and the list | active |

## Target and API evidence

| Target | Intended client/build/interface | Source commit and evidence | Related REQ IDs | Loading/access/runtime uncertainty |
|---|---|---|---|---|
| forever | 1.60.1.70938 / interface 16001 | Gethe/wow-ui-source `forever` at `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`, via the `wow-api-index` query tool (2026-11-25) | all | Declarations prove existence only. Runtime proof comes from Revenge Book v1.6.4 (installed) and The Terminal List, which use the same calls on Forever |
| forever | as above | Found: `C_DeathRecap.GetRecapEvents`, `PLAYER_DEAD`, `C_ChatInfo.RegisterAddonMessagePrefix` / `SendAddonMessage`, `CHAT_MSG_ADDON`, `C_BattleNet.SendGameData`, `BN_CHAT_MSG_ADDON`, `C_Map.GetBestMapForUnit` / `GetPlayerMapPosition`, `C_NamePlate.GetNamePlateForUnit` | 001, 005, 007, 010 | `UnitGUID` takes `UnitTokenPvPRestrictedForAddOns` and is `SecretWhenUnitIdentityRestricted`: probe in open-world PvP |
| forever | as above | Not in the generated index (FrameXML): `TooltipDataProcessor`, world-map pin templates | 003, 004, 010 | Confirm in the loaded FrameXML and with Revenge Book's working code |
| forever | as above | `C_DeathRecap` gives the killer's first name only on Forever (HeadHunter `Detection/ForeverDeaths.lua:3-10`, reviewed 2026-11-25). Full names need a name cache from nameplates, target and mouseover | 001, 024 | Confirm in game with a real PvP death (V-003) |
| forever | as above | `C_EncodingUtil` (Base64, compression, CBOR, JSON) exists for decoding. The planned adapters don't need it: all use plain text | 024 | none |

## UI and accepted design

- Mock-up choice and source: **mock-up first** (user, 2026-11-25).
- Accepted design: **canvas version 8** (id `1795627657-e22b`), accepted by the user on 2026-11-25 (DEC-016). It applies the user's six comments on version 6 (version 7), then "Wanted by" for players added by name (DEC-015). Source in [mockup/](mockup/README.md); live at the private artifact https://claude.ai/artifact/9M4d6XpfKVF8XftFNd8Ncs. Design acceptance isn't functional or in-game acceptance.
- Defaults (accepted with version 8, Q-007):
  - 7 days; details on Shift.
  - Nameplate skull, map pins and both alerts on.
  - Alerts as a popup and in chat; the killer-nearby chat sound on.
  - All three sharing channels on.
  - The killer-nearby alert repeats at most once every 5 minutes per player.
- Relevant REQ IDs: 003, 004, 007–011, 013, 019, 020, 021.
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
| Settings controls and list | interactive | Built from the game's native settings controls, which carry the settings panel's own gamepad focus and navigation. The list's input box and Add and Remove buttons are the game's own templates; `/revenge add First Last` is a keyboard path for adding | Confirm the input box and Remove buttons are reachable with a gamepad on Forever | pending check (no controller confirmed) |
| Map pins and their right-click menu | interactive | Shown on the game's world map; hover and the "Dismiss kill" menu follow the map's own cursor handling. Dismissing is also possible from the settings list (remove), so a gamepad user isn't stuck | gamepad hover and right-click on map pins unverified | pending check |
| Alert popup | passive, click to dismiss | Not focusable; it fades by itself, so no controller action is needed | none | not applicable |

- Input modes/devices to exercise: mouse and keyboard; gamepad only if the user has one.
- Bindings/settings to preserve: none (the addon adds no key bindings).

## Testing preference

- Route and source: the user plays, Bugsy (installed 2026-11-25) catches errors, and the agent reads the saved files after a `/reload` (in use since S01). Witchcraft is not set up.
- Remaining real-client checks: everything marked in-game in the matrix. Sharing needs a second person or account on the user's guild or friends list. Kill checks need real open-world PvP deaths; a debug-only command will inject sample data for the tooltip, list and pins.
- Controller checks: pending (see above).

## Open questions and assumptions

| ID | Question or assumption | Related REQ IDs | Impact / independent work available | Resolution and source |
|---|---|---|---|---|
| Q-001 | Internal names | 015, 016 | resolved | Title "Revenge"; folder, saved variables and globals `RevengeTracker`; slash command `/revenge`; message prefix `RVNG1` (DEC-016) |
| Q-002 | Who counts as "the killer"? | 001, 003 | resolved | Everyone in the kill, with no killing-blow or "helped" distinction (DEC-009) |
| Q-003 | Should the settings list also allow adding an enemy by name? | 011 | resolved | Yes (DEC-013) |
| Q-004 | Should Revenge also read Revenge Book's shared messages? | 005, 006 | resolved, widened | Yes, through a general layer for other popular addons' messages, with deduplication (DEC-019; see [OTHER-ADDONS.md](OTHER-ADDONS.md)) |
| Q-005 | A shared death whose killer is on your own faction (from a Battle.net friend on the other faction) is dropped. | 006 | Implementation detail | assumption (DEC-008) |
| Q-006 | Nameplate mark style? | 007 | resolved | Skull, used for every Revenge marker (DEC-012) |
| Q-007 | Defaults | 008, 009, 013, 019 | resolved | Everything on, as shown in version 8 (DEC-016) |
| Q-008 | What a player added by name shows before any kills | 003, 007, 011 | resolved | Skull, alerts and "💀 Wanted by {who added them}", shared like deaths (DEC-015, REQ-021) |
| Q-009 | Which nameplate addon to test the skull with: the user runs none today. Proposal: Threat Plates (`curse:21217`, Forever build, about 40M downloads) or Platynator (`curse:1361299`) in a test profile. | 007 | Only V-009 depends on it | pending (agent, at testing) |
| Q-010 | Catch-up for friends who were offline | 005, 006, 021 | resolved | Agreed as proposed (DEC-017, REQ-022) |
| Q-012 | Accept other addons' reports from players who aren't guildmates or friends (HeadHunter gossip, public channels)? Proposal: never | 006, 024, 028 | Affects the trust filter only | resolved: never (DEC-021) |
| Q-013 | Show "via Revenge Book" in Shift details? Proposal: yes, grey, only when no Revenge user reported the kill | 004, 030 | Display only | resolved: yes, as proposed (DEC-021) |
| Q-015 | Which other addon to support first, now that the user doesn't run Revenge Book (DEC-022): Revenge Book (if guildmates use it) or Grudgekeeper? | 026, 027 | Decided when S18 starts; nothing blocked before then | pending (user, at S18) |
| Q-014 | Spy (Forever), True Spy, Spy Guild KOS Sync and PlayerNotes & KoS have no public source. Install one through the CurseForge app so the agent can read the installed files, or leave them out? | 024 | Blocks any adapter for them | resolved: left out for now (DEC-021) |
| Q-011 | How Wanted entries end | 011, 012, 021 | resolved | Agreed as proposed (DEC-018, REQ-023) |

## Decisions and scope changes

| ID / date | Source | Decision or change | Affected REQ IDs | Consequence / successor / checks to repeat |
|---|---|---|---|---|
| DEC-001 / 2026-11-25 | User | Bugsy (`github:Spotnick2/Bugsy`) is the in-game error catcher, instead of BugSack (whose !BugGrabber instawow can't install) | testing | Read errors from `BugsyDB` after `/reload` |
| DEC-002 / 2026-11-25 | User | Share with guild, in-game friends and Battle.net friends | 005, 006 | Three message paths to test |
| DEC-003 / 2026-11-25 | User | Expiry 7 days by default, adjustable | 012 | none |
| DEC-004 / 2026-11-25 | User | Open-world deaths only | 002 | none |
| DEC-005 / 2026-11-25 | User | Name "revenge"; a public GitHub repo, created by the agent once this plan is approved | 015, 016 | See Q-001 for internal names |
| DEC-006 / 2026-11-25 | User | Mock-up before implementation | UI REQs | Mock-up is the next step |
| DEC-007 / 2026-11-25 | User (earlier) | Keep Revenge Book installed alongside | 015 | Superseded by DEC-022 (uninstalled) |
| DEC-008 / 2026-11-25 | Implementation | Trust rules for shared data: only from guildmates and friends, deduplicated, rate-limited, hostile killers only | 006 | Revisit if friends report missing deaths |
| DEC-009 / 2026-11-25 | User, mock-up comment on the tooltip | Everyone in the kill counts as a killer; no "helped" label | 001, 003, 004 | Q-002 resolved; killer-rule tweak removed |
| DEC-010 / 2026-11-25 | User, mock-up comment on the tooltip | The tooltip is one line, "💀 (N) names, +N more"; details only while a modifier (Shift) is held | 003, 004, 013 | Modifier choice added to settings |
| DEC-011 / 2026-11-25 | User, mock-up comment on nameplates | Never restyle nameplates; place the skull beside the game's own or an addon's plate | 007 | Test with a nameplate addon (Q-009) |
| DEC-012 / 2026-11-25 | User, mock-up comment on the canvas by the map pins | Skulls for every marker, so they can't be mistaken for others; right-click a pin to dismiss that kill | 007, 010, 020 | Q-006 resolved; REQ-020 added |
| DEC-013 / 2026-11-25 | User, mock-up comment on the settings list | Include "Add by name" | 011 | Q-003 resolved; Q-008 opened |
| DEC-014 / 2026-11-25 | User, mock-up comment on alerts | Add an optional popup, on by default: subtle, silent, no screen-wide effects, fades quickly or on a click | 013, 019 | REQ-019 added |
| DEC-015 / 2026-11-25 | User, in chat | A player added by name reads "💀 Wanted by {who added them}" and syncs to friends and guildmates when the matching sharing is on | 005, 011, 021 | Q-008 resolved; REQ-021 added; Q-010 and Q-011 opened |
| DEC-016 / 2026-11-25 | User, in chat | Mock-up version 8 accepted, with its defaults and the internal names | UI REQs, 015 | Q-001 and Q-007 resolved; implementation may start after the other-addon plan |
| DEC-017 / 2026-11-25 | User, in chat | Catch-up for friends who were offline, as proposed | 022 | REQ-022 added |
| DEC-018 / 2026-11-25 | User, in chat | Wanted entries don't expire; only their adder withdraws them for everyone | 023 | REQ-023 added |
| DEC-019 / 2026-11-25 | User, in chat | Add a layer that takes in messages from other popular addons (like Revenge Book) and deduplicates as well as possible; plan it before implementation starts | 024+ | See OTHER-ADDONS.md |
| DEC-022 / 2026-11-25 | User, in chat: "Uninstall Revenge Book" | Revenge Book is no longer installed here. Coexistence (REQ-015) is still kept for other users. The Revenge Book adapter (REQ-026) now matters only when guildmates run it, and its saved-data import only for users who run both | 015, 026; supersedes DEC-007 | Which adapter comes first is decided when S18 starts (Q-015) |
| DEC-021 / 2026-11-25 | User, in chat: "Approved, begin development" | The other-addon plan as proposed: no reports from strangers (Q-012), grey "via Revenge Book" in Shift details (Q-013), Spy and relatives left out for now (Q-014) | 024–032 | Development started with S01 |
| DEC-023 / 2026-11-25 | Implementation (S04) | The list is one custom element of the game's own vertical settings list, on the same page as the other settings, as in the accepted mock-up. The page is one column rather than the mock-up's two, because the game's settings list is a single column. Its rows scroll inside the element (6 visible) | 011, 013 | V-005 pass (2026-11-25) |
| DEC-024 / 2026-11-25 | Implementation (S04) | Remove on the list takes that player out of every stored kill they're in; other killers in the same kill stay. A tombstone keeps them out of re-reports of those deaths, while new deaths still count. Dismiss kill on a map pin (REQ-020, S10) removes the whole kill instead | 011, 020, 025 | none |
| DEC-025 / 2026-11-25 | Implementation (S04) | Add by name takes letters (any language), spaces, hyphens and apostrophes only, so no chat codes or links get in. It needs first and last name where the game uses surnames (a first name alone could match many players), refuses your own name and, when the name cache knows them, a player of your own faction. A name seen before takes the game's spelling, GUID, class and level; one not seen yet gets them the first time it's seen | 011, 021 | none |
| DEC-026 / 2026-11-25 | User, in chat | Work goes through GitHub: one Issue per increment (#1 for the work so far), a feature branch per Issue, commits pushed at clear deliverable steps, and a pull request against its Issue for the user to review. The user merges | all | Issues #1 to #15 created; the matrix's build order maps them to slices |
| DEC-027 / 2026-11-26 | Implementation (S11) | The repo keeps the addon in `RevengeTracker/`. The BigWigs packager (v2.7.0, pinned by commit) packages as `Revenge`, moves `RevengeTracker/` to the top of the zip and ignores everything else, so the zip holds only the addon folder. The release notes are the hand-written `CHANGELOG.md`, because a generated one would ship in a stray folder. The same workflow runs the checks and a no-upload package build on every pull request, so packaging mistakes show before a tag | 016 | V-012 |
| DEC-020 / 2026-11-25 | User, in chat | Other addons are low priority for performance and maintenance. Failures are silently disregarded and can't affect performance or functionality, and there's an easy off switch | 024, 026–030, 032 | Optional load-on-demand module; adapters built after the core and its first release; REQ-032 added |

## Completion criteria

- Every active REQ row is implemented and verified in the matrix, or explicitly deferred by the user.
- In-game acceptance by the user on Forever 1.60.1: open-world deaths recorded; tooltip, nameplate, alerts and pins correct; sharing confirmed with at least one guildmate or friend over each channel used; no errors in Bugsy.
- Installs from the GitHub release through instawow.
