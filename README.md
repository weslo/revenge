# Revenge

A lightweight addon for **World of Warcraft: Forever** (interface 16001). When you hover an
enemy player, it shows whether they recently killed you, a friend or a guildmate, so you can
get your revenge.

**Status:** early development. No release to install yet.

## Development

- The addon is the `RevengeTracker/` folder. For live testing, link it into the game:
  `New-Item -ItemType Junction -Path "<WoW>\_forever_\Interface\AddOns\RevengeTracker" -Target "<repo>\RevengeTracker"`,
  then `/reload` in game after each change.
- Static checks: `luacheck .` (config in `.luacheckrc`), and `python -I tools/check_lua51.py`. The second
  flags Lua 5.2+ syntax that luacheck 1.2.0 accepts but WoW's Lua 5.1 can't run.
- In game: `/revenge` opens the settings, `/revenge test` records a test kill by your target, and
  `/revenge test clear` removes those. `/revenge debug` toggles a debug log.

- What it will do: [requirements](docs/plans/revenge/REQUIREMENTS.md)
- Build order and progress: [implementation matrix](docs/plans/revenge/IMPLEMENTATION-MATRIX.md)
- Reading other PvP addons' shared data: [other addons](docs/plans/revenge/OTHER-ADDONS.md)
