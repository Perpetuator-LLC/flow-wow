# Contributing to Flow

Thanks for helping! Flow is built to be extended without touching its core, so most
contributions are a new file or a new registration.

## Quick start (about 5 minutes)

1. Install World of Warcraft: Forever, and ideally **Questie** + **QuestieDB** (Flow reads their
   quest data at runtime).
2. Clone this repo, then link it into the game so `/reload` picks up your edits
   (Command Prompt; adjust the WoW path):
   ```
   mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Flow" "C:\path\to\flow-wow"
   ```
3. In game: `/console scriptErrors 1`, `/reload`, then `/flow test`. Everything should pass.
4. After a `/reload`, read what Flow saw (tests, logs, diagnostics) from outside the game:
   ```
   powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1
   ```

## Using Claude (or another AI assistant)

Point it at this folder and ask for what you want ("add a Warrior rotation", "Flow should
plan Tailoring"). [CLAUDE.md](CLAUDE.md) gives it the design rule, the code map, how to test
in game and the Forever quirks. Ask it to run `tools\read-diag.ps1` after you `/reload` so it
can check its own work.

## Good first contributions

- **A new class:** `Classes/<Class>/Data.lua`, `Spells.lua`, `Rotation.lua`, listed in
  `Flow.toc`. See "Adding a class" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Profession data:** guides and item sources in `Modules/Crafting/Guides.lua` (Tailoring,
  Leatherworking, Alchemy, Engineering, Enchanting, Skinning have none yet).
- **Drop rates and Forever-specific item IDs** you've seen in game.
- **Tests** for anything that isn't covered.

## Pull requests

- One feature or fix per PR, with a test in `Modules/Tests.lua`.
- `powershell -ExecutionPolicy Bypass -File tools\lint.ps1` must say "lint OK" (needs
  [luacheck.exe](https://github.com/lunarmodules/luacheck/releases); the script says where to
  put it).
- Bump the patch version in `Flow.toc` and add a player-facing line to `CHANGELOG.md`.
- Say how you tested it in game (class, level, zone) and paste the `/flow test` result.
- Don't include data copied from other addons or sites.
- Flow is licensed under the [GPLv3](LICENSE). By sending a PR you agree your contribution is
  licensed the same way.

## Reporting a bug

Open an issue with what you did, what you expected, what happened, and the output of
`tools\read-diag.ps1` after a `/reload` (it has the error log and test results).
