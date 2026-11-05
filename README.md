# SoothMod

Sooth's personal World of Warcraft addon: one place to put whatever features we want.

## Layout

- `SoothMod.toc`: addon manifest (load order, saved variables, interface version)
- `Core.lua`: shared namespace `ns`, event bus (`ns:On(event, fn)`), `/sooth` slash command, `SoothModDB` saved vars
- `Modules/`: one file per feature. Add a file, then list it in the `.toc`.

## Features

- **Greeting**: shows a "hello sooth" dialog on login. `/sooth hello` shows it again.

## Install (dev)

The addon folder in the game is a junction pointing at this repo, so edits here are live after `/reload`:

```
G:\Blizzard\World of Warcraft\_forever_\Interface\AddOns\SoothMod  ->  H:\SoothMod
```

## Interface version

The `## Interface:` number in the `.toc` must match the client, or the addon shows as "out of date".
In game, run `/dump select(4, GetBuildInfo())` to get the right number and put it in the `.toc`.
