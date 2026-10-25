
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';

// Modelo para representar un reporte de AniMap.
class MascotaReporte {
  final String id;
  final String nombre;
  final String detalles;
  final String ubicacion;
  final String referencia;
  final String descripcion;
  final DateTime? fecha;
  final String? imagenUrl;
  final List<String> imagenes;
  final String tipo;
  final double? latitud;
  final bool esPropietario;
  final double? longitud;

  const MascotaReporte({
    required this.id,
    required this.nombre,
    required this.detalles,
    required this.ubicacion,
    required this.referencia,
    required this.descripcion,
    required this.fecha,
    required this.imagenUrl,
    required this.imagenes,
    required this.tipo,
    required this.latitud,
    required this.esPropietario,
    required this.longitud,
  });

  factory MascotaReporte.fromJson(Map<String, dynamic> json) {
    final config = ApiConfig.current;

    String? resolverImagen(dynamic valor) {
      if (valor == null) return null;

      final ruta = valor.toString().trim();
      if (ruta.isEmpty) return null;

      return config.resolveUrl(ruta);
    }

    final rutasImagenes = json['imageUrls'];

    return MascotaReporte(
      id: json['id']?.toString() ?? '',
      nombre: json['petName']?.toString() ?? 'Sin nombre',
      detalles: json['details']?.toString() ?? '',
      ubicacion: json['location']?.toString() ?? '',
      referencia: json['reference']?.toString() ?? '',
      descripcion: json['description']?.toString() ?? '',
      fecha: DateTime.tryParse(
        json['dateText']?.toString() ?? '',
      ),
      imagenUrl: resolverImagen(json['imageUrl']),
      imagenes: rutasImagenes is List
          ? rutasImagenes
          .map(resolverImagen)
          .whereType<String>()
          .toList()
          : [],
      tipo: json['type']?.toString() ?? '',
      latitud: (json['lat'] as num?)?.toDouble(),
      esPropietario: json['isOwner'] == true,
      longitud: (json['lng'] as num?)?.toDouble(),
    );
  }

  bool get estaPerdida => tipo == 'lost';

  bool get esAvistamiento => tipo == 'sighting';

  bool get fueEncontrada => tipo == 'found';
}

// Servicio para consultar reportes reales del backend.
class MascotasPerdidasService {
  final http.Client _client;

  MascotasPerdidasService({http.Client? client})
      : _client = client ?? http.Client();

  Future<List<MascotaReporte>> obtenerReportes() async {
    final uri = Uri.parse(
      '${ApiConfig.current.baseUrl}/map/reports',
    );

    try {
      final respuesta = await AuthenticatedHttpClient
          .instance
          .get(
        uri,
        optionalAuthentication: true,
      )
          .timeout(const Duration(seconds: 15));

      if (respuesta.statusCode != 200) {
        throw Exception(
          'Error del servidor: ${respuesta.statusCode}',
        );
      }

      final dynamic resultado = jsonDecode(respuesta.body);

      if (resultado is! Map<String, dynamic>) {
        throw const FormatException(
          'Respuesta del servidor no válida',
        );
      }

      if (resultado['ok'] != true) {
        throw Exception(
          resultado['message']?.toString() ??
              'No fue posible consultar los reportes',
        );
      }

      final dynamic datos = resultado['data'];

      if (datos is! List) {
        throw const FormatException(
          'La respuesta no contiene una lista de reportes',
        );
      }

      return datos
          .map((item) => MascotaReporte.fromJson(
        Map<String, dynamic>.from(item as Map),
      ))
          .toList();
    } catch (error) {
      throw Exception(
        'No se pudieron cargar los reportes: $error',
      );
    }
  }

  // Solo mascotas con reportes activos.
  Future<List<MascotaReporte>> obtenerMascotasPerdidas() async {
    final reportes = await obtenerReportes();

    return reportes
        .where((reporte) => reporte.estaPerdida)
        .toList();
  }

  // Avistamientos registrados por la comunidad.
  Future<List<MascotaReporte>> obtenerAvistamientos() async {
    final reportes = await obtenerReportes();

    return reportes
        .where((reporte) => reporte.esAvistamiento)
        .toList();
  }

  void dispose() {
    _client.close();
  }
}
