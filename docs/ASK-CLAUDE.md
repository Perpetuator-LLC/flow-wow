# Talk to Claude from inside WoW (and keep Flow up to date by itself)

Type `/si make the arrow green` in game (or `/ai`, `/claude`). A Claude session on your PC
(Claude desktop's Code tab, or any Claude Code) picks it up straight away, with no reload. It works
in your Flow folder, so it can answer **and change Flow itself**. Its answer shows in Flow Chat
(`/si`) after you press **Reload** there, together with the change.

**Not connected yet?** `/si` on its own then shows a prompt to copy (it's already selected: press
Ctrl+C) into a Claude Code session on your PC. It sets that session up: it finds your Flow source,
runs the bridge, and starts watching. Press Reload once it says it's ready. `/si setup` shows the
prompt again.

A small script on your PC, `tools\claude-bridge.ps1`, passes the messages along, and also keeps
Flow up to date: each time WoW saves (a `/reload`, logout or exit), it checks GitHub and brings a
clean copy of Flow up to the newest version, then tells you in game.

Everything stays on your PC: WoW writes Flow's saved data, the script reads it and writes an
answers file back. Nothing is sent anywhere except what your Claude session itself sends to Claude.

## How it works

WoW addons can't open files or the network while the game runs. Flow's saved data is written to
disk only at a reload (or logout), and the addon's own files are read only when the UI loads. But
WoW writes a **screenshot** (`_forever_\Screenshots`) at once, and addons may take one. (WoW:
Forever's chat log doesn't work for this: it never wrote Flow's whispers to the file.) So:

1. **Sending, no reload:** `/si <message>` (or Send in Flow Chat). Flow shows the message for a
   moment as a block of black and white squares in the top left of the screen (a simple code),
   takes a screenshot and hides them. You see a quick flash and "Screen captured". The message
   also goes into Flow's saved data, so if the screenshot doesn't carry it, the next reload
   does. (`/flow chat live off` sends by reloading instead.)
2. `tools\claude-bridge.ps1` is woken by Windows when a screenshot or `Flow.lua` appears or
   changes (it doesn't poll). It decodes Flow's screenshot, deletes it (your own screenshots are
   left alone), and prints one line per new message:
   `ASK 3 | Sooth (DRUID 5, Mulgore) | make the arrow green`
3. Your Claude session watches those lines (its Monitor tool), does what's asked in the Flow
   folder, and answers with
   `powershell -ExecutionPolicy Bypass -File tools\claude-bridge.ps1 -Reply 3 -Text "Done. Press Reload."`
   which writes `Learned\ClaudeInbox.lua`.
4. **Answers need a reload**, the only time WoW reads Flow's files. Press **Reload** in Flow Chat
   when you want them. That also loads any change Claude made to Flow, so you decide when.
5. **Connected:** while the bridge runs, it writes the time into `Learned\ClaudeInbox.lua` every
   10 minutes. If that was recent at your last reload, `/si` opens the chat; otherwise it opens
   the connect prompt.
6. **Deaths:** when you die, Flow saves a death report (what Flow suggested, what you cast, when
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
   Or, from the game: `/si` (not connected yet) shows a prompt that does all of this; paste it
   into a Claude Code session.
3. In game: Reload in Flow Chat once Claude says it's ready, then `/si hello`. Press Reload a
   moment later to see the answer.

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
| `-Reply ID -Text "..."` | answer message ID (shown in game after Reload in Flow Chat, or `/reload`) |
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
