import os
import re

SCREENS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/screens"

def detailed_audit_states():
    files = sorted([os.path.join(SCREENS_DIR, f) for f in os.listdir(SCREENS_DIR) if f.endswith('.dart')])
    
    empty_state_findings = []
    error_banner_findings = []
    snackbar_findings = []

    for filepath in files:
        filename = os.path.basename(filepath)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            lines = content.splitlines()

        # Audit 1: Search for empty states missing action buttons
        # Match ThemedEmptyState calls
        for idx, line in enumerate(lines, 1):
            if 'ThemedEmptyState(' in line:
                # Check next 15 lines for actionText / onActionPressed
                block = "\n".join(lines[idx-1:idx+15])
                has_action = ('actionText:' in block and 'onActionPressed:' in block)
                if not has_action:
                    empty_state_findings.append({
                        'file': filename,
                        'line': idx,
                        'issue': 'ThemedEmptyState missing primary action button',
                        'snippet': line.strip()
                    })

            # Audit 2: Search for ad-hoc empty states (e.g. Center(child: Text(...)))
            if 'Center(' in line and ('noJobs' in line or 'noData' in line or 'noOrders' in line or 'noNotifications' in line or 'noEmployees' in line):
                if 'ThemedEmptyState' not in line:
                    empty_state_findings.append({
                        'file': filename,
                        'line': idx,
                        'issue': 'Ad-hoc text empty state (should be ThemedEmptyState)',
                        'snippet': line.strip()
                    })

            # Audit 3: Search for ThemedErrorBanner missing onRetry
            if 'ThemedErrorBanner(' in line:
                block = "\n".join(lines[idx-1:idx+12])
                has_retry = ('onRetry:' in block)
                if not has_retry:
                    error_banner_findings.append({
                        'file': filename,
                        'line': idx,
                        'issue': 'ThemedErrorBanner missing inline retry callback',
                        'snippet': line.strip()
                    })

            # Audit 4: Search for raw error banners or ad-hoc error widgets
            if ('Text(error' in line or 'Text(snapshot.error' in line or 'Text(l10n.error' in line) and 'ThemedErrorBanner' not in line:
                error_banner_findings.append({
                    'file': filename,
                    'line': idx,
                    'issue': 'Ad-hoc error text (should be ThemedErrorBanner)',
                    'snippet': line.strip()
                })

            # Audit 5: Search for raw ScaffoldMessenger.showSnackBar calls
            if 'showSnackBar(' in line and 'ThemedSuccess' not in line and 'ThemedError' not in line:
                snackbar_findings.append({
                    'file': filename,
                    'line': idx,
                    'issue': 'Raw SnackBar call (should use ThemedSuccessSnackBar / ThemedErrorSnackBar)',
                    'snippet': line.strip()
                })

    print("=== STATE AUDIT SUMMARY ===")
    print(f"Empty State Findings: {len(empty_state_findings)}")
    for ef in empty_state_findings:
        print(f"  [Empty] {ef['file']}:{ef['line']} -> {ef['issue']}")

    print(f"\nError Banner Findings: {len(error_banner_findings)}")
    for err in error_banner_findings:
        print(f"  [Error] {err['file']}:{err['line']} -> {err['issue']}")

    print(f"\nSnackBar Feedback Findings: {len(snackbar_findings)}")
    for sb in snackbar_findings:
        print(f"  [SnackBar] {sb['file']}:{sb['line']} -> {sb['issue']}")

    return empty_state_findings, error_banner_findings, snackbar_findings

if __name__ == '__main__':
    ef, err, sb = detailed_audit_states()
    with open('/mnt/windows_data/CS tools/Antigravity/SaaS prototype/scratch/states_findings.txt', 'w', encoding='utf-8') as out:
        out.write("=== EMPTY STATE FINDINGS ===\n")
        for item in ef:
            out.write(f"{item['file']}:{item['line']} -> {item['issue']} | {item['snippet']}\n")
        out.write("\n=== ERROR BANNER FINDINGS ===\n")
        for item in err:
            out.write(f"{item['file']}:{item['line']} -> {item['issue']} | {item['snippet']}\n")
        out.write("\n=== SNACKBAR FINDINGS ===\n")
        for item in sb:
            out.write(f"{item['file']}:{item['line']} -> {item['issue']} | {item['snippet']}\n")
