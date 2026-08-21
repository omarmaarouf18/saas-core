#!/usr/bin/env bash
set -euo pipefail

# Determine script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENS_DIR="$REPO_ROOT/frontend/lib/screens"
THEME_FILE="$REPO_ROOT/frontend/lib/core/theme.dart"

if [ ! -d "$SCREENS_DIR" ]; then
  echo "Error: Screens directory not found at $SCREENS_DIR" >&2
  exit 1
fi

if [ ! -f "$THEME_FILE" ]; then
  echo "Error: Theme file not found at $THEME_FILE" >&2
  exit 1
fi

# Counts 1 & 2 match widget CONSTRUCTION (not identifier substrings such as
# `_buildOwnerScaffold(`), using a PCRE negative lookbehind on identifier chars.
# Count 1: Number of files constructing Scaffold(
scaffold_files=$({ grep -lP '(?<![A-Za-z0-9_])Scaffold\(' "$SCREENS_DIR"/*.dart 2>/dev/null || true; } | wc -l | tr -d ' ')

# Count 2: Number of files constructing AppBar(
appbar_files=$({ grep -lP '(?<![A-Za-z0-9_])AppBar\(' "$SCREENS_DIR"/*.dart 2>/dev/null || true; } | wc -l | tr -d ' ')

# Count 3: Total occurrences of BoxDecoration(
box_decorations=$({ grep -oP '(?<![A-Za-z0-9_])BoxDecoration\(' "$SCREENS_DIR"/*.dart 2>/dev/null || true; } | wc -l | tr -d ' ')

# Count 4: Total occurrences of .toUpperCase()
toupper_occurrences=$({ grep -oF ".toUpperCase()" "$SCREENS_DIR"/*.dart 2>/dev/null || true; } | wc -l | tr -d ' ')

# Count 5: Number of files containing Color(0xFF outside core/theme.dart
# Across frontend/lib/screens/*.dart (all screen files are outside core/theme.dart)
color_files=$({ grep -lF "Color(0xFF" "$SCREENS_DIR"/*.dart 2>/dev/null || true; } | wc -l | tr -d ' ')

# Count 6: Total occurrences of Color(0xFF inside frontend/lib/core/theme.dart
theme_color_occurrences=$({ grep -oF "Color(0xFF" "$THEME_FILE" 2>/dev/null || true; } | wc -l | tr -d ' ')

echo "=== Frontend Composition Layer Audit ==="
echo "Target directory: frontend/lib/screens/*.dart"
echo "1. Files containing 'Scaffold(': $scaffold_files"
echo "2. Files containing 'AppBar(': $appbar_files"
echo "3. Total occurrences of 'BoxDecoration(': $box_decorations"
echo "4. Total occurrences of '.toUpperCase()': $toupper_occurrences"
echo "5. Files containing 'Color(0xFF' outside core/theme.dart: $color_files"
echo "6. Total occurrences of 'Color(0xFF' inside frontend/lib/core/theme.dart: $theme_color_occurrences"
