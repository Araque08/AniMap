class ApiConfig {
  static const String baseUrl = 'http://172.24.207.228:3000/api';

  // Auth
  static const String auth = '$baseUrl/auth';

  // Usuario / perfil
  static const String users = '$baseUrl/users';
  static const String profile = '$baseUrl/profile';

  // Mascotas
  static const String pets = '$baseUrl/pets';
  static const String catalogos = '$baseUrl/catalogos';


  // Reportes
  static const String reports = '$baseUrl/reports';

  // Avistamientos
  static const String sightings = '$baseUrl/sightings';

  // Notificaciones
  static const String notifications = '$baseUrl/notifications';

  // FAQ
  static const String faq = '$baseUrl/faq';
}