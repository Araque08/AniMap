import 'package:flutter/services.dart';

class DeviceLocationException implements Exception {
  final String message;

  DeviceLocationException(this.message);

  @override
  String toString() => message;
}

class DeviceLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;

  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });
}

class DeviceLocationService {
  static const MethodChannel _channel = MethodChannel('animap/location');

  static Future<DeviceLocation> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getCurrentLocation',
      );
      final latitude = (result?['latitude'] as num?)?.toDouble();
      final longitude = (result?['longitude'] as num?)?.toDouble();
      final accuracy = (result?['accuracy'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        throw DeviceLocationException(
          'El dispositivo no devolvió una ubicación válida',
        );
      }
      return DeviceLocation(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
      );
    } on PlatformException catch (error) {
      throw DeviceLocationException(
        error.message ?? 'No fue posible obtener la ubicación GPS',
      );
    }
  }
}
