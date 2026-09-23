import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';

class ReportTypeSelectorPage extends StatelessWidget {
  const ReportTypeSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F5),
      appBar: AppBar(
        title: const Text('Reportar'),
        backgroundColor: const Color(0xFFDFF3E8),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '¿Qué deseas reportar?',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Selecciona el tipo de información que quieres compartir con la comunidad.',
                    style: TextStyle(color: Color(0xFF65756C), height: 1.35),
                  ),
                  const SizedBox(height: 22),
                  _ReportOption(
                    key: const ValueKey('report-lost-pet'),
                    icon: Icons.campaign_outlined,
                    title: 'Mascota perdida',
                    subtitle: 'Reporta una de tus mascotas registradas.',
                    onTap: () =>
                        Navigator.pushNamed(context, '/create-lost-report'),
                  ),
                  const SizedBox(height: 14),
                  _ReportOption(
                    key: const ValueKey('report-sighting'),
                    icon: Icons.visibility_outlined,
                    title: 'Avistamiento',
                    subtitle: 'Informa sobre una mascota que viste.',
                    onTap: () =>
                        Navigator.pushNamed(context, '/create-sighting'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const BottomMenuAnimap(currentIndex: 1),
    );
  }
}

class _ReportOption extends StatelessWidget {
  const _ReportOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFFDFF3E8),
                child: Icon(icon, color: const Color(0xFF3F9568)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF65756C)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
