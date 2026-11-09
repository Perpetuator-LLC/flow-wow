# Talk to Claude from inside WoW (and keep Flow up to date by itself)

Type `/claude make the arrow green` in game. A Claude session on your PC (Claude desktop's Code
tab, or any Claude Code) picks it up, works in your Flow folder, so it can answer **and change
Flow itself**, and its answer shows in your chat window as "Claude: ..." after `/claude` (a
reload), together with the change.

A small script on your PC, `tools\claude-bridge.ps1`, passes the messages along, and also keeps
Flow up to date: each time WoW saves (a `/reload`, logout or exit), it checks GitHub and brings a
clean copy of Flow up to the newest version, then tells you in game.

Everything stays on your PC: WoW writes Flow's saved data, the script reads it and writes an
answers file back. Nothing is sent anywhere except what your Claude session itself sends to Claude.

## How it works

WoW addons can't open files or the network. The only way out is Flow's saved data, which WoW
writes to disk when the UI reloads; the only way in is a file in the addon folder, which WoW reads
when the UI loads. So:

1. `/claude <message>` (or the short `/ai` or `/si`): Flow saves the message and reloads the UI (a few seconds), so WoW writes it
   to `WTF\Account\<you>\SavedVariables\Flow.lua`.
2. `tools\claude-bridge.ps1` is woken by Windows when that file changes (it doesn't poll) and
   prints one line per new message:
   `ASK 3 | Sooth (DRUID 5, Mulgore) | make the arrow green`
3. Your Claude session watches those lines (its Monitor tool), does what's asked in the Flow
   folder, and answers with
   `powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1 -Reply 3 -Text "Done. Type /reload."`
   which writes `Learned\ClaudeInbox.lua`.
4. **Check now** in the chat window (or `/claude check`) reloads the UI: WoW reads the answers file
   (and any code Claude changed), and Flow prints the answers. `/claude` on its own opens the chat
   window: what you asked, the answers, a box to type in, Send and Check now.
5. **Deaths:** when you die, Flow saves a death report (what Flow suggested, what you cast, when
   the low-health warning came on, the enemy). At your next reload the bridge passes it on as a
   `DEATH` line. The watching Claude session does a post-mortem (CLAUDE.md): how the easy button
   could have prevented it. It makes that improvement and tells you in a note.

## Setup

1. **Flow from GitHub, linked into the game.** Clone `https://github.com/Perpetuator-LLC/flow-wow`
   and link it as `Interface\AddOns\Flow`; see [CONTRIBUTING.md](../CONTRIBUTING.md). (The
   updater only updates a clone; a copy unzipped from CurseForge updates through CurseForge.)
2. **A Claude session in your Flow folder.** In Claude desktop (Code tab) or Claude Code, open
   the Flow folder and say: **"Watch Flow's in-game chat."** It starts the bridge with its Monitor
   tool and answers every `/claude` you type (CLAUDE.md tells it how). Keep that session open
   while you play.
3. In game: `/claude hello`, then `/claude` a moment later to see the answer.

### Only updates, no Claude

Run the bridge by itself, in its own window, and it just keeps Flow up to date:
```
powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1 -NoAsk
```
To start that with Windows (change the path to your Flow folder):
```
schtasks /Create /SC ONLOGON /TN "Flow updates" /TR "powershell -WindowStyle Minimized -ExecutionPolicy Bypass -File C:\path\to\flow-wow\tools\claude-bridge.ps1 -NoAsk"
```
Remove it with `schtasks /Delete /TN "Flow updates"`.

## Options

| | |
|---|---|
| (none) | listen: print `ASK` / `DEATH` / `UPDATE` lines for a Claude session, keep Flow up to date |
| `-Reply ID -Text "..."` | answer message ID (shown in game after `/claude` or `/reload`) |
| `-Note "..."` | tell the player something with no message to answer |
| `-NoAsk` | only keep Flow up to date |
| `-NoUpdate` | only pass messages on |
| `-Cli` | answer by itself with the `claude` command line instead of a watching session (needs Claude Code's CLI; `-Permission acceptEdits` or `bypassPermissions`) |
| `-AddonDir PATH` | your `AddOns\Flow` folder, if it isn't a link to the clone |
| `-SelfTest` | check the file reading and writing, then exit |

## What gets updated, and what doesn't

- A clone on the `main` branch with **no changes of its own** fast-forwards to the newest Flow.
  In game you see "Flow updated: 0.35.80 -> 0.35.81. Type /reload to load it." (or "Restart WoW",
  when the update adds files).
- A clone with **your own changes** (for example ones Claude made for you from `/claude`) isn't
  touched: you're told an update is waiting. Ask Claude to open a pull request with your changes,
  or to set them aside, and updates resume.
- A clone on **another branch** (the maintainer's) is never touched.

## When you change Flow from the game

On a clone that follows `main`, Claude changes the files but doesn't commit or bump the version:
you see the change after `/reload`, and you can send it to the project as a pull request (see
[CONTRIBUTING.md](../CONTRIBUTING.md)). The maintainer's own clone (not on `main`) commits as
[CLAUDE.md](../CLAUDE.md) describes, and never pushes.
