#!/usr/bin/env bash
# Inspect the private color-filter API surface on this Mac.
#   scripts/probe.sh          list relevant exported symbols + current prefs
#   scripts/probe.sh --diff   snapshot prefs, let you move the Intensity slider
#                             in System Settings, then show which key changed
set -uo pipefail
DOMAIN=com.apple.mediaaccessibility

for fw in \
  /System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility \
  /System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess; do
  echo "== $(basename "$fw") exports"
  if command -v dyld_info >/dev/null; then
    dyld_info -exports "$fw" 2>/dev/null | grep -Ei 'DisplayFilter|WhitePoint|Grayscale|Intensity|UniversalAccessDStart' \
      || echo "  (no matches)"
  else
    echo "  dyld_info not found (install Xcode Command Line Tools)"
  fi
done

echo
echo "== $DOMAIN (filter-related keys)"
defaults read "$DOMAIN" 2>/dev/null | grep -Ei 'filter|intens|white|gray' || echo "  (none)"

if [[ "${1:-}" == "--diff" ]]; then
  before=$(mktemp); after=$(mktemp)
  defaults export "$DOMAIN" - > "$before"
  echo
  read -r -p "Change Color Filters intensity in System Settings, then press Return… "
  defaults export "$DOMAIN" - > "$after"
  diff "$before" "$after" || true
  rm -f "$before" "$after"
  echo
  echo "If a key changed, pin it with:"
  echo "  defaults write local.mike.WhitePointBar GrayscaleIntensityKey '<key>'"
fi
