import os
import re

SCREENS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/screens"
WIDGETS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/widgets"
CORE_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/core"

def audit_raw_values():
    screen_files = [os.path.join(SCREENS_DIR, f) for f in os.listdir(SCREENS_DIR) if f.endswith('.dart')]
    
    findings = []
    
    # Patterns
    color_pattern = re.compile(r'Color\(0x[0-9a-fA-F]+\)')
    colors_dot_pattern = re.compile(r'Colors\.(blue|red|green|amber|teal|grey|gray|orange|purple|yellow|indigo|cyan|lime|pink|brown|deepOrange|deepPurple|lightBlue|lightGreen)\b')
    edge_insets_pattern = re.compile(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\([^)]+\)')
    sized_box_pattern = re.compile(r'SizedBox\((width|height):\s*([0-9.]+)\)')
    border_radius_pattern = re.compile(r'BorderRadius\.(circular|all|only|fromLTRB)\([^)]+\)')
    text_style_pattern = re.compile(r'TextStyle\([^)]+\)')
    
    for filepath in sorted(screen_files):
        filename = os.path.basename(filepath)
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        for idx, line in enumerate(lines, 1):
            # Check Color(0x...)
            for m in color_pattern.finditer(line):
                findings.append({
                    'file': filename,
                    'line': idx,
                    'category': 'Hardcoded Color',
                    'raw_value': m.group(0),
                    'context': line.strip()
                })
            
            # Check raw Colors.*
            for m in colors_dot_pattern.finditer(line):
                findings.append({
                    'file': filename,
                    'line': idx,
                    'category': 'Raw Material Color',
                    'raw_value': m.group(0),
                    'context': line.strip()
                })
                
            # Check EdgeInsets without AppSpacing
            if 'AppSpacing' not in line:
                for m in edge_insets_pattern.finditer(line):
                    findings.append({
                        'file': filename,
                        'line': idx,
                        'category': 'Hardcoded EdgeInsets',
                        'raw_value': m.group(0),
                        'context': line.strip()
                    })
                    
            # Check SizedBox numeric height/width without AppSpacing
            if 'AppSpacing' not in line:
                for m in sized_box_pattern.finditer(line):
                    val = float(m.group(2))
                    if val > 0 and val not in [1.0, 2.0]: # allow micro dividers
                        findings.append({
                            'file': filename,
                            'line': idx,
                            'category': 'Hardcoded SizedBox Dimension',
                            'raw_value': m.group(0),
                            'context': line.strip()
                        })
            
            # Check BorderRadius without AppRadius
            if 'AppRadius' not in line:
                for m in border_radius_pattern.finditer(line):
                    findings.append({
                        'file': filename,
                        'line': idx,
                        'category': 'Hardcoded BorderRadius',
                        'raw_value': m.group(0),
                        'context': line.strip()
                    })
                    
            # Check TextStyle without AppTypography
            if 'AppTypography' not in line:
                for m in text_style_pattern.finditer(line):
                    findings.append({
                        'file': filename,
                        'line': idx,
                        'category': 'Hardcoded TextStyle',
                        'raw_value': m.group(0),
                        'context': line.strip()
                    })

    print(f"Total design debt findings: {len(findings)}")
    category_counts = {}
    for f in findings:
        cat = f['category']
        category_counts[cat] = category_counts.get(cat, 0) + 1
    
    for cat, count in category_counts.items():
        print(f"  - {cat}: {count}")
        
    return findings

if __name__ == '__main__':
    findings = audit_raw_values()
    with open('/mnt/windows_data/CS tools/Antigravity/SaaS prototype/scratch/design_debt_findings.txt', 'w', encoding='utf-8') as out:
        for item in findings:
            out.write(f"[{item['category']}] {item['file']}:{item['line']} -> {item['raw_value']} | Line: {item['context']}\n")
