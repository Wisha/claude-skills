#!/usr/bin/env bash
set -euo pipefail

# --class <reasoning>/<clarity> is the task's classification (SKILL.md, Model choice).
# Args after "--" go to the agent, e.g. -- --model sonnet --effort medium.
usage='usage: orch-spawn.sh <orch-dir> <name> [kind] [base-ref] --class <reasoning>/<clarity> -- --model <alias> [--effort <level>]'
pos=() agent_args=() class=""
while (( $# )); do
  case "$1" in
    --) shift; agent_args=("$@"); break ;;
    --class) class="${2:?--class needs <reasoning>/<clarity>}"; shift 2 ;;
    *) pos+=("$1"); shift ;;
  esac
done
set -- ${pos[@]+"${pos[@]}"}

orch_dir="${1:?$usage}"
name="${2:?missing worker name}"
kind="${3:-claude}"
base="${4:-$(cat "$orch_dir/base-ref")}"

[[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "invalid name: $name" >&2; exit 2; }

# A Claude worker never inherits the session's model: the orchestrator classifies the task and names the model.
model=""
for (( i = 0; i < ${#agent_args[@]}; i++ )); do
  case "${agent_args[i]}" in
    --model) model="${agent_args[i+1]:-}" ;;
    --model=*) model="${agent_args[i]#--model=}" ;;
  esac
done
if [[ "$kind" == claude ]]; then
  [[ "$class" =~ ^(advanced|ordinary|none)/(limited|decent|clear|full)$ ]] || {
    echo "missing or invalid --class (got '${class}'): <advanced|ordinary|none>/<limited|decent|clear|full>" >&2
    echo "$usage" >&2; exit 2; }
  [[ -n "$model" ]] || { echo "missing --model after '--': pick it from SKILL.md, Model choice" >&2; echo "$usage" >&2; exit 2; }
fi

repo="$(git rev-parse --show-toplevel)"
run_id="$(cat "$orch_dir/run-id")"
wt_root="$(dirname "$repo")/$(basename "$repo").worktrees"
wt="$wt_root/$run_id/$name"
branch="orch/$run_id/$name"

mkdir -p "$(dirname "$wt")"
git -C "$repo" worktree add -q "$wt" -b "$branch" "$base"

# Carry the repo's Claude settings into the worktree when they are untracked.
if [[ -d "$repo/.claude" && ! -e "$wt/.claude/settings.json" ]]; then
  mkdir -p "$wt/.claude"
  cp "$repo/.claude/settings.json" "$wt/.claude/settings.json" 2>/dev/null || true
fi

# Four panes per tab keeps them readable. State: "<anchor-pane> <panes-in-tab>".
# The orchestrator's own tab starts with one pane (itself).
state_file="$orch_dir/.tab-state"
[[ -f "$state_file" ]] || printf '%s 1\n' "${HERDR_PANE_ID:?run inside a Herdr pane}" > "$state_file"
read -r anchor count < "$state_file"

if (( count >= 4 )); then
  pane="$(herdr tab create --workspace "${HERDR_WORKSPACE_ID:?}" --cwd "$wt" --label "$run_id" --no-focus | jq -r '.result.root_pane.pane_id')"
  printf '%s 1\n' "$pane" > "$state_file"
else
  direction=right
  (( count % 2 == 0 )) && direction=down
  pane="$(herdr pane split "$anchor" --direction "$direction" --cwd "$wt" --no-focus | jq -r '.result.pane.pane_id')"
  printf '%s %d\n' "$anchor" $((count + 1)) > "$state_file"
fi

# A pane just split can report busy for a few seconds before its shell is ready: retry only on that.
for attempt in 1 2 3 4 5 6; do
  if out="$(herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 \
      ${agent_args[@]+-- "${agent_args[@]}"} 2>&1)"; then
    break
  fi
  if [[ "$out" == *agent_pane_busy* && $attempt -lt 6 ]]; then sleep 3; continue; fi
  echo "$out" >&2
  echo "agent did not start in pane $pane (worktree $wt, branch $branch); start it by hand or close the pane" >&2
  exit 1
done

args="${agent_args[*]:-default}"
printf '| %s | %s | %s (%s) | %s | BRIEFED | results/%s.md | |\n' "$name" "$pane" "$args" "${class:-unclassified}" "$wt" "$name" >> "$orch_dir/ledger.md"
jq -n --arg name "$name" --arg pane "$pane" --arg model "${model:-default}" --arg args "$args" --arg class "$class" --arg worktree "$wt" --arg branch "$branch" \
  '{name:$name, pane:$pane, model:$model, args:$args, class:$class, worktree:$worktree, branch:$branch}'
