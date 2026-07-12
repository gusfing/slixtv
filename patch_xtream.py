import re

file_path = r'C:\Users\ks209\Documents\kawaki clients\iptv sflixtv\iptv last testing phase (2)\iptv last testing phase\lib\features\auth\data\xtream_api_service.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

def encode_url(match):
    return f"String _processUrl(String url) {{ if (url.isEmpty) return ''; url = url.trim().replaceAll('\\\\', '/'); try {{ return Uri.encodeFull(url); }} catch(e) {{ return url; }} }}\n{match.group(0)}"

if 'String _processUrl' not in content:
    content = re.sub(r'class XtreamApiService implements ApiClient \{', encode_url, content)
    
    # Replace cover and streamIcon
    content = content.replace("poster: streamIcon,", "poster: _processUrl(streamIcon),")
    content = content.replace("poster: cover,", "poster: _processUrl(cover),")
    content = content.replace("poster: infoJson?['movie_image']?.toString() ?? '',", "poster: _processUrl(infoJson?['movie_image']?.toString() ?? ''),")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Patched xtream_api_service.dart')
else:
    print('Already patched xtream')
