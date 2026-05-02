import 'package:flutter/material.dart';

class PersonalInfoPage extends StatelessWidget {
  const PersonalInfoPage({super.key});

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Información Personal'),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 55,
              backgroundColor: Color(0xFFD7D7D7),
              child: Icon(
                Icons.person,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            _ReadOnlyField(
              label: 'Nombre',
              value: 'Felipe Meza Rodríguez',
              icon: Icons.person,
            ),
            const SizedBox(height: 14),
            _ReadOnlyField(
              label: 'Correo',
              value: 'felipe@email.com',
              icon: Icons.email,
            ),
            const SizedBox(height: 14),
            _ReadOnlyField(
              label: 'Teléfono',
              value: '3000000000',
              icon: Icons.phone,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit),
                label: const Text('Editar información'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: darkGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActiveSessionsPage extends StatelessWidget {
  const ActiveSessionsPage({super.key});

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);

  @override
  Widget build(BuildContext context) {
    final sessions = [
      {
        'device': 'Dispositivo actual',
        'detail': 'Android emulator - Sesión activa',
        'current': true,
      },
      {
        'device': 'Otro dispositivo',
        'detail': 'Último acceso reciente',
        'current': false,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesiones activas'),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(18),
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final session = sessions[index];
          final isCurrent = session['current'] == true;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8F6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE0E0E0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCurrent ? Icons.phone_android : Icons.devices,
                  color: darkGreen,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session['device'].toString(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session['detail'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isCurrent)
                  TextButton(
                    onPressed: () {},
                    child: const Text('Cerrar'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);

  bool notificationsEnabled = true;
  bool onlyMyZone = true;
  String selectedSpecies = 'Todas';
  String selectedEvent = 'Todos';

  final species = ['Todas', 'Perro', 'Gato', 'Ave'];
  final events = ['Todos', 'Pérdida', 'Avistamiento', 'Encontrado'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferencias de notificación'),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            value: notificationsEnabled,
            activeColor: darkGreen,
            title: const Text('Recibir notificaciones'),
            subtitle: const Text('Permite recibir alertas de AniMap'),
            onChanged: (value) {
              setState(() {
                notificationsEnabled = value;
              });
            },
          ),
          const Divider(),
          SwitchListTile(
            value: onlyMyZone,
            activeColor: darkGreen,
            title: const Text('Solo mi zona'),
            subtitle: const Text('Prioriza alertas cercanas al usuario'),
            onChanged: notificationsEnabled
                ? (value) {
              setState(() {
                onlyMyZone = value;
              });
            }
                : null,
          ),
          const SizedBox(height: 18),
          const Text(
            'Especie',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedSpecies,
            decoration: _inputDecoration(),
            items: species.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: notificationsEnabled
                ? (value) {
              if (value == null) return;
              setState(() {
                selectedSpecies = value;
              });
            }
                : null,
          ),
          const SizedBox(height: 18),
          const Text(
            'Tipo de evento',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedEvent,
            decoration: _inputDecoration(),
            items: events.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: notificationsEnabled
                ? (value) {
              if (value == null) return;
              setState(() {
                selectedEvent = value;
              });
            }
                : null,
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: notificationsEnabled ? () {} : null,
              icon: const Icon(Icons.save),
              label: const Text('Guardar preferencias'),
              style: ElevatedButton.styleFrom(
                backgroundColor: darkGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF5F8F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFE0E0E0),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFE0E0E0),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF5F8F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFFE0E0E0),
          ),
        ),
      ),
    );
  }
}