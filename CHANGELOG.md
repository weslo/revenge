# Revenge changelog

## v0.5.1

- Revenge is on CurseForge too, as **Easy Revenge**; in game it's still "Revenge". Nothing
  else changes, and instawow still installs it from GitHub.

## v0.5.0

- A diagnostic log, off by default, for looking into a problem later. `/revenge log on` (or "Keep a
  diagnostic log" under Options › AddOns › Revenge › Troubleshooting) saves a short line for each of
  your deaths, what's shared and received, alerts, nameplate skulls, map pins, other addons' reports and
  any error Revenge catches. Nothing is shown in chat or sent to anyone, and it keeps the newest 2,000
  lines. `/revenge log off` stops it, `/revenge log clear` empties it, and `/revenge log` says how many
  lines it has.

## v0.4.0

- Data from other PvP addons counts too: deaths and wanted players that guildmates and friends
  share through **Revenge Book**, **Grudgekeeper** or **HeadHunter**, and the players on your own
  **Kill on Sight** list. Each death still counts once, however many addons reported it.
- It's optional and switched on by default: Options › AddOns › Revenge › Other addons has a
  switch for all of it, one per addon, and a line saying how each is doing. `/revenge others off`
  switches it off from chat. Switched off, what only other addons reported is hidden at once, and
  their support doesn't load at all after `/reload`.
- Other addons can't slow or break Revenge: their messages wait their turn in a small queue that
  runs a little each frame and never in combat, and an addon whose data stops making sense is
  paused for the session without a word.
- Holding Shift on a tooltip says "via Revenge Book" (or whichever) for a kill only another
  addon reported.
- The release now holds a second folder, `RevengeTracker_OtherAddons`, which instawow installs
  with it.

## v0.3.0

- Sharing with in-game friends and Battle.net friends who run Revenge, each with its own switch
  under Sharing. Battle.net friends count only on WoW: Forever and your own faction.
- A small skull beside the nameplate of a recent killer or a Wanted player. The nameplate itself
  is left alone, whether it's the game's or an addon's.
- Skulls on the world map where recent deaths happened: coral for you, blue for friends, yellow
  for guildmates. Hover for who and when; right-click to dismiss a kill everywhere.
- Alerts, both on by default: when a recent killer or a Wanted player comes into view (at most
  once every 5 minutes per player), and when a friend or guildmate is killed. They show as a
  small silent popup that fades by itself, and in chat with a short sound; each can be
  switched off.

## v0.2.0

- Guild sharing: your deaths and the players you mark Wanted reach guildmates who run Revenge,
  and theirs reach you. Their kills show on the killer's tooltip and in your list, and their
  marks read "Wanted by" their name.
- Catch-up: when you log in, guildmates send what you missed while you were offline.
- Options › AddOns › Revenge has a new "Sharing" section to turn off sending your own.
- `/revenge test share` sends a test kill to your guild, to try it out.

## v0.1.0

The first release, for World of Warcraft: Forever.

- When enemy players kill you in the open world, Revenge remembers them. Battlegrounds,
  arenas, dungeons, raids and duels don't count.
- Hovering one of them adds a line to their tooltip: 💀 and how many times they've killed
  you recently. Hold Shift to see when and where.
- Options › AddOns › Revenge sets how long kills are remembered (7 days by default) and
  which key shows the details. It also lists your recent killers: remove anyone you're done
  with, or add a player by name to mark them "Wanted by you". `/revenge add First Last`
  does the same from chat.
- Not in this release yet: sharing with guildmates and friends, nameplate skulls, alerts
  and map pins.
