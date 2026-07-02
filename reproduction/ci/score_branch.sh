#!/bin/bash
# Score a branch's CI-committed results/methods/*.csv against published (numpy-only).
# Usage: bash score_branch.sh <branch>
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
b="$1"; [ -z "$b" ] && { echo "usage: score_branch.sh <branch>"; exit 1; }
cd "$ROOT"; git fetch -q origin "$b"
tmp=$(mktemp -d); git --work-tree="$tmp" checkout "origin/$b" -- results/methods 2>/dev/null \
  || { echo "no results/methods on origin/$b (CI not finished?)"; exit 1; }
echo "=== $b (maxD/bias/spread) ==="
for m in scc dcc gam cps paico; do
  f="$tmp/results/methods/${m}_global.csv"
  [ -f "$f" ] && python3 "$HERE/cmp.py" --method "$m" --csv "$f" 2>/dev/null \
    | grep -E "maxD|bias|spread" | tr '\n' ' ' && echo " <- $m"
done
rm -rf "$tmp"
