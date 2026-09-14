# tmux worktree workflow — technical documentation

A cross-platform (Linux/WSL + Windows/psmux) tmux setup that makes **one git
worktree = one tmux session**, launched from a single fzf popup.

```
<prefix>w  →  fzf picker (switch / checkout / clone)
```

- [Directory convention](#1-directory-convention)
- [The 5-window session contract](#2-the-5-window-session-contract)
- [The picker: data model, actions, keys](#3-the-picker)
- [Clone flow](#4-clone-flow)
- [Migration: converting old clones](#5-migration-of-existing-clones)
- [Cross-platform mechanics](#6-cross-platform-mechanics)
- [Deployment map](#7-deployment-map)
- [Extension points](#8-extension-points)
- [Known caveats](#9-known-caveats)

---

## 1. Directory convention

```
G:\Repository\Worktrees\          (or ~/Repository/Worktrees on Linux)
  <repo>/
    .bare/                        bare repo — all objects and refs
    .git                          text file:  gitdir: ./<repo>/.bare
    <repo>-<branch>/              worktree #1 (default branch)
    <repo>-<other-branch>/        worktree #2, ...
```

Every worktree is a **symmetric sibling** of every other — there is no
"special" primary checkout, so any worktree can be removed with
`git worktree remove` without special-casing.

Three rules hold the workspace together:

1. **Folder name** = `<repo>-<sanitized-branch>`. Sanitization maps `/` and
   `.` to `-` (`feature/x` → `feature-x`).
2. **tmux session name** = `<sanitized-branch>` (the folder basename, which
   is already the sanitized branch). One worktree ⇢ one session, 1:1.
3. **`$WORKTREE_ROOT`** is a single environment variable every script reads
   (with a filesystem fallback), so the layout can live anywhere.

Branch/folder names that collide (e.g. `feature/x` and `feature-x`) are
considered the same worktree — a known, accepted limitation of the naming
scheme (see [caveats](#9-known-caveats)).

## 2. The 5-window session contract

Every session created for a worktree boots exactly these five windows:

| # | Window    | Runs            | Purpose                    |
|---|-----------|-----------------|----------------------------|
| 1 | `neovim`  | `nvim .`        | editor                     |
| 2 | `lazygit` | `lazygit`       | git UI                     |
| 3 | `run`     | *(bare shell)*  | dev server / ad hoc cmds   |
| 4 | `lazysql` | `lazysql`       | sql database client        |
| 5 | `opencode`| `opencode`      | ai coding agent            |

The `run` window starts as a plain shell because the dev server command is
project-specific and changes by the minute; the other four are static.

Sessions are **idempotent**: the bootstrap (`tmux-worktree-session.sh`) skips
creation and attach/switch if the session already exists, so it is safe to
call from the picker, from a shell alias, or by hand.

## 3. The picker

`tmux-worktree.sh` is bound to `<prefix>w` via tmux `display-popup`:

```
bind-key -r w display-popup -E -w 90% -h 90% "bash ~/.local/scripts/worktree/tmux-worktree.sh"
```

### Data model

The script enumerates four kinds of fzf rows, each emitted as a
tab-separated record `type ⇥ repo ⇥ ref ⇥ label`. fzf's `--with-nth 4`
plus `--delimiter '\t'` keeps only the human-readable label visible while
the script still has structured fields to dispatch on.

| `type`      | `repo`        | `ref`               | semantics                                          |
|-------------|---------------|---------------------|----------------------------------------------------|
| `switch`    | repo name     | absolute path       | worktree on disk; live session shown in the label |
| `checkout`  | repo name     | remote branch name  | branch with no worktree yet                        |
| `newbranch` | repo name     | *(empty)*           | synthetic "+ New branch in <repo>" row             |
| `clone`     | *(empty)*     | *(empty)*           | pinned "+ Clone new repository" row                |

Row enumeration per repo:

```
bare repos        ← find $WORKTREE_ROOT -maxdepth 2 -name .bare -type d
worktrees         ← git --git-dir=<repo>/.bare worktree list --porcelain
                   (excludes <repo>/.bare itself)
un-worktree'd origin branches
                  ← git for-each-ref refs/remotes/origin, minus worktrees
                   whose sanitized name already exists on disk
```

### Actions

| Row type | `Enter` (smart)                                  | `s` (switch)         | `c` (checkout/clone)  |
|----------|--------------------------------------------------|----------------------|-----------------------|
| `switch` | switch into session (create if missing)          | switch               | *(ignored)*           |
| `checkout`| create worktree + boot 5-window session          | *(ignored)*          | create worktree + boot|
| `newbranch`| prompt for branch name → worktree + session     | *(ignored)*          | same as Enter         |
| `clone`  | gh-picker / URL → bare clone → worktree → session| *(ignored)*          | same as Enter         |

All keybinds resolve to the same `Enter` accept (`enter:accept,s:accept,c:accept`),
so the _action taken_ is determined purely by the row's `type` field, not by
which key was pressed. This keeps a single `case` dispatcher that is trivial
to extend.

`switch_or_attach` prefers `tmux switch-client` (we are inside tmux — the
picker runs in a popup) and falls back to `attach-session`.

## 4. Clone flow

Step 1 is an fzf picker over the GitHub REST API via the `gh` CLI:

```
gh api 'user/repos?affiliation=owner,collaborator,organization_member&per_page=100' --paginate --jq '.[] .full_name'
```

The `affiliation=owner,collaborator,organization_member` trio is deliberate:
the plain `gh repo list` only returns repos you *own*, which would hide
private repos you are invited to and org repos. This endpoint returns
everything your account can see.

If `gh` is missing/unauthenticated, or the repo is a public repo you have no
affiliation with, the flow degrades to a manual URL paste.

The clone creates a bare repo and normalizes it in four steps so the
worktree flow works identically for every branch:

1. The fetch refspec is repointed to a remote-tracking namespace
   (`+refs/heads/*:refs/remotes/origin/*`) and re-fetched — a bare clone only
   fetches the default branch and mirrors it into `refs/heads/*`;
2. `origin/HEAD` is resolved via `remote set-head origin -a`;
3. the mirrored `refs/heads/*` are dropped and the bare HEAD is parked on an
   unborn ref (`refs/heads/worktree-root`), because a bare HEAD pointing at a
   real branch makes git treat that branch as "checked out at `.bare`" and
   refuse `worktree add` on it;
4. the default branch is detected from `origin/HEAD` and immediately given
   its own worktree + session.

New worktrees branch off the tracked remote branch (`origin/<branch>`), and
new branches branch off `origin/HEAD` (the default branch).

## 5. Migration of existing clones

`tmux-worktree-migrate.sh <path>...` converts existing plain clones in place
**without touching them**:

1. Abort if the source repo has uncommitted changes (`status --porcelain`).
2. Re-clone bare **from the source's own `origin` remote** into
   `$WORKTREE_ROOT/<repo>/.bare` (never copies `.git` internals manually).
3. Create a worktree for the branch that was checked out.
4. The old directory is left untouched — cleanup is a manual, post-inspection
   step.

Use it for `Machine_Setups`, `Elixir/event-sourcing/lunar_frontiers_1`, etc.

## 6. Cross-platform mechanics

One config file, two OSes: psmux (the native Windows tmux) reads
`~/.tmux.conf` as a fallback config path, so the same file in `$HOME` is
picked up by both real tmux and psmux.

`tmux.conf` contains a single OS fork guarded by tmux >= 3.2 conditional
loading. The probe is deliberately **interpreter-agnostic** — an `if-shell`
test for `/etc/os-release`, which evaluates false under PowerShell (psmux's
default shell) and true under any POSIX shell:

```
%if '#{>=:#{version},3.2}'
  if-shell 'test -f /etc/os-release' \
    'source-file ~/.tmux.linux.conf' \
    'source-file ~/.tmux.windows.conf'
%else
  source-file ~/.tmux.linux.conf
%endif
```

- **`tmux.windows.conf`** sets `default-shell` to Git For Windows' bash and
  defines `WORKTREE_ROOT` via `set-environment -g`.
- **`tmux.linux.conf`** defines the Unix `WORKTREE_ROOT` and the `xclip`
  clipboard binding (xclip is Linux-only).

`WORKTREE_ROOT` is a tmux global-environment variable (`set-environment -g`),
so every pane, `run-shell` and `display-popup` process inherits it — no
per-shell `export` needed.

The picker and bootstrap scripts are **explicitly invoked via `bash`** in the
tmux config. This matters on Windows, where psmux's default shell is `pwsh`:
`run-shell`/`display-popup` would otherwise try to interpret bash scripts as
PowerShell. Naming the interpreter removes the ambiguity.

All scripts carry POSIX conventions but run under Git Bash on Windows, so one
bash implementation serves both OSes.

## 7. Deployment map

| Source (repo)                                          | Dest (live machine)        | OS      | Mechanism     |
|--------------------------------------------------------|----------------------------|---------|---------------|
| `Shared/tmux/tmux.conf`                                | `~/.tmux.conf`             | both    | symlink       |
| `Shared/tmux/tmux.windows.conf`                        | `~/.tmux.windows.conf`     | Windows | symlink       |
| `Shared/tmux/tmux.linux.conf`                          | `~/.tmux.linux.conf`       | Linux   | symlink       |
| `Shared/tmux/scripts/**`                               | `~/.local/scripts/worktree`| both    | symlink (dir) |
| `Windows/config/glazewm/config.yaml`                   | `.glzr/glazewm/config.yaml`| Windows | `linkconfig.ps1` |
| everything above (`.zshrc`, `.config/nvim`, scripts…)  | `$HOME` / `~/.local/scripts`| Linux   | `linkconfig.sh` |

Windows: `pwsh linkconfig.ps1` (self-elevates for symlink creation).
Linux: `./linkconfig.sh` (symlinks need no elevation).

## 8. Extension points

- **Add a 6th window** — edit the two `switch_or_attach` bootstraps
  (`tmux-worktree.sh`, `tmux-worktree-session.sh`); they are intentionally
  kept in sync.
- **Move `$WORKTREE_ROOT`** — it is *not* hardcoded: each OS override conf
  defines its own value via `set-environment -g WORKTREE_ROOT`
  (`tmux.windows.conf` → `G:/Repository/Worktrees`, `tmux.linux.conf` →
  `$HOME/Repository/Worktrees`). Change it there whenever the folder layouts
  diverge; the scripts fall back to their own default only if the env var is
  unset.
- **Change sanitization** — edit `sanitize()` in `lib/worktree-lib.sh`.
- **Add a new row type** — emit a new tag in the list builder, add a case in
  the dispatcher.

## 9. Known caveats

- **Name collisions**: branches that sanitize to the same string (e.g.
  `feature/x` and `feature-x`) resolve to the same worktree folder.
- **`if-shell` / `%if` version gating**: psmux tracks tmux 3.3.8 and the
  `if 'command' 'a' 'b'` form used for the OS fork needs tmux >= 3.2; older
  tmux falls back to the Linux branch. Verify `tmux -V` on each machine.
- **`display-popup -E`** closes the popup when the command ends — on psmux
  the second `fzf` (the gh clone picker) runs inside the first popup.
  Seamless in practice, but the popup won't "persist".
- **`Worktree no longer exists`**: `git worktree prune` in an on-disk worktree
  that was removed externally leaves stale rows; the picker guards the
  `switch` path against missing dirs.
- **LazyGit/LazySQL/opencode are assumed installed** — the bootstrappers
  `send-keys` their commands without checking availability.
- **Migration is conservative by design** — dirty trees abort so nothing is
  ever lost or auto-committed.