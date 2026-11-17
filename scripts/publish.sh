#!/usr/bin/env bash
# One-time: create a git repo and publish it to GitHub (needs `gh auth login`).
#   scripts/publish.sh            public repo
#   scripts/publish.sh --private  private repo
set -euo pipefail
cd "$(dirname "$0")/.."
VIS="${1:---public}"

[[ -d .git ]] || git init -b main
git add -A
git diff --cached --quiet || git commit -m "Initial commit: WhitePointBar menu bar app"
gh repo create WhitePointBar "$VIS" --source=. --push \
  --description "macOS menu bar app: white point + grayscale filter with intensity slider"
gh repo edit --add-topic macos,menu-bar,swiftui,grayscale,color-temperature,accessibility
gh repo view --web
