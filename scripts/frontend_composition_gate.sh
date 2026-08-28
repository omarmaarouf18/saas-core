#!/usr/bin/env bash
set -euo pipefail

# Frontend Composition Layer Gate
# Rejects raw composition-layer violations inside frontend/lib/screens/**.
# Screens must compose UI exclusively through the shared widgets layer
# (frontend/lib/widgets/**) and design tokens (frontend/lib/core/theme.dart).
#
# Blocked patterns in screens/:
#   - Scaffold(            -> use AppShell / screen templates (widgets/)
#   - AppBar(              -> use AppShell (widgets/)
#   - BoxDecoration(       -> use ThemedCard / ThemedPanel (widgets/)
#   - Color(0xFF literals  -> use AppColors tokens (core/theme.dart)
#   - .toUpperCase() calls -> use AppTypography.uppercaseLabel (core/theme.dart)
#   - appBarBackgroundColor:/appBarForegroundColor: overrides -> AppShell
#     defaults keep chrome consistent (V1 pass regression guard: AppBar
#     styling drifted twice via per-screen overrides). Sole exception:
#     `Colors.transparent` backgrounds on the full-bleed auth screens.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENS_DIR="$REPO_ROOT/frontend/lib/screens"

if [ ! -d "$SCREENS_DIR" ]; then
  echo "GATE SKIP: screens directory not found at $SCREENS_DIR"
  exit 0
fi

VIOLATIONS=0

check_pattern() {
  local label="$1"
  local regex="$2"
  local matches
  matches=$(grep -rnP "$regex" "$SCREENS_DIR" --include='*.dart' 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "BLOCKED: $label found in frontend/lib/screens/:"
    echo "$matches"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
}

check_pattern "'Scaffold(' construction" '(?<![A-Za-z0-9_])Scaffold\('
check_pattern "'AppBar(' construction" '(?<![A-Za-z0-9_])AppBar\('
check_pattern "'BoxDecoration(' construction" '(?<![A-Za-z0-9_])BoxDecoration\('
check_pattern "'.toUpperCase()' call" '\.toUpperCase\(\)'
check_pattern "'Color(0xFF' literal" 'Color\(0x(?:FF|ff)'
check_pattern "'appBarBackgroundColor' override (Colors.transparent excepted)" \
  'appBarBackgroundColor:(?!.*Colors\.transparent)'
check_pattern "'appBarForegroundColor' override" 'appBarForegroundColor:'

check_chrome_style_disclosure() {
  local matches
  matches=$(grep -rnP 'chromeStyle:\s*AppShellChromeStyle\.' "$SCREENS_DIR" --include='*.dart' 2>/dev/null || true)
  if [ -n "$matches" ]; then
    local commit_msg
    commit_msg=$(git log -1 --pretty=%B 2>/dev/null || true)
    if ! echo "$commit_msg" | grep -q "SHARED WIDGET CHANGES DISCLOSURE"; then
      echo "BLOCKED: explicit chromeStyle override found in screens/ without SHARED WIDGET CHANGES DISCLOSURE in commit message:"
      echo "$matches"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
}
check_chrome_style_disclosure

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "BLOCKED: $VIOLATIONS composition-layer rule(s) violated in frontend/lib/screens/."
  echo "Route Scaffold/AppBar through AppShell/templates, decorations through ThemedCard/ThemedPanel,"
  echo "colors through AppColors, and uppercase transforms through AppTypography.uppercaseLabel."
  exit 1
fi

echo "== frontend composition gate: all checks passed =="
