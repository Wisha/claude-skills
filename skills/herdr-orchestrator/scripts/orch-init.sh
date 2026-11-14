#!/usr/bin/env bash
set -euo pipefail

slug="${1:?usage: orch-init.sh <slug>}"
repo="$(git rev-parse --show-toplevel)"
run_id="$(date +%Y%m%d-%H%M)-${slug}"
orch_dir="$repo/.orch/$run_id"

mkdir -p "$orch_dir/briefs" "$orch_dir/results"

# Keep run artefacts out of git without editing the tracked .gitignore.
exclude="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
grep -qxF '.orch/' "$exclude" 2>/dev/null || printf '.orch/\n' >> "$exclude"
printf '%s\n' "$run_id" > "$orch_dir/run-id"
git -C "$repo" rev-parse HEAD > "$orch_dir/base-ref"
cat > "$orch_dir/ledger.md" <<EOF
# Ledger: $run_id

| name | pane | model (reasoning/clarity) | worktree | status | result | open issues |
|------|------|---------------------------|----------|--------|--------|-------------|
EOF

printf '%s\n' "$orch_dir"
