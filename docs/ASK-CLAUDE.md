# Talk to Claude from inside WoW (and keep Flow up to date by itself)

Type `/claude make the arrow green` in game. A small script on your PC hands the message to
Claude Code, working in your Flow folder, so it can answer **and change Flow itself**. The answer
shows in your chat window as "Claude: ..." after the next `/reload`, and so does the change.

The same script also keeps Flow up to date: each time WoW saves (a `/reload`, logout or exit), it
checks GitHub and brings a clean copy of Flow up to the newest version, then tells you in game.

Everything stays on your PC: WoW writes Flow's saved data, the script reads it and writes an
answers file back. Nothing is sent anywhere except what Claude Code itself sends to Claude.

## How it works

WoW addons can't open files or the network. The only way out is Flow's saved data, which WoW
writes to disk when the UI reloads; the only way in is a file in the addon folder, which WoW reads
when the UI loads. So:

1. `/claude <message>`: Flow saves the message and reloads the UI (a few seconds), so WoW writes it
   to `WTF\Account\<you>\SavedVariables\Flow.lua`.
2. `tools\claude-bridge.ps1` is woken by Windows when that file changes (it doesn't poll). It runs
   Claude Code (`claude -p`) in your Flow folder with the message, and writes the answer to
   `Learned\ClaudeInbox.lua` in your Flow folder.
3. `/claude` on its own reloads the UI: WoW reads the answers file (and any code Claude changed),
   and Flow prints the answers.

Claude keeps one conversation going between messages, so you can follow up ("now make it
brighter").

## Setup (once)

1. **Flow from GitHub, linked into the game.** Clone `https://github.com/Perpetuator-LLC/flow-wow`
   and link it as `Interface\AddOns\Flow`; see [CONTRIBUTING.md](../CONTRIBUTING.md). (The
   updater only updates a clone; a copy unzipped from CurseForge updates through CurseForge.)
2. **Claude Code**, the `claude` command: install it from
   https://docs.claude.com/en/docs/claude-code and run `claude` once to log in. (Only needed for
   `/claude`; updates work without it, with `-NoClaude`.)
3. **Start the bridge** from your Flow folder and leave the window open while you play:
   ```
   powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1
   ```
   It shows each message and answer as they go by. Ctrl+C stops it.

### Start it with Windows (optional)

So you never have to think about it, add a scheduled task that starts it when you log in to
Windows (change the path to your Flow folder):
```
schtasks /Create /SC ONLOGON /TN "Flow bridge" /TR "powershell -WindowStyle Minimized -ExecutionPolicy Bypass -File C:\path\to\flow-wow\tools\claude-bridge.ps1"
```
Remove it with `schtasks /Delete /TN "Flow bridge"`.

## Options

| | |
|---|---|
| `-NoClaude` | only keep Flow up to date (no Claude Code needed) |
| `-NoUpdate` | only answer `/claude` messages |
| `-Permission acceptEdits` | (default) Claude may edit Flow's files; other commands (lint, git) are refused |
| `-Permission bypassPermissions` | Claude may also run commands (lint, commit). Only on your own PC, for your own messages |
| `-AddonDir PATH` | your `AddOns\Flow` folder, if it isn't a link to the clone |
| `-SelfTest` | check the file reading and writing, then exit |

## What gets updated, and what doesn't

- A clone on the `main` branch with **no changes of its own** fast-forwards to the newest Flow.
  In game you see "Flow updated: 0.35.80 -> 0.35.81. Type /reload to load it." (or "Restart WoW",
  when the update adds files).
- A clone with **your own changes** (for example ones Claude made for you from `/claude`) isn't
  touched: you're told an update is waiting. Ask Claude (in game or in Claude Code) to open a
  pull request with your changes, or to set them aside, and updates resume.
- A clone on **another branch** (the maintainer's) is never touched.

## When you change Flow from the game

On a clone that follows `main`, Claude changes the files but doesn't commit or bump the version:
you see the change after `/reload`, and you can send it to the project as a pull request
(see [CONTRIBUTING.md](../CONTRIBUTING.md)). The maintainer's own clone (not on `main`) commits as
[CLAUDE.md](../CLAUDE.md) describes, and never pushes.
