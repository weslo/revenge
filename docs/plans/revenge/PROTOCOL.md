# Revenge's sharing protocol (prefix `RVNG1`)

Written for S05 (#4), guild sharing and catch-up. Friends and Battle.net (#5) reuse the same
messages on other channels.

## Rules

- **Everyone sends only their own data:** their own deaths, the Wanted marks they added, and
  the withdrawals of those marks. A message whose subject isn't its sender is dropped, so
  nothing travels second-hand. This is the trust rule of the plan (DEC-008, OTHER-ADDONS.md);
  Revenge Book's sync follows the same rule.
- **Guild channel only, for now.** The game delivers GUILD addon messages only from current
  guildmates, and a guild is one faction, so a guildmate's killers are hostile to you too.
  Whispers are ignored until #5 adds friends, with their own checks.
- **The sender must match the name in the message.** The game names a sender as "Name",
  "Name-Realm", "Name-Surname" or "Name Surname" (seen by Revenge Book on Forever). The first
  name must match; a surname, when the game gives one, must match too.
- **Everything received goes through the merge,** like your own data. Repeats change nothing,
  removed killers and dismissed kills stay removed, and a withdrawal beats any older copy of
  its mark.
- **Limits:** 255 bytes per message; at most 80 records per guildmate per 10 minutes, 400 in
  all; at most 50 Wanted marks stored per adder; kill times no more than 30 days old or 5
  minutes in the future. Anything malformed is dropped without a word (with `/revenge debug`,
  a debug line says why).
- **"Share my deaths and wanted players with my guild" off:** nothing of yours is sent, and
  hellos aren't answered. You still say hello and receive.

## Messages

One addon message each, fields separated by TAB. Every message starts with the sender's type,
full name and GUID (without `Player-`; empty if unknown).

| Type | Fields after type, name, GUID | Meaning |
|---|---|---|
| `H` | since, version | Hello after login: "send me your data newer than `since`" |
| `K` | id, at, map, x, y, flags, then per killer: name, GUID, class, level | You died just now |
| `R` | as `K` | The same death, in an answer to a hello |
| `M` | at, target, target GUID, class, level | You marked target Wanted at `at` |
| `X` | at, target | You withdrew that mark at `at` |

- `id` is the sender's own kill id (`k12`). A death with more killers than fit in one message
  goes as several `K` (or `R`) with the same id, and the receiver merges them into one kill.
- `at` and `since` are server time. `map` is the map ID; `x` and `y` are 0 to 1000 (tenths of a
  percent). Receivers name the zone from the map ID in their own language.
- `flags`: `t` marks a test kill (`/revenge test share`), stored as a test kill and removed by
  `/revenge test clear`.
- `class` is the class file name (`ROGUE`); `level` is 1 to 100. Empty fields mean unknown.
- An incompatible change gets a new prefix (`RVNG2`). Within `RVNG1`, new fields only go at the
  end, and unknown types are dropped.

## Catch-up

1. Ten to fifteen seconds after login (or after joining a guild), you send `H` with `since`: the
   time you were last online, less 10 minutes, but at least a day back and at most your expiry
   (7 days by default). With no record of your last time online, it's the whole expiry.
2. Each guildmate running Revenge, with sharing on, answers on the guild channel after 2 to 8
   seconds:
   - their own deaths since `since` (`R`, newest first, at most 20);
   - all their Wanted marks (`M`, newest first, at most 20);
   - their withdrawals from the last 30 days (`X`, at most 10).
3. Hellos that arrive while an answer waits are merged into it (the earliest `since` wins), and
   answers are at least 10 seconds apart. A guildmate's hello is answered at most every 5
   minutes.
4. Answers go to the whole guild, so anyone else who missed something gets it too; the merge
   ignores what they already have.

Data only meets when both people are online at once: a guildmate's death reaches you when you
and they are next online together.

## Sending

- One queue for everything. It sends up to 8 messages at once, then one a second. A message the
  game throttles waits 2, 4, 8 … seconds; after 5 tries, or 10 minutes in the queue, it's
  dropped.
- Nothing is sent in combat, in an instance, or while the game locks addon chat. The queue
  waits and tries again every 30 seconds.
- Results the game won't fix by waiting (not in a guild, an invalid channel) drop the message.
