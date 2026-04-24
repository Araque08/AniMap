import 'package:flutter/material.dart';

/*
  Aquí hicimos una pantalla principal temporal.
  La usamos para confirmar que el inicio de sesión sí entra a la aplicación.
*/
class HomePage extends StatelessWidget {
  final String userName;

  const HomePage({
    super.key,
    required this.userName,
  });

  static const Color backgroundColor = Color(0xFFDDE6D8);
  static const Color primaryGreen = Color(0xFF73C15A);
  static const Color darkText = Color(0xFF415466);
  static const Color accentGreen = Color(0xFF3F9E57);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'AniMap',
          style: TextStyle(
            color: darkText,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $userName',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bienvenido a AniMap. Desde aquí podrás gestionar mascotas, reportes, avistamientos y notificaciones.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7A70),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  children: const [
                    _HomeOptionCard(
                      icon: Icons.pets,
                      title: 'Mis mascotas',
                      description: 'Registra y consulta tus mascotas.',
                    ),
                    _HomeOptionCard(
                      icon: Icons.report_problem_outlined,
                      title: 'Reportar pérdida',
                      description: 'Crea un reporte de mascota perdida.',
                    ),
                    _HomeOptionCard(
                      icon: Icons.visibility_outlined,
                      title: 'Avistamiento',
                      description: 'Reporta una mascota vista.',
                    ),
                    _HomeOptionCard(
                      icon: Icons.map_outlined,
                      title: 'Mapa',
                      description: 'Consulta reportes cercanos.',
                    ),
                    _HomeOptionCard(
                      icon: Icons.notifications_none,
                      title: 'Notificaciones',
                      description: 'Revisa alertas y coincidencias.',
                    ),
                    _HomeOptionCard(
                      icon: Icons.person_outline,
                      title: 'Perfil',
                      description: 'Administra tu información.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _HomeOptionCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  static const Color primaryGreen = Color(0xFF73C15A);
  static const Color darkText = Color(0xFF415466);
  static const Color accentGreen = Color(0xFF3F9E57);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Abrir: $title'),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFC8D1C3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: primaryGreen.withOpacity(0.22),
              child: Icon(
                icon,
                color: accentGreen,
              ),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: darkText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF718076),
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}