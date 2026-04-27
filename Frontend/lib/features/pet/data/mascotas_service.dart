import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class MascotasService {
  static const String baseUrl = 'http://10.0.2.2:3000/api/pets';

  static Future<Map<String, dynamic>> registrarMascota({
    required int fkUsuario,
    required int fkEspecie,
    int? fkRaza,
    required String nombre,
    required String color,
    int? edadAprox,
    String? unidadEdad,
    required String sexo,
    String? observaciones,
    required List<XFile> imagenes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(baseUrl),
    );

    request.fields['fk_usuario'] = fkUsuario.toString();
    request.fields['fk_especie'] = fkEspecie.toString();
    request.fields['nombre'] = nombre;
    request.fields['color'] = color;
    request.fields['sexo'] = sexo;

    if (fkRaza != null) {
      request.fields['fk_raza'] = fkRaza.toString();
    }

    if (edadAprox != null) {
      request.fields['edad_aprox'] = edadAprox.toString();
    }

    if (unidadEdad != null) {
      request.fields['unidad_edad'] = unidadEdad;
    }

    if (observaciones != null && observaciones.trim().isNotEmpty) {
      request.fields['observaciones'] = observaciones.trim();
    }

    for (final imagen in imagenes) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'imagenes',
          imagen.path,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    final data = jsonDecode(response.body);

    if (response.statusCode != 201 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'Error registrando mascota');
    }

    return data;
  }
}