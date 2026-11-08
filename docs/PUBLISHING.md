# Publishing Flow on CurseForge

Status: **live** since 2026-11-08: [Flow (unfettered)](https://www.curseforge.com/wow/addons/flow-unfettered),
project ID **1790624** (`## X-Curse-Project-ID` in `Flow.toc`), game version 1.60.1 (Forever).
Every GitHub release uploads itself there (below). The first upload was done by hand.

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
3. Upload the zip, choose the game version, and paste in the changelog section for that version
   (only the newest `## x.y.z` section of `CHANGELOG.md`; set the changelog type to Markdown).
   The project **description** is where the feature list goes: adapt the README's Features.
4. Copy the project ID into `Flow.toc` as `## X-Curse-Project-ID: <id>`.

## Source code
Public on GitHub: https://github.com/Perpetuator-LLC/flow-wow (`main`, remote `github`). Put
this in the CurseForge project's Source link. Push with the GitHub CLI's credentials:
`git -c credential.helper= -c 'credential.helper=!"C:/Program Files/GitHub CLI/gh.exe" auth git-credential' push github flow-0.10:main`.
Commits use the GitHub no-reply address (repo-local `user.email`), never a personal email.

## Automatic releases (every GitHub release goes to CurseForge)
Each release published on GitHub (`v0.35.97`, with its `Flow-<version>.zip`) starts the
GitHub Action [`.github/workflows/curseforge.yml`](../.github/workflows/curseforge.yml). It
downloads that zip and runs `tools\curseforge-upload.ps1`, which uploads it to project 1790624:
- tagged with the game version from `## Interface` (16001 -> 1.60.1, the Forever flavour);
- with that version's `CHANGELOG.md` section as the changelog (Markdown);
- as a "release".

**One-time setup (the maintainer):**
1. On CurseForge, make an API token: authors.curseforge.com, your account, **API tokens**.
2. On GitHub, add it as a repository secret named **`CF_API_TOKEN`**:
   [Settings > Secrets and variables > Actions > New repository secret](https://github.com/Perpetuator-LLC/flow-wow/settings/secrets/actions/new).
   Never put the token in a file or a commit.

Without the secret, the Action only warns ("not uploaded to CurseForge"), and releases still work.

**An existing release** (one from before the secret, or one whose upload failed): on GitHub,
open **Actions > CurseForge > Run workflow** and enter its tag (for example `v0.35.96`). Or run
`gh workflow run curseforge.yml -f tag=v0.35.96`.

**By hand:** `$env:CF_API_TOKEN = "<token>"`, then
`powershell -ExecutionPolicy Bypass -File tools\curseforge-upload.ps1 -Zip dist\Flow-<version>.zip`.
`-DryRun` shows what it would upload without a token.

## Blizzard addon policy (already met)
- The addon is free, and its code isn't obfuscated.
- It doesn't automate gameplay: suggestions only. Casting needs a key press or click, and in
  combat the key stays on one spell for the whole fight.
