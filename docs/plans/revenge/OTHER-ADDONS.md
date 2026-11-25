# Taking in other addons' data

- Updated: 2026-11-25, Claude (planning)
- Decision: DEC-019 (user, in chat): "add an abstraction to the addon that supports messages from other popular addons (like RevengeBook) and deduplicates as best as possible. Let's plan the other-addon support first."
- Isolation: DEC-020 (user, in chat): other addons are "low priority when it comes to performance and maintenance… if they error, can't be parsed, or cause problems, they should be silently disregarded and prevented from impacting performance or functionality. Users should be able to easily switch off other addon compatibility."
- Requirements: REQ-024 to REQ-032 in [REQUIREMENTS.md](REQUIREMENTS.md); build rows IMP-013 to IMP-018 in [IMPLEMENTATION-MATRIX.md](IMPLEMENTATION-MATRIX.md)
- Evidence: read-only source reviews of each addon, 2026-11-25, at the versions named below. Line references are to those clones and will drift as the addons update.

## Goal

Deaths and Wanted marks that guildmates and friends share through **other** PvP addons count in Revenge too. They show in the tooltip line, skull, alerts and pins exactly like Revenge's own. Each real event appears **once**, however many addons and channels reported it.

## Ground rules

1. **Listen only.** Revenge reads other addons' messages, and their saved data when they're loaded. It never sends in another addon's format, never answers another addon's hello, and never joins another addon's chat channel. Joining one shows in your channel list, and some addons count every member as one of their users.
2. **Same trust as Revenge's own sharing** (DEC-008). Accept reports only from current guildmates and friends (Q-012). A death report counts only when its sender is the victim; all three addons that send deaths enforce this themselves. A Wanted mark counts only when its sender is the one who added it.
3. **Low priority, isolated, silent.** Other addons change and break in ways Revenge can't control (DEC-020). See [Isolation and priority](#isolation-and-priority). In short:
   - Their support is an optional module the core never depends on.
   - It runs on a strict time budget, behind Revenge's own work.
   - Anything that errors or won't parse is dropped silently.
   - One switch turns it all off.
4. **Nothing secret.** Other addons' fields are plain strings, and never reach APIs that take secret values.
5. **Light.** No bundled libraries. Every adapter below uses plain text that Lua can split, except Wanted: Dead or... Dead, which is deferred for that reason.
6. **No copied code.** Revenge Book and HeadHunter have no license. Revenge reads their data formats, which is interoperability, and none of their code is copied.

## Isolation and priority

The user's rule (DEC-020): other addons are low priority for performance and maintenance. If they error, can't be parsed or cause problems, they're silently disregarded and must not affect performance or functionality. Users can easily switch other-addon support off.

### A separate, optional module

- **Its own folder.** All adapters live in a load-on-demand folder, `RevengeTracker_OtherAddons`, shipped in the same release zip as Revenge.
- **Loaded only when wanted.** Revenge loads it only when **Use data from other addons** is on.
  - Switched off, or disabled in the game's AddOns list, none of its code loads after the next `/reload`, and none of the other addons' prefixes are registered. It costs nothing.
  - Switching it off also hides, at once, every kill and Wanted mark known *only* from other addons. Data that Revenge users also reported stays.
- **The core never depends on it.** Revenge's recording, sharing, catch-up, tooltip, skull, alerts, pins and list work identically without the module.
- **One narrow door.** The module reaches the core through a single call, `SubmitForeign(records)`.
  - That call checks every record: known type, field types, string lengths, number ranges, sane times.
  - Only then does a record enter the trust filter and merge.
  - Adapters never touch the store, the UI or the settings directly.

### Silent failure

- **No messages, ever.**
  - Every adapter call runs inside `pcall`.
  - Errors are swallowed, never passed to the game's error handler, so Bugsy shows nothing.
  - Input that can't be parsed is dropped without a message.
  - Nothing about other addons ever appears in chat, a popup or an error frame. Their status shows only on the settings page, and in an optional `/revenge debug` log.
- **A circuit breaker per adapter.** An adapter switches itself off for the rest of the session after any of:
  - 5 errors;
  - more than half of its last 50 messages failing to parse;
  - 3 overruns of its time budget.

  Its status line reads "paused: the other addon may have changed". It tries again next session.

### Performance budget

- **A queue, not the event handler.** Other addons' messages go into a small bounded queue, 200 entries, dropping the oldest when full. They're processed later in slices of at most **0.5 ms per frame**.
- **In a busy moment, other addons' data waits.** Processing pauses in combat. Revenge's own messages are handled first and never wait behind them.
- **Cheap rejection first.** Oversized messages and senders over a per-sender rate cap are dropped before any parsing. Trust checks (guildmate or friend) come before decoding wherever the sender is known.
- **Saved-data importers are time-sliced** (a few entries per frame):
  - they run once after login, then at most every 10 minutes, never in combat;
  - each run has a total entry cap;
  - each importer stops at the first structure it doesn't recognise.
- **Bounded merge cost.** Foreign records merged per second are capped. Foreign-only data has its own storage cap, with the oldest dropped first.

### Revenge's own data wins

When a foreign record and Revenge's own disagree about a kill (killers, place, time), Revenge's own fields win. Foreign data only fills gaps, and adds kills Revenge doesn't otherwise know.

### Low maintenance

- **One file per adapter**, each with its own sample-message fixtures.
- **A format change disables, not breaks.** When another addon changes its format, its adapter fails closed (the circuit breaker) until someone updates it.
- **Adapters never hold up Revenge.** An adapter problem never blocks a Revenge release: it can ship switched off by default, or be left out of the module.
- **Built last.** Adapters come after the core features and Revenge's first release (see [Order and effort](#order-and-effort)).

## Architecture

```
 ┌─ Revenge core (always loaded) ──────────────────────────────────────────────────────────────┐
 │  own prefix RVNG1 ─► Sources/Revenge.lua ─┐                                                 │
 │                                           ├─► trust filter ─► name cache ─► merge ─► store ─► tooltip, skull, alerts, pins, list
 │  SubmitForeign(records) ─► validate ──────┘        (own data handled first; foreign capped) │
 └──────────────▲──────────────────────────────────────────────────────────────────────────────┘
                │ the only way in
 ┌─ RevengeTracker_OtherAddons (load on demand, optional) ─────────────────────────────────────┐
 │  other prefixes ─► size/rate/trust pre-checks ─► bounded queue ─► 0.5 ms/frame slices       │
 │        ─► adapter.decode() in pcall ─► records          saved data ─► time-sliced importers │
 │  circuit breaker per adapter · master switch · status lines for the settings page           │
 └──────────────────────────────────────────────────────────────────────────────────────────────┘
```

Revenge's own protocol is one more source (`Sources/Revenge.lua`) on the core's path, so the merge and trust code are exercised by every message, whether or not the module is loaded.

### Adapter interface

| Field / function | Purpose |
|---|---|
| `id`, `title` | Stable ID for settings and provenance (e.g. `revengebook`), and a display name |
| `prefixes` | Addon-message prefixes to register and route here |
| `detect()` | Whether the other addon is loaded here, for the settings page. Listening works without it |
| `decodeMessage(prefix, text, channel, sender)` | Returns normalized records, or nothing |
| `importLocal()` | Optional. Reads the other addon's saved data read-only, a slice at a time, returns records |
| `understands` | The protocol versions and message types this adapter knows; anything else is dropped and counted |

### Normalized records

- **KillReport**:
  - `victim`, `killers` (a list): identities.
  - `at`: server time, with `precision` of `exact` (server time), `client` (the sender's clock, assumed within 5 minutes) or `received` (stamped when it arrived).
  - `mapID`, `x`, `y`, `zoneText`: optional.
  - `reporter`, `source`: the adapter and channel.
- **WantedMark**: `target`, `by`, `at`, optional `note`, `source`.
- **Withdrawal**: the adder takes a WantedMark back.
- **Identity**: `name` as given, plus `realm`, `guid`, `class`, `level`, `guild` when known.
  - The other addons write names as "First Last", "First-Last", or "first last" in lower case.
  - Grudgekeeper victims, and Forever's own death recap, can carry the **first name only**.

### Identity resolution

- **The death recap gives first names only.** On Forever, `C_DeathRecap` gives the killer's first name only (HeadHunter `Detection/ForeverDeaths.lua:3-10`). That's true for Revenge's own recording too (REQ-001).
- **A name cache fills them in.** Revenge keeps a small cache of full names, built from nameplates, target and mouseover: GUID → "First Last", and first name → the full names seen with it. Revenge's own deaths and first-name-only reports resolve through it.
- **Name key:** lower case, `-` turned into a space, spaces collapsed, plus `-realm` when known.
- **Matching, in order:**
  - A GUID match wins.
  - Otherwise, the full-name key.
  - A first name only matches a full name when exactly one candidate is known. Otherwise the report is kept apart, waiting for more information.

### Deduplication

- **Same kill**, when all of these hold:
  - the same victim;
  - at least one killer in common;
  - times within **2 minutes** when both are `exact`, or **10 minutes** otherwise;
  - the same map when both give a map ID. Zone names are ignored: other addons send them in their user's game language ("Dämmerwald" for "Duskwood"), which would split one death in two (found by the offline tests, 2026-11-25).
- **What a merge keeps:**
  - the most precise time and position;
  - the union of killers, preferring entries with GUID, class and level;
  - a `sources` list.

  The tooltip count rises once per real kill.
- **Same Wanted mark:** the same target and the same adder. Different adders stay separate ("Wanted by Mira, Tavish").
- **Echoes:**
  - Guild addon messages come back to their sender, so your own death can arrive from Revenge and from Revenge Book at once. They merge.
  - Revenge Book's and Grudgekeeper's answers to someone else's catch-up request repeat old kills. They merge too.
- **Dismissals stick:** a dismissed kill (REQ-020) keeps a small tombstone with its merge key, so another source can't bring it back.

### Settings and display

- An **Other addons** group on the settings page:
  - At the top, one master switch, **Use data from other addons** (also `/revenge others off`). Off means the module isn't loaded after `/reload`, and foreign-only data is hidden at once.
  - Below it, one switch per adapter, each on by default.
  - Each switch's status: "listening", "reading saved data", "paused: the other addon may have changed", and reports this session.
- **Provenance:** Shift details add a grey "via Revenge Book" when a kill came only from another addon (Q-013).

## The addons

Popularity is CurseForge downloads as of 2026-11-25.

| Addon (downloads) | What reaches a listener on Forever | Plan |
|---|---|---|
| **Revenge Book** 1.6.4 (3.9k; you uninstalled it 2026-11-25, DEC-022) | Everything on GUILD, including answers to others' catch-up requests. Friends' whisper and Battle.net data needs Revenge to send a hello, but a user running both has it in `DeathNoteDB` | **Adapter candidate**: guild messages, plus saved data for users who run both |
| **Grudgekeeper** 1.13.1 (2.2k) | Everything on GUILD, plain `;` text; long messages are probably AceComm-chunked | **Adapter 2**: guild deaths, assists and kill orders |
| **HeadHunter** 1.1.x (31k) | Its realm channel can't carry addon messages on Forever. Reports go by PARTY/RAID, or to random players by whisper | **Adapter 3**: party/raid and whispers from guildmates and friends, plus saved data while it's loaded |
| **Kill on Sight** 4.0.1 Forever (67k) | Nothing: the Forever build removed its sync | **Adapter 4**: its KoS list, from saved data, as Wanted marks |
| **Wanted: Dead or... Dead** 1.29.6 (9.5k) | Mostly a faction-wide custom channel; LibSerialize and LibDeflate encoding; signed authority records | **Deferred** (REQ-031): joining its channel breaks rule 1, and decoding needs two bundled libraries |
| **Spy (Forever)** (1.1M), **True Spy** (36k), **Spy Guild KOS Sync** (1.6k), **PlayerNotes & KoS** (4.2k) | Unknown: no public source | **Blocked** (Q-014). Spy itself shares sightings only, by its description |

### 1. Revenge Book (`DeathNote`, prefix `DeathNote`)

- **Format:**
  - TAB-separated, at most 255 bytes, fields `%XX`-escaped.
  - Field 1 is the protocol (`1`), field 2 the type.
  - Each type has an exact field count, and some allow one optional extra. Reject anything else (`Sync.lua:496-511`).
- **Used:**
  - `K` (live kill on the sender) and `R` (the same in a catch-up answer): `key, display, class, level, zone, t, victim`.
    - `key` is the killer, "First-Surname".
    - `t` is the sender's clock, so its precision is `client`.
    - `victim` is the sender, "First Surname" (`Sync.lua:2566-2587`).
  - `L`: `key, t, victim, mapID, x, y`, with x and y in tenths of a percent. It attaches to the matching `K`/`R`.
  - `M` (added by hand: Wanted by the sender): `key, display, class, level, t, by`.
  - `X` (taken off: a Withdrawal): `key, by`.
- **Ignored:** hit-list releases `J`/`A`, bounties `B`, avenged `V`/`E`, sightings `S`/`T`, help calls on `DeathNoteSOS`, hellos `H`.
- **Saved data:**
  - `DeathNoteDB` holds `enemies` with per-killer `deaths`, a `guild.lists[guildName]` book, and a `friends` book (`Store.lua:376-377`, `783-790`; `Sync.lua:733-742`).
  - Imported read-only, time-sliced, after login and then at most every 10 minutes while Revenge Book is loaded. This is how friends' data that only reached your own Revenge Book gets in.
  - Its internal event bus (`_G.DeathNote:On`) is not used, since it's undocumented and may change.
- **Churn:** ten releases in two weeks. The protocol digit stays `1`, but types are added.

### 2. Grudgekeeper (prefix `Grudgekeeper`, GUILD only)

- **Format:**
  - `;`-separated: type, protocol `1`, then fields; new fields are only added at the end.
  - Transport is LibForever-1.0 over AceComm. Messages over 255 bytes are probably split with `\001`/`\002`/`\003` lead bytes, so the adapter reassembles them. This is unverified, because that library wasn't in the clone.
- **Used:**
  - `D` (the sender died): `killer, class, race, level, zone, …, enemyGuild` (`Guild.lua:1436`). It has no timestamp, so precision is `received`.
  - `C` (kill order): `id, target, class, race, level, guid, reward, created, expires, state, doneBy, note, …` (`Guild.lua:745`).
    - State `o` (open) is "Wanted by the poster".
    - Any other state is a Withdrawal.
  - `O` relays a `C` and is never trusted over a live `C`.
- **Ignored:** `K`/`H` (the sender's own kills and assists), points, notes, sightings, pots and profiles.
- **Saved data:** `GrudgekeeperDB` exists, but not used at first, since guild messages already cover it.
- **Churn:** very high. Fields were added without changing the protocol digit, so parse by position and tolerate extra trailing fields.

### 3. HeadHunter (prefix `HeadHunter`)

- **Format:**
  - The message starts with `"1"`, then the faction `A`/`H`, a type letter and `:`.
  - Records are separated by `~`, fields by `;`, sub-fields by `,`. Numbers and coordinates are base 36.
  - Gossip wraps records in an `E` envelope.
- **Used:** `D` death reports: `t;victimKey;level;class;race;mapID;x;y;confidence;layer;killer[;assists]`.
  - Each killer is `key,incomplete,level,class,race,sex,guid`, and `t` is server time (`Protocol.lua:213-293`).
  - Taken from PARTY/RAID and from whispers, including `E` envelopes, only when the sender or the envelope's author is the victim and a guildmate or friend.
- **Ignored:** HeadHunter's realm-wide channel and its strangers (Q-012); WANTED is computed locally by HeadHunter and never sent.
- **Saved data:** `HeadHunter_DB` is read while loaded. On Forever it isn't loaded back after a reload, so the importer reads it in-session only.
- **Value:** lower than its downloads suggest, since only groupmates and occasional whispers reach a listener.

### 4. Kill on Sight (Forever build; no messages)

- **Saved data:**
  - `KillOnSightDB.global.data.players[key]` holds `{name, class, reason, addedBy, addedAt, …}`. These become WantedMarks: "Wanted by" `addedBy`, which is usually you.
  - Check for both `KillOnSight` and `KillOnSight-forever` as folder names.
  - The record type is a localized string, so check for "player" entries by structure, not by that string.

## Order and effort

Other addons are low priority (DEC-020), so they come after everything else:

1. **The core source layer** (IMP-013): records, name cache, trust and merge, with Revenge's own deaths flowing through it, and the `SubmitForeign` door with its validation. This is core, so it's built early, right after recording.
2. **All core features and Revenge's first release**, with no other-addon code in it.
3. **The optional module** (IMP-018): load-on-demand folder, master switch, queue and time budget, circuit breakers, status lines. It's tested with deliberately broken fake adapters before any real one.
4. **The first adapter:** Revenge Book (IMP-014) if guildmates use it, otherwise Grudgekeeper (IMP-015). You no longer run Revenge Book (DEC-022), so this is decided when S18 starts (Q-015).
5. The rest in order: **Grudgekeeper** or **Revenge Book**, then **HeadHunter** (IMP-016), then **Kill on Sight** (IMP-017). Each one is built only if the one before proved worth it.
6. **Wanted: Dead or... Dead:** only if asked, and then only its guild kill-on-sight list (`WNTDK`), which needs the two libraries.

Testing each adapter needs sample messages, built from the formats above and kept as fixtures. They're decoded offline under a Lua 5.1 interpreter (not yet installed), then checked in game with a guildmate or friend running that addon.

## Open questions

- **Q-012:** reports from players who aren't guildmates or friends (HeadHunter gossip, public channels). Proposal: never.
- **Q-013:** show "via Revenge Book" in Shift details. Proposal: yes, grey, only when no Revenge user reported the kill.
- **Q-014:** Spy (Forever), True Spy, Spy Guild KOS Sync and PlayerNotes & KoS have no public source.
  - Options: you install one through the CurseForge app and I read the installed files (read only); or leave them out.
  - Spy itself shares sightings, not kills, so its value is mainly Spy Guild KOS Sync's shared kill-on-sight list.
