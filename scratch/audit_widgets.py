import os
import re

WIDGETS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/widgets"
SCREENS_DIR = "/mnt/windows_data/CS tools/Antigravity/SaaS prototype/frontend/lib/screens"

widget_files = sorted([f for f in os.listdir(WIDGETS_DIR) if f.endswith('.dart')])
screen_files = [os.path.join(SCREENS_DIR, f) for f in os.listdir(SCREENS_DIR) if f.endswith('.dart')]

widget_data = {}

for wf in widget_files:
    wpath = os.path.join(WIDGETS_DIR, wf)
    with open(wpath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract class name(s)
    classes = re.findall(r'class\s+([A-Za-z0-9_]+)\s+extends', content)
    
    # Count occurrences across screens
    usages = []
    for sf in sorted(screen_files):
        sname = os.path.basename(sf)
        with open(sf, 'r', encoding='utf-8') as f:
            scontent = f.read()
        for c in classes:
            if c in scontent and not c.startswith('_'):
                usages.append(sname)
                break
                
    widget_data[wf] = {
        'classes': classes,
        'usages': usages,
        'usage_count': len(usages)
    }

for wf, data in widget_data.items():
    print(f"Widget: {wf}")
    print(f"  Classes: {', '.join(data['classes'])}")
    print(f"  Used in ({data['usage_count']} screens): {', '.join(data['usages']) if data['usages'] else 'None (Directly instantiated or modal component)'}")
