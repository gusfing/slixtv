import 'package:flutter_test/flutter_test.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/config_parser.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/config_pretty_printer.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';

void main() {
  group('ConfigParser', () {
    test('should parse valid responses', () {
      final config = ConfigParser.parseConfigs(
        mainInfoResponse: {'server_name': 'My Server', 'portal_name': 'My Portal', 'support_url': 'http://support.com'},
        modulesResponse: ['mod1', 'mod2'],
        profileResponse: {'stb_type': 'MAG322', 'timezone': 'America/New_York', 'locale': 'es_ES'},
      );

      expect(config.serverName, 'My Server');
      expect(config.portalName, 'My Portal');
      expect(config.supportUrl, 'http://support.com');
      expect(config.modules.length, 2);
      expect(config.modules[0], 'mod1');
      expect(config.stbType, 'MAG322');
      expect(config.timezone, 'America/New_York');
      expect(config.locale, 'es_ES');
    });

    test('should handle missing data with defaults', () {
      final config = ConfigParser.parseConfigs(
        mainInfoResponse: null,
        modulesResponse: null,
        profileResponse: null,
      );

      expect(config.serverName, 'Unknown Server');
      expect(config.stbType, 'MAG250');
      expect(config.modules.isEmpty, isTrue);
    });
  });

  group('ConfigPrettyPrinter', () {
    test('should format DeviceIdentity', () {
      final identity = DeviceIdentity.generate();
      final str = ConfigPrettyPrinter.formatDeviceIdentity(identity);
      
      expect(str, contains('DEVICE IDENTITY'));
      expect(str, contains(identity.mac));
      expect(str, contains(identity.serialNumber));
    });

    test('should format SessionManager and mask token', () {
      final session = SessionManager();
      session.setBearerToken('12345678901234567890');
      session.setPortalInfo('http://test.com', '/load.php');
      
      final str = ConfigPrettyPrinter.formatSessionManager(session);
      
      expect(str, contains('SESSION STATE'));
      expect(str, contains('1234567890123456... (masked)'));
      expect(str, contains('http://test.com'));
    });

    test('should truncate long URL', () {
      final longUrl = 'http://test.com/' + 'a' * 100;
      final truncated = ConfigPrettyPrinter.truncateUrl(longUrl, maxLength: 50);
      
      expect(truncated.length, 50);
      expect(truncated, endsWith('...'));
    });

    test('should format JSON', () {
      final formatted = ConfigPrettyPrinter.formatJson({'a': 1, 'b': 2});
      expect(formatted, contains('{\n  "a": 1,\n  "b": 2\n}'));
    });
  });
}
