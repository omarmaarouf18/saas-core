import os
import re

SCREENS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/screens"
WIDGETS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/widgets"
CORE_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/core"

def audit_motion_values():
    target_dirs = [SCREENS_DIR, WIDGETS_DIR, CORE_DIR]
    target_files = []
    for d in target_dirs:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.dart'):
                    target_files.append(os.path.join(d, f))

    findings = []

    # Regular expressions for hardcoded Duration and raw Curves
    duration_pattern = re.compile(r'Duration\((milliseconds|seconds|minutes):\s*\d+\)')
    curves_pattern = re.compile(r'Curves\.[a-zA-Z0-9_]+\b')

    for filepath in sorted(target_files):
        filename = os.path.relpath(filepath, "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib")
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        for idx, line in enumerate(lines, 1):
            # Ignore lines already using AppMotion
            if 'AppMotion' in line:
                continue
            
            # Ignore theme.dart definitions of AppMotion
            if 'theme.dart' in filename:
                continue

            # Check Duration(...) without AppMotion
            for m in duration_pattern.finditer(line):
                findings.append({
                    'file': filename,
                    'line': idx,
                    'category': 'Hardcoded Duration',
                    'raw_value': m.group(0),
                    'context': line.strip()
                })

            # Check Curves.xxx without AppMotion
            for m in curves_pattern.finditer(line):
                findings.append({
                    'file': filename,
                    'line': idx,
                    'category': 'Raw Curves',
                    'raw_value': m.group(0),
                    'context': line.strip()
                })

    print(f"Total motion findings: {len(findings)}")
    category_counts = {}
    for f in findings:
        cat = f['category']
        category_counts[cat] = category_counts.get(cat, 0) + 1

    for cat, count in category_counts.items():
        print(f"  - {cat}: {count}")

    return findings

if __name__ == '__main__':
    findings = audit_motion_values()
    with open('/mnt/windows_data/CS tools/Antigravity/SaaS prototype/scratch/motion_findings.txt', 'w', encoding='utf-8') as out:
        for item in findings:
            out.write(f"[{item['category']}] {item['file']}:{item['line']} -> {item['raw_value']} | Line: {item['context']}\n")
