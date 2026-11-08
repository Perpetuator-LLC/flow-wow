# Working on Flow (for Claude and other AI assistants)

Flow is a World of Warcraft: Forever addon (Lua 5.1, interface 16001): a levelling companion
with a rotation helper, route planner and arrow, gear scoring, bag sorting and profession
plans. Read [README.md](README.md) for what it does and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it's built.

## The one design rule

**Extend by registering, don't edit the core.** `Core.lua` has registries
(`ns:Register(kind, key, value)`, `ns:Get`, `ns:Each`). New classes, rotations, advisors,
route goals, profession guides, item sources, gear analyzers, setup rows and tests are new
registrations, usually in a new file listed in `Flow.toc`. The table of registry kinds is in
`docs/ARCHITECTURE.md`. If a change seems to need edits all over the core, look for the
registry first, or add one.

## Map of the code

| Path | What |
|---|---|
| `Flow.toc` | Load order. Every new file must be listed here or WoW never loads it. |
| `Core.lua` | Event bus (`ns:On`), registries, saved data (`ns:OnLoad`), `/flow` commands (`ns.commands.x`). |
| `Classes/<Class>/` | Class data, trainer spells, rotation. Only Paladin so far: adding a class is a great first contribution. |
| `Modules/Rotation/` | Rotation engine, cast button/key, the Forever API shims (`Compat.lua`, `ns.api`). |
| `Modules/Nav/` | Route: goals (`Goals.lua`), planner, arrow and panels (`Nav.lua`), world map (`MapOverlay.lua`), tracker. |
| `Modules/Crafting/` | Profession guides, recorded recipes, skill plans that become route stops. |
| `Modules/Gear/`, `Modules/Items/` | Gear scores per role, bag icons, selling, keep reasons. |
| `Modules/Advisor/` | The advice list. |
| `Modules/Tests.lua` | Self-tests. |
| `tools/` | PowerShell: read the in-game diagnostics, analyse combat logs, package a release, render the CurseForge graphics. |

## Testing: there is no Lua interpreter, tests run in the game

- Add a test for every behaviour you change: `ns:Register("test", "area: what it checks", function(t) ... end)`
  in `Modules/Tests.lua`, using `t:ok(cond, msg)`, `t:eq(a, b, msg)`, `t:near(a, b, tol, msg)`.
  Restore any saved data you change inside a test.
- Tests run on every `/reload` and with `/flow test`. The results are saved with the
  diagnostics snapshot, which you can read without asking the player to copy anything:
  `powershell -ExecutionPolicy Bypass -File tools\read-diag.ps1`. It finds the WoW folder and
  account by itself (override with `FLOW_WOW_DIR` / `FLOW_WOW_ACCOUNT`).
- The saved file is written when the game reloads or logs out, so it shows the **previous**
  session. Ask the player to `/reload` (twice if you need the run that includes your change).
- Useful in game: `/console scriptErrors 1`, `/flow api` (which APIs this client has),
  `/flow rot why`, `/flow nav why`.
- With the repo junctioned into `Interface\AddOns\Flow`, `/reload` picks up edits.

## Blocked actions ("Flow has been blocked from an action only available to the Blizzard UI")

These are taint bugs and always ours to fix. **Every time you read the diagnostics, check the
"Blocked actions" section** that `tools\read-diag.ps1` prints (and the `taint.log` lines under it).
If anything is there, fix it before other work, even if nobody mentioned it:

1. The log line names the blamed add-on, the protected function and what was open.
2. `taint.log` (developer installs turn it on: `## X-Flow-Dev: 1` in `Flow.toc`) says which
   Flow line first tainted the path.
3. Fix the cause, not the symptom. Usual causes: assigning a Blizzard global or table
   (`StaticPopupDialogs = ...`), calling Blizzard panel functions from add-on code
   (`ShowUIPanel`/`HideUIPanel` on their frames, `HandleUserActionToggleSidePanel`), or changing
   protected frames or settings in combat.
4. Add a test (see "taint:" tests in `Modules/Tests.lua`, which use `issecurevariable`).
5. If you can't tell the root cause from the log and taint.log, ask the player what they clicked.
   Don't guess-fix.

## WoW: Forever quirks (learned the hard way)

- **Secret values:** player health and some unit data are hidden from addons. Code must cope
  with `nil`/secret values; `ns.api.Safe(x)` unwraps what it can.
- **Auras** can error when read from tainted code: `Compat.lua` wraps them in `pcall` and falls
  back to remembering your own casts.
- **Combat lockdown:** a secure button can't change what it casts in combat, so the cast key is
  locked to one spell at the pull. Don't try to retarget, interrupt or heal others in combat.
- Macro-type secure buttons are ignored on Forever; use `type = "spell"`.
- `UnitPosition` height is always 0 (no elevation), and nameplate positions are restricted
  ("Can't measure restricted regions").
- Item IDs can differ from classic: match tools and materials by ID **or** name.
- Talents use `C_ClassTalents` / `C_Traits`, not the classic talent API.
- Some item globals are gone (`GetItemCount` lives in `C_Item`). Use `ns.api.Count(id)`,
  `ns.api.ItemInfo`, `ns.api.ItemIcon`, `ns.api.IsUsableItem` (Compat.lua), never the bare globals.
- Never move, resize, show or hide a secure frame (the cast button) in combat, and finish any
  drag of one in `PLAYER_REGEN_DISABLED` (see `ns.cast:EndMove`).

## Lua gotchas that have bitten us

- **Backslashes:** texture paths need doubled backslashes, `"Interface\\Icons\\X"`. In Lua 5.1
  `"\I"` silently becomes `"I"` and the texture is blank. Run `tools\check-paths.ps1` before
  committing: shell heredocs and sed tend to eat one of the two backslashes.
- A `local` must be declared before any function that uses it is defined.
- `ns:Register` errors on a duplicate key; tests that register helpers must do it once, at
  file level.

## Data rules

- **Don't copy Questie (or other addons') data into this repo.** Flow reads Questie/QuestieDB
  at runtime when they're installed; that's the arrangement.
- Profession and item data in `Modules/Crafting/Guides.lua` is our own, approximate, and
  corrected by what the game shows.
- **Saved data is shared by every character on the account** (`FlowDB`) unless you declare it
  per character. Anything about one character (its fights, trainer, recipes, spells, bars,
  choices for this character) gets `ns:PerCharacter("section")` or
  `ns:PerCharacter("section.field")` next to its `ns:OnLoad` (see `charData` in
  docs/ARCHITECTURE.md). Settings, learned trails and NPC places stay shared.

## Style

- Comments explain *why* and what the player sees, in plain English.
- Player-facing text is short, plain and specific ("Loot Stringy Wolf Meat 9/66"), never
  jargon.
- Keep features optional and quiet: nothing should nag; the route should just be right.
- Every Flow panel gets its title bar from `ns.theme:TitleBar(parent, title, icon)`
  (`Modules/Theme.lua`): the same dark bar, orange accent and gold title as the Flow Tracker,
  Router and Seller. Colours come from `ns.theme`, never hard-coded per panel.

## Every change

1. Code + a test in `Modules/Tests.lua`. For anything the player clicks (a button, a menu, a
   dropdown), add a **click test**: call its OnClick script in a `pcall` the way a click would,
   and check what should appear did (see "click:" tests). Self-tests run 8 s after every login
   and print one red chat line if any fail, so a broken button is flagged before it's clicked.
   Anything that builds a menu goes through `ns.menu:RouteItems()`-style safe builders: one
   failing entry must not stop the menu opening.
2. Before committing, run `powershell -ExecutionPolicy Bypass -File tools\lint.ps1` and get it
   to **0 warnings** (it runs luacheck with `.luacheckrc`, then `check-paths.ps1`). It catches
   a missing `local`, a `local` used before it's declared, typos in names and unused values.
   Fix the code rather than widening `.luacheckrc`; use `_` for values you don't need.
   Lint can't see game values that differ on Forever (vectors that are plain tables, globals
   moved into `C_*`): those need an in-game test.
3. Bump `## Version:` in `Flow.toc` (patch number) and add a `CHANGELOG.md` entry at the top,
   written for players.
4. If you add a registry kind, a command or a feature, update `docs/ARCHITECTURE.md` and the
   README feature list.
5. One commit per change, message `Flow x.y.z: what changed`.
