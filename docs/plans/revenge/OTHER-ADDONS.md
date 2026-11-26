# Taking in other addons' data

- Updated: 2026-11-26, Claude (built: S14 to S18 in one pull request, DEC-031; formats re-read from source the same day)
- Decision: DEC-019 (user, in chat): "add an abstraction to the addon that supports messages from other popular addons (like RevengeBook) and deduplicates as best as possible. Let's plan the other-addon support first."
- Isolation: DEC-020 (user, in chat): other addons are "low priority when it comes to performance and maintenance… if they error, can't be parsed, or cause problems, they should be silently disregarded and prevented from impacting performance or functionality. Users should be able to easily switch off other addon compatibility."
- Requirements: REQ-024 to REQ-032 in [REQUIREMENTS.md](REQUIREMENTS.md); build rows IMP-013 to IMP-018 in [IMPLEMENTATION-MATRIX.md](IMPLEMENTATION-MATRIX.md)
- Evidence: read-only source reviews of each addon, first on 2026-11-25 and again on 2026-11-26 at the commits named below, read through the GitHub API without cloning or running anything. The formats are described here in our own words. Line references will drift as the addons update.

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
| **Revenge Book** 1.7.1 (3.9k; you uninstalled it 2026-11-25, DEC-022) | Everything on GUILD, including answers to others' catch-up requests. Friends' whisper and Battle.net data needs Revenge to send a hello, but a user running both has it in `DeathNoteDB` | **Adapter candidate**: guild messages, plus saved data for users who run both |
| **Grudgekeeper** 1.13.1 (2.2k) | Everything on GUILD, plain `;` text; long messages are probably AceComm-chunked | **Adapter 2**: guild deaths, assists and kill orders |
| **HeadHunter** 1.1.x (31k) | Its realm channel can't carry addon messages on Forever. Reports go by PARTY/RAID, or by whisper ("gossip") to members of its channel's roster | **Adapter 3**: party/raid and whispers from guildmates and friends, plus saved data while it's loaded |
| **Kill on Sight** 4.0.3 Forever (67k) | Nothing: the Forever build removed its sync | **Adapter 4**: its KoS list, from saved data, as Wanted marks |
| **Wanted: Dead or... Dead** 1.29.6 (9.5k) | Mostly a faction-wide custom channel; LibSerialize and LibDeflate encoding; signed authority records | **Deferred** (REQ-031): joining its channel breaks rule 1, and decoding needs two bundled libraries |
| **Spy (Forever)** (1.1M), **True Spy** (36k), **Spy Guild KOS Sync** (1.6k), **PlayerNotes & KoS** (4.2k) | Unknown: no public source | **Blocked** (Q-014). Spy itself shares sightings only, by its description |

### 1. Revenge Book (`DeathNote`, prefix `DeathNote`), re-read at `01ef1c1` (v1.7.1)

- **Format:** TAB-separated, at most 255 bytes, at most 10 fields. Field 1 is the protocol `1`, field 2 the type, and each type has an exact field count (K and R 9, L and M 8, X 4). Control bytes, `%` and `|` are escaped as `%XX`. Numbers are plain decimal. Times are the sender's own clock (`time()`), so their precision is `client`.
- **Names:** a killer's key is "First-Surname". When the sender didn't know the surname, the key's second part is a realm (or `?`) and the display name is the first name alone; Revenge then keeps the first name only. Victims and adders are "First Surname".
- **Used:** `K` (a live death of the sender) and `R` (the same in a catch-up answer): key, display, class, level, zone, t, victim. `L`: key, t, victim, mapID, x, y (tenths of a percent), merging into its death. `M` (marked Wanted by hand by the sender): key, display, class, level, t, by. `X` (that mark taken back; it has no time, so it counts from arrival): key, by.
- **Who:** the victim of K, R and L, and the adder of M and X, is always the sender; nothing is relayed. Revenge checks this again.
- **Channels:** only the guild channel reaches a listener. Friends' whispers and Battle.net data need Revenge Book's own hello, so they reach you only through your own Revenge Book's saved data.
- **Ignored:** hit lists (J/A), bounties (B, C, Q, Y), avenged kills (V/E), sightings, hellos and the rest.
- **Saved data** (`DeathNoteDB`, read while Revenge Book is loaded): your own book (`enemies[key].deaths`, sure kills only, not assists or imports), your current guild's book (`guild.lists[guild].enemies[key].deeds`), the friends' book (`friends.enemies[key].deeds`), your own hand-made Wanted entries, and the marks guildmates and friends sent (`listedBy`). Deaths older than 30 days are skipped.

### 2. Grudgekeeper (prefix `Grudgekeeper`, guild only), re-read at `ba6a723` (v1.13.1)

- **Format:** `;`-separated: type, protocol `1`, then fields; new fields only ever go on the end. No escaping: Grudgekeeper turns `;` into `,` before sending. Transport is LibForever-1.0, a pass-through to AceComm-3.0, which splits messages over 255 bytes: byte 1 marks the first part, byte 2 a middle part, byte 3 the last, per sender; byte 4 escapes a message that starts with a control byte. Revenge joins the parts.
- **Names:** "First Last"; an older client may send "Name-Realm", whose realm Revenge drops.
- **Used:** `D` (the sender just died): killer, class, race, level, zone, times, raceFile, sex, guild. No time, so `received`. `G` of kind `D` (one of the sender's own earlier deaths, in a catch-up answer): killer, class, race, level, zone, t, guild, times. `C` (the sender's own kill order, as it stands): id, target, class, race, level, guid, reward, created, expires, state, doneBy, note, auto, raceFile, sex. State `o` (open, until `expires`) is "Wanted by" the poster; `d`, `p`, `x` and `e` (fulfilled, paid, withdrawn, expired) end it.
- **Ignored:** `O` (someone else relaying an order), `F` (a hunter claiming someone else's order), `G` of kind `K`, the sender's own kills and assists, points, notes, sightings and profiles.
- **Saved data:** not read; the guild messages carry it all.

### 3. HeadHunter (prefix `HeadHunter`), re-read at `33130c0` (after v1.1.1)

- **Format:** `1`, the sender's faction `A`/`H`, a type letter, `:`, then records joined by `~` (one type per message). Fields `;`, sub-fields `,`. Numbers in lower-case base 36. No splitting, compression or escaping.
- **Used:** `D`: t, victim, level, class, race, mapID, x, y (thousandths), confidence (`e`, `i`, or `s` for a simulated test death, which is skipped), layer, killer, up to 4 assists, and an optional `h<helpers>`. Each enemy is name, incomplete (`1`: first name only, with the full GUID), level (`s` for a skull), class, race, sex, guid. Class and race are one-letter codes. t is the death recap's time; Revenge treats it as `client`.
- **Channels:** HeadHunter tries its own `HeadHunterSync` channel first, which the Forever server refuses (Revenge never joins it). A plain `D` goes to PARTY or RAID; whispers carry `E` envelopes (world, author, faction, server, hops, at, then the record).
- **Taken:** a plain `D` by party or raid, and an `E` at hop 1 whose author is the sender, when the sender is a guildmate or friend. **Ignored:** envelopes at hop 2 and up, bridged envelopes on group channels, catch-up data, and everything that isn't a death on your side.
- **Saved data** (`HeadHunter_DB`, while HeadHunter is loaded): your own deaths (`homes[meta.home].deaths`, origin `local`), the newest 200. Its received reports aren't read, since they include strangers'.

### 4. Kill on Sight (folder `KillOnSight`; no messages), re-read at `8ec0efb` (v4.0.3 Forever)

- **Saved data:** `KillOnSightDB.global.data.players["first last"] = { name, class, reason, addedBy, addedAt, ... }`, a hand-rolled layout (not AceDB). Everything in `players` is kill on sight; the "Honoured" list (`honorPlayers`), the encounter stats, the backup and the old per-realm copies aren't read.
- **Marks:** "Wanted by" you, or by `addedBy` when an old sync left a guildmate's full name there. `addedAt` is the local clock. Names typed with `/kos add` are lower case and get capitals. Old entries with a first name only are skipped: Kill on Sight never alerts on them either.
- **Removals:** removing a player deletes the entry, so after reading the whole list Revenge drops the marks only Kill on Sight gave for players no longer on it.
- **Folder:** CurseForge installs it as `KillOnSight`; Revenge checks `KillOnSight-forever` too.

## As built (2026-11-26)

- **Files:** the module is `RevengeTracker_OtherAddons/` (`Breaker.lua`, `Queue.lua`, `Host.lua`, `Adapters/*.lua`), shipped in the same zip, load-on-demand and depending on Revenge. The core's side is `Foreign.lua` (the door, trust, loading the module, status) and `OthersPanel.lua` (the status lines).
- **The door** takes kills, Wanted marks and withdrawals. A message's sender must be a guildmate on the guild channel, an online friend (in-game or Battle.net), or a guildmate or friend in your group, and it must be about their own death or mark. Your own copy of another addon's saved data is exempt from both checks.
- **Never passed on:** Revenge's own catch-up answers carry only what Revenge itself recorded, and removing another addon's mark doesn't send a withdrawal.
- **Hidden at once** when the master switch goes off: kills and marks no Revenge user reported. Caps: 1,000 such kills and 500 such marks in storage (the oldest go at login), 3,000 records a session, 50 per call.
- **Budget:** a 200-message queue, at most 0.5 ms a frame, nothing in combat, at most 20 records a second into the merge; one call over 2 ms is an overrun. Per sender, at most 120 messages per adapter in 10 minutes. Imports run 20 seconds after the module loads and then every 10 minutes, one adapter at a time, at most 500 records a run, skipping what this session already handed over.
- **Breakers:** 5 errors, more than 25 of the last 50 messages failing to parse, or 3 overruns pause an adapter for the session. A saved-data structure it doesn't recognise stops that import for the session without counting as an error.
- **Lapsing marks:** a mark can carry `expires` (Grudgekeeper's open orders); it stops showing then and is pruned at the next login. Revenge's own marks never lapse.
- **Alerts:** a death from another addon that arrives live (Revenge Book's `K`, Grudgekeeper's `D`, HeadHunter's `D` within 5 minutes) alerts like a guildmate's own.
- **Tests:** `tests/test_others.lua` (the framework, with throwing, junk-flooding and slow fake adapters) and `tests/test_adapters.lua` (each format, built from the descriptions above).

## Order and effort

Other addons are low priority (DEC-020), so they come after everything else:

1. **The core source layer** (IMP-013): records, name cache, trust and merge, with Revenge's own deaths flowing through it, and the `SubmitForeign` door with its validation. This is core, so it's built early, right after recording.
2. **All core features and Revenge's first release**, with no other-addon code in it.
3. **The optional module** (IMP-018): load-on-demand folder, master switch, queue and time budget, circuit breakers, status lines. It's tested with deliberately broken fake adapters before any real one.
4. **The adapters:** planned one at a time, each only if the one before proved worth it. Built instead all together with the module in one pull request, to be tried in game over time (DEC-031, which settles Q-015).
6. **Wanted: Dead or... Dead:** only if asked, and then only its guild kill-on-sight list (`WNTDK`), which needs the two libraries.

Each adapter's sample messages are built from the formats above and decoded offline under Lua 5.1 (`tests/test_adapters.lua`). The in-game check needs a guildmate or friend running that addon.

## Open questions

- **Q-012:** reports from players who aren't guildmates or friends (HeadHunter gossip, public channels). Proposal: never.
- **Q-013:** show "via Revenge Book" in Shift details. Proposal: yes, grey, only when no Revenge user reported the kill.
- **Q-014:** Spy (Forever), True Spy, Spy Guild KOS Sync and PlayerNotes & KoS have no public source.
  - Options: you install one through the CurseForge app and I read the installed files (read only); or leave them out.
  - Spy itself shares sightings, not kills, so its value is mainly Spy Guild KOS Sync's shared kill-on-sight list.
