#!/usr/bin/env bash
set -euo pipefail

icon="${1:-SmokeArrow/SmokeArrow/Assets.xcassets/AppIcon.appiconset/NewSmokeArrow.png}"

if [[ ! -f "$icon" ]]; then
  echo "not found: $icon" >&2
  exit 2
fi

alpha="$(sips -g hasAlpha "$icon" 2>/dev/null | tail -n 1 | awk '{print $2}')"
echo "$icon hasAlpha: ${alpha:-unknown}"

if [[ "${alpha:-}" == "yes" ]]; then
  echo "Fix: swift scripts/strip_png_alpha.swift \"$icon\"" >&2
  exit 1
fi

