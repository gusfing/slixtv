import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';

/// A simple fake storage that stores data in-memory for tests.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    AppleOptions? appleOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    AppleOptions? appleOptions,
  }) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    AppleOptions? appleOptions,
  }) async => _storage.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    AppleOptions? appleOptions,
  }) async => _storage.remove(key);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    AppleOptions? appleOptions,
  }) async => _storage.clear();

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    AppleOptions? appleOptions,
  }) async => Map.from(_storage);

  // Required by the interface but not used in tests
  @override
  FlutterSecureStorageOptions get options => const AndroidOptions();
}

void main() {
  late FakeSecureStorage mockStorage;

  setUp(() {
    mockStorage = FakeSecureStorage();
  });

  group('DeviceIdentity', () {
    test('generate should create identity with correct formats', () {
      final identity = DeviceIdentity.generate();

      // MAC format: 00:1A:79:XX:XX:XX
      expect(identity.mac, startsWith('00:1A:79:'));
      expect(RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(identity.mac), isTrue);

      // Serial should be MAC without colons
      expect(identity.serialNumber, identity.mac.replaceAll(':', ''));

      // Device IDs should be 32 chars hex
      expect(identity.deviceId.length, 32);
      expect(identity.deviceId2.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(identity.deviceId), isTrue);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(identity.deviceId2), isTrue);

      expect(identity.stbType, 'MAG250');
      expect(identity.model, 'MAG250');
    });

    test('loadOrCreate should create new identity if storage is empty', () async {
      final identity = await DeviceIdentity.loadOrCreate(mockStorage);

      expect(identity.mac, startsWith('00:1A:79:'));
      // Verify it was persisted
      final stored = await mockStorage.read(key: 'mag_device_identity');
      expect(stored, isNotNull);
    });

    test('loadOrCreate should load existing identity if storage is not empty', () async {
      final existingIdentity = DeviceIdentity.generate();
      await mockStorage.write(
        key: 'mag_device_identity',
        value: json.encode(existingIdentity.toMap()),
      );

      final identity = await DeviceIdentity.loadOrCreate(mockStorage);

      expect(identity.mac, existingIdentity.mac);
      expect(identity.deviceId, existingIdentity.deviceId);
    });

    test('toMap and fromMap should be consistent', () {
      final original = DeviceIdentity.generate();
      final map = original.toMap();
      final decoded = DeviceIdentity.fromMap(map);

      expect(decoded.mac, original.mac);
      expect(decoded.serialNumber, original.serialNumber);
      expect(decoded.deviceId, original.deviceId);
      expect(decoded.deviceId2, original.deviceId2);
      expect(decoded.signature, original.signature);
      expect(decoded.hwVersion, original.hwVersion);
      expect(decoded.imageVersion, original.imageVersion);
      expect(decoded.stbType, original.stbType);
      expect(decoded.model, original.model);
    });
  });
}
