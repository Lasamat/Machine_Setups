# PowerShell cheatsheet

What the profile at `Microsoft.PowerShell_profile.ps1` gives you. Verified against
a real load on 2026-10-07; PSReadLine 2.4.5, fzf 0.67, startup ~215ms.

Related: `scope.md` (work deliberately deferred).

---

## Keys — in Insert mode

| Key | What it does |
|---|---|
| `Ctrl+r` | fzf over your whole PSReadLine history, **newest first**. Pick → the command lands on the line, ready to edit. Never runs it. |
| `Ctrl+t` | fzf over files+dirs under the cwd. Only the **last token** on the line prefilters, so `cat ` + `Ctrl+t` shows everything, and `cat .\sco` prefilters `.\sco`. Pick → appended to the line, auto-quoted if it has a space or apostrophe. |
| `Alt+c` | fzf over zoxide's frecency list. Pick → jumps there immediately. |

All three look identical (same flags, one launch path) and render as a **popup
below the cursor**, not fullscreen.

`Esc` cancels any picker and leaves your line untouched.

Note `Ctrl+r` and `Ctrl+t` replace PSReadLine's defaults for those chords
(`ReverseSearchHistory` and `SwapCharacters`).

## Keys — always available (PSReadLine Vi mode)

`Esc` → Normal mode (prompt shows `[Normal]`), `i`/`a`/`o` → Insert, `v` → visual,
`dd`, `cw`, `yy`, `p`, `u` / `Ctrl+r` in Normal is vi-native undo-redo, `/` search,
`n` / `N` repeat search, `Ctrl+l` clear screen.

`Alt+1..9` digit arguments still work.

## Commands

| Command | What it does |
|---|---|
| `z <text>` | Jump by zoxide frecency. `z` alone → home. `z <existing path>` → literal `cd`. |
| `zi` | Same, but through an fzf picker. Typed as a command rather than a chord. |
| `yy` | yazi at the cwd; on quit your shell **cd's to wherever you ended up**. |
| `psm` | `psmux attach`. Not `ps` — that alias belongs to `Get-Process`. |
| `vim` | → `nvim` |
| `lzg` | lazygit |
| `lzd` | lazydocker |
| `gd` | gh-dash (`G:\T\Tools\gh-dash.exe`) |

Every directory you visit is recorded in zoxide's frecency db automatically, so
`z` and `Alt+c` get better the more you use them.

## POSIX commands, everywhere

The prompt rewrites these to GNU coreutils, so you get real flags and globbing:

```
ls  la  cat  cp  mv  rm  mkdir  rmdir  touch  ln  link  readlink  realpath
grep  find  head  tail  cut  sort  uniq  wc  tr  tee  xargs  seq  printf
date  du  df  stat  file-less tools like basename dirname factor factor expr numfmt
sha1sum sha224sum sha256sum sha384sum sha512sum md5sum cksum b2sum base32 base64
sleep  env  printenv  hostname  nproc  arch  pwd  which-ish shuf  tsort  split
```

`ls` gets `--color=auto` injected. `la` is a shorthand that runs
`ls -AFhl` (all, classify, human-readable, long).

Globbing works: `ls *.ps1`, `grep -i foo *.md`, `cat .\some\path`.

**Two things to know:**

- This only happens for lines you **type at the prompt**. Inside a function or
  script, `ls` is still `Get-ChildItem`, `cat` is `Get-Content`, `rm` is
  `Remove-Item`, `tee` is `Tee-Object`. Inherent to how the shim works.
- The shim depends on `$PSNativeCommandArgumentPassing` being `Windows`, which is
  the PowerShell 7 default here but is not pinned. See `scope.md` §2.

## Editor feel

- Vi mode with a `[Normal]` / `[Insert]` indicator in the prompt.
- `HistoryNoDuplicates` — consecutive repeats of the same command collapse, so
  ↑↑↑ skips the `ls` spam.
- Inline history prediction (discreet grey text, take it with `→`).
  ⚠️ Known issue: on PSReadLine 2.4.5 + PowerShell 7.6 this is currently
  **broken upstream** (PSReadLine issue #5116) and may show nothing at all. It
  works on 2.3.6. `Ctrl+r` covers the same need meanwhile.
- Custom syntax colouring.

## Things that deliberately do *not* happen

- **`Ctrl+r` never executes anything.** It only writes to the line. An earlier
  version auto-submitted and would have run `rm -rf` if you'd picked it.
- **No custom prompt.** You tore out posh-git / oh-my-posh on purpose, so the
  stock `PS C:\...>` prompt is kept. `scope.md` §4 has the details if you ever
  want one back.
- **No file-type icons.** Terminal-Icons was removed; it cost 451ms of a 740ms
  startup and never showed up on `ls` anyway, since the coreutils shim takes over
  before `Get-ChildItem` is reached. `scope.md` §8 has a lazy-load recipe if the
  `Get-ChildItem` icons are ever missed.

## Startup

~215ms, down from ~730ms. The big wins were dropping Terminal-Icons (−451ms),
replacing the old `z` PowerShell module with hand-rolled zoxide glue (−146ms), and
unpinning PSReadLine so the bundled 2.4.5 loads instead of 2.2.6.

## Gotcha worth internalising

**A shell reads the profile once, at startup.** After editing the profile you
must open a **new** window — editing `. $PROFILE` in a live session does not
re-register key handlers. Two rounds of debugging were lost to this; it's the
single most likely reason a change "did nothing".

For a throwaway shell, `pwsh -NoProfile` is still there — just skip the profile.

## Quick self-check

```powershell
Get-Module PSReadLine                              # 2.4.5, one version only
(Get-PSReadLineOption).EditMode                    # Vi
Get-PSReadLineKeyHandler -Bound | Where-Object Key -in 'Ctrl+r','Ctrl+t','Alt+c'
```