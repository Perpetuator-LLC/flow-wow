# Publishing Flow on CurseForge

Status: prepared, not published. Building the zip works today (`tools/package.ps1`). The
steps that need your accounts and decisions are listed below.

## Before the first upload (decisions)
- [x] **Licence.** GPLv3 (`LICENSE`, the official gnu.org text; `## X-License: GPL-3.0` in the
  TOC). Pick "GNU General Public License version 3 (GPLv3)" on CurseForge. The package
  script puts `LICENSE` in the zip.
- [x] **Public name.** "Flow" is taken on CurseForge (an unlisted Forever project, checked
  2026-11-07), and names must be unique. Use **"Flow (unfettered)"**, the TOC title. Leave
  "Forever"/"WoW" out of the name: CurseForge's rules say no game names.
- [ ] **Author name** in `Flow.toc` (`## Author:`).
- [x] **Forever on CurseForge.** It is a flavour there: tag uploads with game version
  **1.60.1 (Forever)**.
- [x] **Graphics.** Avatar `docs/flow-logo.png` (400x400, CurseForge's size) and description
  banner `docs/flow-banner.png` (1800x440). Edit the `.svg` sources, then re-render with
  `powershell -ExecutionPolicy Bypass -File tools\render-graphics.ps1` (uses Edge headless).

## First upload (manual)
1. Create a CurseForge author account and a new World of Warcraft addon project.
2. Run `powershell -ExecutionPolicy Bypass -File tools\package.ps1`; it builds
   `dist\Flow-<version>.zip`.
3. Upload the zip, choose the game version, and paste in the changelog section for that version.
4. Copy the project ID into `Flow.toc` as `## X-Curse-Project-ID: <id>`.

## Later: automatic releases
Tag a version (`v0.15.0`) and let a Gitea Actions workflow run the BigWigs packager, with
`CF_API_KEY` stored as a repository secret. It reads `.pkgmeta` (to add then) and the TOC's
project ID.

## Blizzard addon policy (already met)
- The addon is free, and its code isn't obfuscated.
- It doesn't automate gameplay: suggestions only. Casting needs a key press or click, and in
  combat the key stays on one spell for the whole fight.
