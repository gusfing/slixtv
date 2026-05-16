import 'dart:math';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdentity {
  final String mac;
  final String serialNumber;
  final String deviceId;
  final String deviceId2;
  final String signature;
  final String hwVersion;
  final String imageVersion;
  final String stbType;
  final String model;

  DeviceIdentity({
    required this.mac,
    required this.serialNumber,
    required this.deviceId,
    required this.deviceId2,
    required this.signature,
    required this.hwVersion,
    required this.imageVersion,
    required this.stbType,
    required this.model,
  });

  Map<String, String> toMap() {
    return {
      'mac': mac,
      'serial_number': serialNumber,
      'device_id': deviceId,
      'device_id2': deviceId2,
      'signature': signature,
      'hw_version': hwVersion,
      'image_version': imageVersion,
      'stb_type': stbType,
      'model': model,
    };
  }

  factory DeviceIdentity.fromMap(Map<String, dynamic> map) {
    return DeviceIdentity(
      mac: map['mac'] ?? '',
      serialNumber: map['serial_number'] ?? '',
      deviceId: map['device_id'] ?? '',
      deviceId2: map['device_id2'] ?? '',
      signature: map['signature'] ?? '',
      hwVersion: map['hw_version'] ?? '2.6.0',
      imageVersion: map['image_version'] ?? '218',
      stbType: map['stb_type'] ?? 'MAG250',
      model: map['model'] ?? 'MAG250',
    );
  }

  static Future<DeviceIdentity> loadOrCreate(FlutterSecureStorage storage) async {
    final String? storedJson = await storage.read(key: 'mag_device_identity');
    
    if (storedJson != null) {
      try {
        final Map<String, dynamic> map = json.decode(storedJson);
        return DeviceIdentity.fromMap(map);
      } catch (e) {
        // Fallback to generation if decoding fails
      }
    }

    final identity = generate();
    await identity.save(storage);
    return identity;
  }

  Future<void> save(FlutterSecureStorage storage) async {
    await storage.write(key: 'mag_device_identity', value: json.encode(toMap()));
  }

  static DeviceIdentity generate() {
    final random = Random();
    
    // Generate MAC: 00:1A:79:XX:XX:XX
    final macParts = [
      '00', '1A', '79',
      _toHex(random.nextInt(256)),
      _toHex(random.nextInt(256)),
      _toHex(random.nextInt(256)),
    ];
    final mac = macParts.join(':').toUpperCase();

    // Serial number derivation: 12 uppercase alphanumeric from MAC
    // Usually MAG serials look like "001A79XXXXXX" or similar
    final serialNumber = mac.replaceAll(':', '').toUpperCase();

    // device_id and device_id2: 32-char lowercase hex strings
    final deviceId = _generateRandomHex(32);
    final deviceId2 = _generateRandomHex(32);

    // Signature: typically a hash or random hex
    final signature = _generateRandomHex(32);

    return DeviceIdentity(
      mac: mac,
      serialNumber: serialNumber,
      deviceId: deviceId,
      deviceId2: deviceId2,
      signature: signature,
      hwVersion: '2.6.0',
      imageVersion: '218',
      stbType: 'MAG250',
      model: 'MAG250',
    );
  }

  static String _toHex(int value) {
    return value.toRadixString(16).padLeft(2, '0');
  }

  static String _generateRandomHex(int length) {
    final random = Random();
    final chars = '0123456789abcdef';
    return List.generate(length, (index) => chars[random.nextInt(chars.length)]).join();
  }

  DeviceIdentity copyWith({
    String? mac,
    String? serialNumber,
    String? deviceId,
    String? deviceId2,
    String? signature,
    String? hwVersion,
    String? imageVersion,
    String? stbType,
    String? model,
  }) {
    return DeviceIdentity(
      mac: mac ?? this.mac,
      serialNumber: serialNumber ?? this.serialNumber,
      deviceId: deviceId ?? this.deviceId,
      deviceId2: deviceId2 ?? this.deviceId2,
      signature: signature ?? this.signature,
      hwVersion: hwVersion ?? this.hwVersion,
      imageVersion: imageVersion ?? this.imageVersion,
      stbType: stbType ?? this.stbType,
      model: model ?? this.model,
    );
  }
}
