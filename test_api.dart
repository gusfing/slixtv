import 'package:slix_iptv/features/auth/data/stalker_api_service.dart';
import 'dart:convert';
import 'dart:io';

void main() async {
  final service = StalkerApiService();
  try {
    await service.handshake('http://tv.stream4k.cc', '00:1E:99:2C:D2:08');
    final profile = await service.getProfile();
    
    final output = {
      'id': profile.id,
      'name': profile.name,
      'status': profile.status,
      'raw': profile.raw,
    };
    
    File('profile_output.json').writeAsStringSync(jsonEncode(output));
    print('Done');
  } catch (e) {
    print('Error: $e');
  }
}
