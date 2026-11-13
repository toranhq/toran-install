<p align="center">
  <img src="assets/toran.svg" width="96" height="96" alt="Toran">
</p>

<h1 align="center">Install Toran</h1>

<p align="center">
  The install scripts behind <a href="https://toran.run">toran.run</a>.
</p>

---

**Toran** drives GitHub issues to merged pull requests. A watch on each machine in your pool picks
the next step for every issue you label, and headless coding agents (Claude Code, Codex,
Antigravity) do the work under audited skills, on your machines, under your own GitHub Apps.

This repository holds only the install scripts. Every Toran release publishes them here, and
GitHub Pages serves them at `toran.run`.

## Install

**Windows 11** (PowerShell):

```powershell
irm https://toran.run/install.ps1 | iex
```

**macOS and Linux:**

```sh
curl -fsSL https://toran.run/install.sh | sh
```

Then follow `toran setup`. It checks the machine, offers to install what is missing and signs your
agents in.

> These lines go live with the first release that publishes the scripts here. Until then, use the
> install command you were given with your access.

## What the script does

The script is short and holds no secret. Read it before you run it:
[`install.ps1`](install.ps1), [`install.sh`](install.sh).

1. Shows what it will install and asks before installing anything.
2. Installs the GitHub CLI and Git if they are missing, from your platform's own source: `winget`
   on Windows, Homebrew on macOS, GitHub's apt or dnf repository on Linux.
3. Signs you in to GitHub with `gh auth login` if you are not signed in, and asks for the
   `read:packages` scope (one browser approval).
4. Downloads the Toran binary for your OS and architecture, and checks its SHA-256 against the
   release before it runs it.
5. Installs it for your user only (`~/.local/bin/toran`, or `%LOCALAPPDATA%\Programs\toran` on
   Windows), adds that folder to your PATH, and starts `toran setup`.

It never stores a token itself, never asks for administrator rights on its own, and changes
nothing outside the install folder and your PATH.

## Requirements

- Windows 11 x64, macOS (Apple silicon or Intel), or Linux x64/arm64 with glibc 2.28 or later.
- A GitHub account with access to Toran.
- A subscription to at least one coding agent: Claude Code, Codex or Antigravity.

## Access

Toran is in private release. Access is granted per GitHub account; ask your Toran contact.
If the script stops with `no access to ghcr.io/...`, run
`gh auth refresh -h github.com -s read:packages` and try again. If the message stays, your account
has no access yet.

## Security

Please report a vulnerability privately; see [SECURITY.md](SECURITY.md).

## License

The scripts in this repository are licensed under the [MIT License](LICENSE). Toran itself is
proprietary software of 116 Ideas, Inc. and is not covered by that license; its use is governed by
the terms you accept when you install it.

Toran™ is a trademark of 116 Ideas, Inc.
