#!/usr/bin/env python3
"""A2 audit: find hardcoded human-readable UI string literals in frontend/lib
that bypass the l10n/ARB layer (context.l10n.*).

Re-runnable:  python3 scripts/frontend_l10n_audit.py

Methodology (documented, deterministic):
- Scans frontend/lib/**/*.dart (excluding l10n/ generated infra and core/theme.dart)
  over FULL SOURCE TEXT so multiline widget constructions are covered.
- Flags quoted literals appearing immediately after user-visible call sites:
    Text(  Text.rich(  uppercaseLabel(  _error =   and named properties:
    tooltip/hintText/labelText/helperText/errorText/semanticLabel/title/message/
    subtitle/label/emptyTitle/emptyMessage/actionLabel
- Skips: test-key lines (Key(...), value:/id: args), route paths, asset paths,
  lowercase technical tokens (fontFamily, User-Agent, mime, ws channels),
  snake_case enums, and literals already interpolating l10n.* values.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / "frontend" / "lib"
EXCLUDE_PARTS = ("l10n",)
EXCLUDE_FILES = {"theme.dart"}

# Full-text contexts: (?P<lit>['"]) marks where the literal starts.
CONTEXTS = [
    r"(?<![A-Za-z0-9_])Text\(\s*(?P<lit>['\"])",
    r"(?<![A-Za-z0-9_])Text\.rich\(\s*(?P<lit>['\"])",
    r"(?<![A-Za-z0-9_])uppercaseLabel\(\s*(?P<lit>['\"])",
    r"\b(?:_?error)\s*=\s*(?P<lit>['\"])",
    r"\b(?:tooltip|hintText|labelText|helperText|errorText|semanticLabel|title|message|subtitle|label|emptyTitle|emptyMessage|actionLabel|text)\s*:\s*(?P<lit>['\"])",
    r"(?<![A-Za-z0-9_])(?:return|=>)\s*(?P<lit>['\"])",
]

COMPILED = [(re.compile(c), c) for c in CONTEXTS]

SKIP_PATTERNS = [
    r"^/",                                # route names
    r"^assets/",                          # asset paths
    r"^fonts/",
    r"^[a-z0-9_]+$",                      # snake_case enums/statuses ('cod', 'pending')
    r"^[a-zA-Z0-9_]+_[a-zA-Z0-9_]+$",     # snake_case test keys / ids
    r"^[a-z]+:[<{}a-z_]*$",               # ws channel templates 'job:<id>'
    # compact technical tokens must start lowercase ('fontFamily', 'QuickDeliveryApp/1.0'
    # starts uppercase BUT contains '/' -> caught by next rule):
    r"^[a-z][A-Za-z0-9_.\-/:]*$",
    r"^[A-Z][A-Za-z]*[/][A-Za-z0-9.\-]+$",  # 'QuickDeliveryApp/1.0' style UA strings
    r"^ApiClientException:",              # exception toString representation
    r"^Bearer\s",                         # HTTP Authorization header template
]

# Lines whose trailing context marks the following literal as a test key.
KEY_TAIL = re.compile(r"(?:Key\(|value\s*:|id\s*:)\s*$")


INTERP_RE = re.compile(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")


def is_human_readable(s: str) -> bool:
    """Human copy heuristic applied AFTER stripping Dart interpolation
    ($var / ${expr}) and escape sequences: the REMAINDER must still contain
    a >=2-letter alphabetic run. Pure numeric/id badges (hash-QD, dollar-amount)
    therefore classify as non-translatable formatting."""
    remainder = INTERP_RE.sub("", s)
    remainder = remainder.replace("\\$", "").replace("\\", "")
    return bool(re.search(r"[A-Za-z\u0600-\u06FF]{2}", remainder))


def classify(literal: str, preceding_text: str) -> bool:
    if "l10n." in literal:
        return False  # already routed through localization
    for pat in SKIP_PATTERNS:
        if re.match(pat, literal):
            return False
    tail = preceding_text[-40:]
    if KEY_TAIL.search(tail):
        return False
    return is_human_readable(literal)


def is_accepted_exception(rel_path: str, literal: str) -> bool:
    """Documented accepted exceptions:
    1. Brand names ('Quick Delivery', 'QD')
    2. Tracking badge IDs ('#QD-$displayId')
    3. Component library debug catalog ('component_library_screen.dart')"""
    if "component_library_screen.dart" in rel_path:
        return True
    if literal in ("Quick Delivery", "QD"):
        return True
    if literal.startswith("#QD-"):
        return True
    return False


def audit_source(src: str, rel_path: Path = Path("test.dart")) -> tuple[int, list[tuple[Path, int, str]]]:
    findings = []
    total = 0
    for rx, _ in COMPILED:
        for m in rx.finditer(src):
            quote = m.group("lit")
            rest = src[m.end():]
            end = rest.find(quote)
            if end == -1:
                continue
            literal = rest[:end]
            if "\n" in literal:  # broken extraction guard
                continue
            total += 1
            line = src.count("\n", 0, m.start()) + 1
            if classify(literal, src[max(0, m.start() - 200):m.start()]):
                findings.append((rel_path, line, literal))
    return total, findings


def main() -> int:
    findings = []
    dart_files = sorted(
        p for p in LIB.rglob("*.dart")
        if not any(part in EXCLUDE_PARTS for part in p.parts)
        and p.name not in EXCLUDE_FILES
    )
    total = 0
    for path in dart_files:
        src = path.read_text(encoding="utf-8")
        rel = path.relative_to(REPO)
        file_total, file_findings = audit_source(src, rel)
        total += file_total
        findings.extend(file_findings)

    seen = set()
    uniq = []
    for f, ln, lit in findings:
        k = (str(f), ln, lit)
        if k not in seen:
            seen.add(k)
            uniq.append(k)

    exceptions = []
    violations = []
    for f, ln, lit in sorted(uniq):
        if is_accepted_exception(f, lit):
            exceptions.append((f, ln, lit))
        else:
            violations.append((f, ln, lit))

    print("=== Extended Hardcoded-String l10n Audit ===")
    print(f"Scanned {len(dart_files)} dart files under frontend/lib (excl. l10n/, theme.dart)")
    print(f"String literals at audited call sites: {total}")
    print(f"Flagged as likely-unlocalized human copy: {len(uniq)}")
    print(f"  - Documented accepted exceptions: {len(exceptions)}")
    print(f"  - Non-exempt unlocalized violations: {len(violations)}")
    if violations:
        print("\nVIOLATIONS FOUND:")
        for f, ln, lit in violations:
            print(f"  [VIOLATION] {f}:{ln}: {lit!r}")
    else:
        print("\nZero non-exempt unlocalized violations found.")

    if "--strict" in sys.argv and violations:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
