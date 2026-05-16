class MagConfig {
  final String serverName;
  final String portalName;
  final String supportUrl;
  final List<String> modules;
  final String stbType;
  final String timezone;
  final String locale;

  MagConfig({
    required this.serverName,
    required this.portalName,
    required this.supportUrl,
    required this.modules,
    required this.stbType,
    required this.timezone,
    required this.locale,
  });
}

class ConfigParser {
  static MagConfig parseConfigs({
    required dynamic mainInfoResponse,
    required dynamic modulesResponse,
    required dynamic profileResponse,
  }) {
    String serverName = 'Unknown Server';
    String portalName = 'Unknown Portal';
    String supportUrl = '';
    
    if (mainInfoResponse is Map) {
      serverName = mainInfoResponse['server_name']?.toString() ?? serverName;
      portalName = mainInfoResponse['portal_name']?.toString() ?? portalName;
      supportUrl = mainInfoResponse['support_url']?.toString() ?? supportUrl;
    }

    List<String> modules = [];
    if (modulesResponse is List) {
      modules = modulesResponse.map((e) => e.toString()).toList();
    } else if (modulesResponse is Map && modulesResponse.containsKey('modules')) {
      if (modulesResponse['modules'] is List) {
        modules = (modulesResponse['modules'] as List).map((e) => e.toString()).toList();
      }
    }

    String stbType = 'MAG250';
    String timezone = 'Europe/Kyiv';
    String locale = 'en_US';

    if (profileResponse is Map) {
      stbType = profileResponse['stb_type']?.toString() ?? stbType;
      timezone = profileResponse['timezone']?.toString() ?? timezone;
      locale = profileResponse['locale']?.toString() ?? locale;
    }

    return MagConfig(
      serverName: serverName,
      portalName: portalName,
      supportUrl: supportUrl,
      modules: modules,
      stbType: stbType,
      timezone: timezone,
      locale: locale,
    );
  }
}
