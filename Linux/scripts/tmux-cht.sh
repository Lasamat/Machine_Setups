#!/usr/bin/env bash

languages=("bash" "lua" "c#" "javascript" "typescript" "elixir" "tmux" "html" "css")
commands=("find" "man" "tldr" "sed" "awk" "ls" "grep" "jq" "git" "git-worktree" "dotnet")

options=("${languages[@]}" "${commands[@]}")

selected=$(printf "%s\n" "${options[@]}" | fzf)
if [[ -z $selected ]]; then
  exit 0
fi
echo "selected: $selected"
read -p "Enter Query: " query
echo "query: $query"

is_language=false
for lang in "${languages[@]}"; do
  if [[ "$lang" == "$selected" ]]; then
    is_language=true
    break
  fi
done

if $is_language; then
  query=$(echo "$query" | tr ' ' '+')
  tmux neww bash -c "echo \"curl cht.sh/$selected/$query/\" & curl cht.sh/$selected/$query & while [ : ]; do sleep 1; done"
else
  tmux neww bash -c "curl -s cht.sh/$selected~$query | less"
fi
