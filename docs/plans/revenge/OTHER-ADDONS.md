# Taking in other addons' data

- Updated: 2026-11-25, Claude (planning)
- Decision: DEC-019 (user, in chat): "add an abstraction to the addon that supports messages from other popular addons (like RevengeBook) and deduplicates as best as possible. Let's plan the other-addon support first."
- Requirements: REQ-024 to REQ-031 in [REQUIREMENTS.md](REQUIREMENTS.md); build rows IMP-013 to IMP-017 in [IMPLEMENTATION-MATRIX.md](IMPLEMENTATION-MATRIX.md)
- Evidence: read-only source reviews of each addon, 2026-11-25, at the versions named below. Line references are to those clones and will drift as the addons update.

## Goal

Deaths and Wanted marks that guildmates and friends share through **other** PvP addons count in Revenge too. They show in the tooltip line, skull, alerts and pins exactly like Revenge's own. Each real event appears **once**, however many addons and channels reported it.

## Ground rules

1. **Listen only.** Revenge reads other addons' messages, and their saved data when they're loaded. It never sends in another addon's format, never answers another addon's hello, and never joins another addon's chat channel. Joining one shows in your channel list, and some addons count every member as one of their users.
2. **Same trust as Revenge's own sharing** (DEC-008). Accept reports only from current guildmates and friends (Q-012). A death report counts only when its sender is the victim; all three addons that send deaths enforce this themselves. A Wanted mark counts only when its sender is the one who added it.
3. **Fail closed, per source.** Each adapter runs in `pcall` and drops anything it doesn't fully understand: an unknown message type, a wrong field count, an unknown protocol digit. An adapter that keeps failing turns itself off for the session and says so on the settings page.
4. **Nothing secret.** Other addons' fields are plain strings, and never reach APIs that take secret values.
5. **Light.** No bundled libraries. Every adapter below uses plain text that Lua can split, except Wanted: Dead or... Dead, which is deferred for that reason.
6. **No copied code.** Revenge Book and HeadHunter have no license. Revenge reads their data formats, which is interoperability, and none of their code is copied.

## Architecture

```
 CHAT_MSG_ADDON / BN_CHAT_MSG_ADDON                  other addons' saved data (read-only, while loaded)
            │                                                       │
            ▼                                                       ▼
  Source registry: routes each prefix to its adapter       adapter.importLocal() at login, then every 2 min
            │                                                       │
            ▼                                                       ▼
  adapter.decode(...) → normalized records: KillReport / WantedMark / Withdrawal
            │
            ▼
  Trust filter: sender is a guildmate or friend; sender is the victim or adder; hostile killers only; size and rate caps
            │
            ▼
  Identity resolution (name cache) → Merge (deduplicate, combine killers and sources) → Store → tooltip, skull, alerts, pins, list
```

Revenge's own protocol is one more source (`Sources/Revenge.lua`) on the same path, so every message exercises the merge and trust code.

### Adapter interface

| Field / function | Purpose |
|---|---|
| `id`, `title` | Stable ID for settings and provenance (e.g. `revengebook`), and a display name |
| `prefixes` | Addon-message prefixes to register and route here |
| `detect()` | Whether the other addon is loaded here, for the settings page. Listening works without it |
| `decodeMessage(prefix, text, channel, sender)` | Returns normalized records, or nothing |
| `importLocal()` | Optional. Reads the other addon's saved data read-only, returns records |
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
  - the same zone when both report one (`mapID` first, then zone text, since zone names can be localized).
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
  - one switch per adapter, on by default;
  - each switch's status: "listening", "reading saved data", "turned off after errors", and reports this session.
- **Provenance:** Shift details add a grey "via Revenge Book" when a kill came only from another addon (Q-013).

## The addons

Popularity is CurseForge downloads as of 2026-11-25.

| Addon (downloads) | What reaches a listener on Forever | Plan |
|---|---|---|
| **Revenge Book** 1.6.4 (3.9k; you run it) | Everything on GUILD, including answers to others' catch-up requests. Friends' whisper and Battle.net data needs Revenge to send a hello, but your own copy stores it in `DeathNoteDB` | **Adapter 1**: guild messages and saved data |
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
  - Imported read-only at login and every 2 minutes while Revenge Book is loaded. This is how friends' data that only reached your own Revenge Book gets in.
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

1. **The source layer** (IMP-013): registry, records, name cache, trust and merge, with Revenge's own deaths flowing through it. It comes before the tooltip, so everything after builds on it.
2. **Revenge Book** (IMP-014): its guild messages and saved data, right after the tooltip and list. You run it, so this brings in shared data before Revenge's own sharing exists.
3. **Revenge's own sharing and catch-up** (IMP-005, IMP-006): as planned.
4. **Grudgekeeper** (IMP-015), then **HeadHunter** (IMP-016), then **Kill on Sight** (IMP-017).
5. **Wanted: Dead or... Dead:** only if asked, and then only its guild kill-on-sight list (`WNTDK`), which needs the two libraries.

Testing each adapter needs sample messages, built from the formats above and kept as fixtures. They're decoded offline under a Lua 5.1 interpreter (not yet installed), then checked in game with a guildmate or friend running that addon.

## Open questions

- **Q-012:** reports from players who aren't guildmates or friends (HeadHunter gossip, public channels). Proposal: never.
- **Q-013:** show "via Revenge Book" in Shift details. Proposal: yes, grey, only when no Revenge user reported the kill.
- **Q-014:** Spy (Forever), True Spy, Spy Guild KOS Sync and PlayerNotes & KoS have no public source.
  - Options: you install one through the CurseForge app and I read the installed files (read only); or leave them out.
  - Spy itself shares sightings, not kills, so its value is mainly Spy Guild KOS Sync's shared kill-on-sight list.
