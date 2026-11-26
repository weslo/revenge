# Revenge changelog

## Unreleased

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
