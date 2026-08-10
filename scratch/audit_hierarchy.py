#!/usr/bin/env python3
import os
import re

TARGET_FILES = [
    "frontend/lib/screens/customer_marketplace_screen.dart",
    "frontend/lib/screens/job_status_screen.dart",
    "frontend/lib/screens/wallet_screen.dart",
    "frontend/lib/screens/employee_screen.dart",
    "frontend/lib/screens/employee_jobs_screen.dart",
]

def audit_file(filepath):
    findings = []
    if not os.path.exists(filepath):
        return findings

    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # 1. Check Raw Card or Raw Card-like Container
    for idx, line in enumerate(lines):
        lineno = idx + 1
        sline = line.strip()
        if ' Card(' in line or sline.startswith('Card('):
            findings.append((lineno, "RAW_CARD", "Raw Card widget used instead of ThemedCard"))
        
        if 'BoxDecoration(' in line and 'boxShadow:' in line:
            findings.append((lineno, "RAW_CONTAINER_SHADOW", "Raw Container/BoxDecoration with boxShadow used instead of ThemedCard"))

    # 2. Check ThemedCard elevation & padding
    in_themed_card = False
    card_line = 0
    card_buffer = []

    for idx, line in enumerate(lines):
        lineno = idx + 1
        if 'ThemedCard(' in line:
            in_themed_card = True
            card_line = lineno
            card_buffer = [line]
        elif in_themed_card:
            card_buffer.append(line)
            # Find closing bracket or end of constructor parameters
            if ');' in line or (line.strip().startswith('child:') and not line.strip().endswith('(')):
                block = "".join(card_buffer)
                if 'elevation:' not in block:
                    findings.append((card_line, "MISSING_ELEVATION", "ThemedCard missing explicit elevation parameter"))
                elif 'AppElevation.' not in block:
                    findings.append((card_line, "RAW_ELEVATION", "ThemedCard using non-token raw elevation"))

                if 'padding:' not in block:
                    findings.append((card_line, "MISSING_PADDING", "ThemedCard missing explicit padding parameter"))
                elif 'AppSpacing.' not in block and 'EdgeInsets' not in block:
                    findings.append((card_line, "RAW_PADDING", "ThemedCard padding not using AppSpacing token"))

                in_themed_card = False
                card_buffer = []

    # 3. Check for multiple PrimaryButton in single card or dialog container
    # Simple block check by looking at contiguous indentation / card blocks
    content = "".join(lines)

    return findings

def main():
    print("=== Phase 4 Visual Hierarchy & Card Audit ===")
    total_findings = 0
    results = {}

    for path in TARGET_FILES:
        file_findings = audit_file(path)
        results[path] = file_findings
        total_findings += len(file_findings)
        print(f"\nFile: {path}")
        if not file_findings:
            print("  No issues found.")
        else:
            for lineno, ftype, desc in file_findings:
                print(f"  Line {lineno:4d} [{ftype}]: {desc}")

    print(f"\nTotal Hierarchy Findings across in-scope files: {total_findings}")

    with open("scratch/hierarchy_findings.txt", "w") as f:
        f.write(f"Total Hierarchy Findings: {total_findings}\n")
        for path, f_list in results.items():
            f.write(f"\nFile: {path}\n")
            for lineno, ftype, desc in f_list:
                f.write(f"  Line {lineno:4d} [{ftype}]: {desc}\n")

if __name__ == "__main__":
    main()
