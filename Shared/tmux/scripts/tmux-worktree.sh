#!/usr/bin/env bash
# ── worktree picker (<leader>w) ─────────────────────────────────────────────
# Opens an fzf popup listing:
#   • worktrees with a live tmux session      → Enter switches in
#   • worktrees on disk, no session yet       → Enter switches in (bootstrap 5-window layout)
#   • branches with no worktree yet           → Enter checks out into a new worktree
#   • "+ New branch in <repo>"                → Enter prompts for a branch name
#   • "+ Clone new repository"                → Enter clones via gh (or URL paste) + worktree
# Keys:  Enter = smart default   s = switch only   c = checkout/clone only
#
# Rows are tab-separated:  type ⇥ repo ⇥ ref ⇥ label

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/worktree-lib.sh"

WORKTREE_ROOT="$(resolve_worktree_root)"
WORKTREE_ROOT="$(cd "$WORKTREE_ROOT" && pwd)"

# ── helpers ─────────────────────────────────────────────────────────────────

setup_bare() { # $1 = repo dir (absolute)   $2 = clone URL
  local repo="$1" url="$2"
  local bare="$repo/.bare"
  mkdir -p "$repo"
  git clone --bare "$url" "$bare" >/dev/null 2>&1 || return 1
  git --git-dir="$bare" config --bool core.bare false
  echo "gitdir: $bare" > "$repo/.git"
  # a bare clone only fetches the default branch and mirrors it into
  # refs/heads/*; repoint the refspec at a remote-tracking namespace and
  # fetch everything under refs/remotes/origin/*
  git --git-dir="$bare" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git --git-dir="$bare" fetch origin --prune 2>/dev/null || true
  git --git-dir="$bare" remote set-head origin -a 2>/dev/null || true  # origin/HEAD
  # drop the mirrored local branches so no ref is "checked out" at the bare
  # repo (that would block `worktree add`), then park HEAD on an unborn ref
  git --git-dir="$bare" for-each-ref --format='%(refname)' refs/heads | while read -r r; do
    git --git-dir="$bare" update-ref -d "$r"
  done
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/worktree-root
  git --git-dir="$bare" remote set-url --push origin "$url" 2>/dev/null || true
}

add_worktree() { # $1 = repo (abs)  $2 = branch  $3 = target dir (abs)  $4 = start-point (optional)
  local repo="$1" branch="$2" target="$3" start="${4:-}"
  if [[ -n "$start" ]]; then
    git --git-dir="$repo/.bare" worktree add -b "$branch" "$target" "$start" 2>/dev/null \
      || git --git-dir="$repo/.bare" worktree add "$target" "$branch"
  else
    git --git-dir="$repo/.bare" worktree add -b "$branch" "$target" 2>/dev/null \
      || git --git-dir="$repo/.bare" worktree add "$target" "$branch"
  fi
}

switch_or_attach() { # $1 = session name   $2 = worktree dir (abs, for create)
  local session="$1" dir="$2"
  if ! has_tmux_session "$session"; then
    tmux new-session -d -s "$session" -c "$dir" -n "neovim"
    tmux send-keys -t "$session:neovim" "nvim ." C-m
    tmux new-window -t "$session" -c "$dir" -n "lazygit"
    tmux send-keys -t "$session:lazygit" "lazygit" C-m
    tmux new-window -t "$session" -c "$dir" -n "run"
    tmux new-window -t "$session" -c "$dir" -n "lazysql"
    tmux send-keys -t "$session:lazysql" "lazysql" C-m
    tmux new-window -t "$session" -c "$dir" -n "opencode"
    tmux send-keys -t "$session:opencode" "opencode" C-m
    tmux select-window -t "$session:neovim"
  fi
  tmux switch-client -t "$session" 2>/dev/null || tmux attach-session -t "$session"
}

# ── build the picker list ───────────────────────────────────────────────────

LIST_TMP="$(mktemp)"
trap 'rm -f "$LIST_TMP"' EXIT

while read -r repo; do
  [[ -n "$repo" ]] || continue
  reponame="$(basename "$repo")"

  # worktrees on disk (with live-session marker where applicable)
  while read -r wt; do
    [[ -n "$wt" ]] || continue
    branch="$(basename "$wt")"
    sess="$(sanitize "$branch")"
    status=""
    if has_tmux_session "$sess"; then
      status="  (live session)"
    fi
    printf 'switch\t%s\t%s\t[%s] %s%s\n' "$reponame" "$wt" "$reponame" "$branch" "$status"
  done < <(git --git-dir="$repo/.bare" worktree list --porcelain 2>/dev/null | grep '^worktree ' | cut -d' ' -f2- | grep -v "$repo/.bare")

  # branches with no worktree yet (checkout candidates)
  while read -r branch; do
    [[ -n "$branch" ]] || continue
    sanitized="$(sanitize "$branch")"
    [[ -d "$repo/$sanitized" ]] && continue
    printf 'checkout\t%s\t%s\t[%s] %s  (new worktree)\n' "$reponame" "$branch" "$reponame" "$branch"
  done < <(git --git-dir="$repo/.bare" for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | sed 's#^origin/##')

  # synthetic "+ New branch" row
  printf 'newbranch\t%s\t\t[%s] + New branch\n' "$reponame" "$reponame"
done < <(each_repo)

# pinned "+ Clone" row (always last)
printf 'clone\t\t\t+ Clone new repository\n'

# ── fzf ─────────────────────────────────────────────────────────────────────

CHOICE="$(cat "$LIST_TMP" | fzf \
  --with-nth 4 \
  --delimiter '\t' \
  --prompt 'worktree> ' \
  --header 'Enter: go · s: switch · c: checkout/clone' \
  --bind 'enter:accept,s:accept,c:accept' \
  --preview 'echo {3}')" || true

[[ -n "$CHOICE" ]] || exit 0

TYPE="$(printf '%s' "$CHOICE" | cut -f1)"
REPO="$(printf '%s' "$CHOICE" | cut -f2)"
REF="$(printf '%s' "$CHOICE" | cut -f3)"

# ── dispatch ────────────────────────────────────────────────────────────────

case "$TYPE" in
  switch)
    if [[ -d "$REF" ]]; then
      switch_or_attach "$(sanitize "$(basename "$REF")")" "$REF"
    else
      echo "Worktree no longer exists: $REF" >&2
    fi
    ;;

  checkout)
    add_worktree "$WORKTREE_ROOT/$REPO" "$REF" "$WORKTREE_ROOT/$REPO/$(sanitize "$REF")" "origin/$REF"
    switch_or_attach "$(sanitize "$REF")" "$WORKTREE_ROOT/$REPO/$(sanitize "$REF")"
    ;;

  newbranch)
    echo -n "New branch name (in $REPO): " >&2
    read -r name
    [[ -n "$name" ]] || exit 0
    add_worktree "$WORKTREE_ROOT/$REPO" "$name" "$WORKTREE_ROOT/$REPO/$(sanitize "$name")" "origin/HEAD"
    switch_or_attach "$(sanitize "$name")" "$WORKTREE_ROOT/$REPO/$(sanitize "$name")"
    ;;

  clone)
    clone_url=""
    if command -v gh >/dev/null 2>&1; then
      repo_row="$(gh api 'user/repos?affiliation=owner,collaborator,organization_member&per_page=100' --paginate \
        --jq '.[] .full_name' | fzf --prompt 'repo> ' --header 'Choose a repo (Esc to paste URL manually)' || true)"
      if [[ -n "$repo_row" ]]; then
        clone_url="https://github.com/$repo_row.git"
      fi
    fi
    if [[ -z "$clone_url" ]]; then
      echo -n "Git clone URL: " >&2
      read -r clone_url
    fi
    [[ -n "$clone_url" ]] || exit 0

    reponame="$(basename "$clone_url" .git)"
    setup_bare "$WORKTREE_ROOT/$reponame" "$clone_url" || { echo "Clone failed." >&2; exit 1; }

    default_branch="$(git --git-dir="$WORKTREE_ROOT/$reponame/.bare" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's#^origin/##' || echo main)"
    add_worktree "$WORKTREE_ROOT/$reponame" "$default_branch" "$WORKTREE_ROOT/$reponame/$(sanitize "$default_branch")" "origin/$default_branch"
    switch_or_attach "$(sanitize "$default_branch")" "$WORKTREE_ROOT/$reponame/$(sanitize "$default_branch")"
    ;;
esac