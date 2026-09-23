import 'package:flutter/material.dart';

import '../../../auth/presentation/session_navigation.dart';
import '../../../auth/data/session_manager.dart';
import 'admin_faq_page.dart';
import 'admin_faq_categories_page.dart';

class AdminHomePage extends StatelessWidget {
  final SessionManager? sessionManager;
  const AdminHomePage({super.key, this.sessionManager});

  static const green = Color(0xFF3F9568);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7FAF8),
    appBar: AppBar(
      title: const Text('Panel administrativo'),
      backgroundColor: const Color(0xFFF7FAF8),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          tooltip: 'Cerrar sesión',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () =>
              confirmLogoutAndNavigate(context, sessionManager: sessionManager),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: green,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AniMap',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Gestiona el centro de ayuda',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Administración',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _AdminLink(
          title: 'Preguntas frecuentes',
          subtitle: 'Crear, editar y activar FAQ',
          icon: Icons.help_outline_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminFaqPage()),
          ),
        ),
        const SizedBox(height: 12),
        _AdminLink(
          title: 'Categorías FAQ',
          subtitle: 'Organizar las preguntas frecuentes',
          icon: Icons.category_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminFaqCategoriesPage()),
          ),
        ),
      ],
    ),
  );
}

class _AdminLink extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _AdminLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: Icon(icon, color: AdminHomePage.green),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
