import re

files_to_patch = [
    'lib/features/live_tv/presentation/live_tv_screen.dart',
    'lib/features/player/presentation/player_screen.dart'
]

for file_path in files_to_patch:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add import
    if 'wakelock_plus.dart' not in content:
        content = re.sub(r"(import 'package:flutter/material\.dart';)", r"\1\nimport 'package:wakelock_plus/wakelock_plus.dart';", content, count=1)

    # Enable wakelock in initState
    if 'WakelockPlus.enable()' not in content:
        content = re.sub(r'(super\.initState\(\);)', r'\1\n    WakelockPlus.enable();', content, count=1)

    # Disable wakelock in dispose
    if 'WakelockPlus.disable()' not in content:
        content = re.sub(r'(super\.dispose\(\);)', r'WakelockPlus.disable();\n    \1', content, count=1)

    # Set volume
    if 'setVolume(' not in content:
        content = re.sub(r'(_player = Player\(\);)', r'\1\n    _player?.setVolume(100.0);', content)

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print('Patched ' + file_path)
