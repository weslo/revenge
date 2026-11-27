# Revenge

A lightweight addon for **World of Warcraft: Forever** (interface 16001). When you hover an
enemy player, it shows whether they recently killed you, a friend or a guildmate, so you can
get your revenge.

**Status:** early development. It tracks your deaths and shares them with guildmates and friends who
run Revenge, marks recent killers on their tooltip and nameplate and on the world map, and alerts
you when one comes into view or a friend is killed. It can also use what guildmates and friends share
through Revenge Book, Grudgekeeper and HeadHunter, and your Kill on Sight list. What's in each version:
[changelog](CHANGELOG.md).

## Install

With [instawow](https://github.com/layday/instawow):

```
instawow install github:weslo/revenge
```

Or download the `Revenge-…-forever.zip` file from the
[latest release](https://github.com/weslo/revenge/releases/latest) and unzip it into
`World of Warcraft\_forever_\Interface\AddOns`, so that you get the `AddOns\RevengeTracker` and
`AddOns\RevengeTracker_OtherAddons` folders. Then restart the game. The second one is optional: it's
what reads other addons' data, and Revenge loads it only while that's switched on.

## Development

- Work is tracked in [Issues](https://github.com/weslo/revenge/issues), one per increment. Each is
  built on a `feature/<issue>-<name>` branch and lands through a pull request that closes its Issue.
- The addon is the `RevengeTracker/` folder, and the optional, load-on-demand module that reads
  other addons' data is `RevengeTracker_OtherAddons/`. For live testing, link each into the game:
  `New-Item -ItemType Junction -Path "<WoW>\_forever_\Interface\AddOns\RevengeTracker" -Target "<repo>\RevengeTracker"`
  (and the same for `RevengeTracker_OtherAddons`), then `/reload` in game after each change.
- Static checks: `luacheck .` (config in `.luacheckrc`), and `python -I tools/check_lua51.py`. The second
  flags Lua 5.2+ syntax that luacheck 1.2.0 accepts but WoW's Lua 5.1 can't run.
- Offline tests run under real Lua 5.1 against a mock of the game's API (`tests/wow_mock.lua`):
  set up once with `python -m venv .venv` and `.venv\Scripts\python.exe -m pip install lupa==2.8`,
  then run `.venv\Scripts\python.exe -I tests\run.py` (optionally with a test-name filter).
- In game: `/revenge` opens the settings (with the list of recent killers), `/revenge add First Last`
  marks a player Wanted by you, `/revenge test` records a test kill by your target,
  `/revenge test share` also sends it to guildmates running Revenge, and `/revenge test clear` removes
  test kills. `/revenge others` says what other addons' data is in use (`on`/`off` switches it).
  `/revenge log on` keeps a diagnostic log in saved data (`off`, `clear`), and `/revenge debug` toggles
  debug lines in chat.
- To review play with the diagnostic log on: `/reload` or log out (the game writes saved variables then),
  then run `python -I tools/review_log.py` (add `--summary` for just the checks). It finds
  `RevengeTracker.lua` under the game's `WTF` folder, or takes a path, and prints the log in local time,
  which checks have evidence, what's stored and Bugsy's errors that mention Revenge. It parses the saved
  file as data and never runs it.
- CI (`.github/workflows/build.yml`) runs the checks and tests above on every pull request and
  push to `main`. It also builds the release zip with the
  [BigWigs packager](https://github.com/BigWigsMods/packager) (settings in `.pkgmeta`), without
  uploading it, and `tools/check_package.py` checks that the zip holds only the two addon folders.
- To release: add the version's section to the top of `CHANGELOG.md`, merge it, then tag `main`
  (`git tag v0.2.0`, `git push origin v0.2.0`). The workflow publishes the GitHub release, with
  the zip and the `release.json` that instawow reads. The TOC's `@project-version@` becomes the tag.

- What it will do: [requirements](docs/plans/revenge/REQUIREMENTS.md)
- Build order and progress: [implementation matrix](docs/plans/revenge/IMPLEMENTATION-MATRIX.md)
- Reading other PvP addons' shared data: [other addons](docs/plans/revenge/OTHER-ADDONS.md)
- How Revenge shares with guildmates: [protocol](docs/plans/revenge/PROTOCOL.md)

## License

[MIT](LICENSE). The release zip doesn't carry the LICENSE file, since it holds only the two addon
folders; both TOCs say `## X-License: MIT`.
