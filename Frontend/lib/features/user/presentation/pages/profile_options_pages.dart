import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/profile_service.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({
    super.key,
    required this.profile,
    required this.onUpdated,
  });

  final Map<String, dynamic> profile;
  final VoidCallback onUpdated;

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _isSaving = false;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profile['nombre']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.profile['telefono']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await ProfileService.actualizarPerfil(
        nombre: _nameController.text.trim(),
        telefono: _phoneController.text.trim(),
      );

      final refreshedProfile = await ProfileService.obtenerPerfil();

      if (!mounted) return;

      _nameController.text = refreshedProfile['nombre']?.toString() ?? '';
      _phoneController.text = refreshedProfile['telefono']?.toString() ?? '';
      widget.onUpdated();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado correctamente')),
      );
    } on ProfileException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar el perfil')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.profile['foto_url']?.toString();
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Información Personal'),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            CircleAvatar(
              radius: 55,
              backgroundColor: const Color(0xFFD7D7D7),
              backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
              child: hasPhoto
                  ? null
                  : const Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),
            _ProfileField(
              label: 'Nombre',
              controller: _nameController,
              icon: Icons.person,
              enabled: !_isSaving,
              validator: (value) {
                if (value == null || value.trim().length < 3) {
                  return 'El nombre es muy corto';
                }
                if (value.trim().length > 120) {
                  return 'El nombre es demasiado largo';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _ProfileField(
              label: 'Correo',
              initialValue: widget.profile['email']?.toString() ?? '',
              icon: Icons.email,
              readOnly: true,
            ),
            const SizedBox(height: 14),
            _ProfileField(
              label: 'Teléfono',
              controller: _phoneController,
              icon: Icons.phone,
              enabled: !_isSaving,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
                LengthLimitingTextInputFormatter(20),
              ],
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (phone.length < 10 ||
                    phone.length > 20 ||
                    !RegExp(r'^[0-9+\-\s()]+$').hasMatch(phone)) {
                  return 'Número de teléfono no válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Guardar información'),
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
              border: Border.all(color: const Color(0xFFE0E0E0)),
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
                  TextButton(onPressed: () {}, child: const Text('Cerrar')),
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
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedSpecies,
            decoration: _inputDecoration(),
            items: species.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
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
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedEvent,
            decoration: _inputDecoration(),
            items: events.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
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
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.icon,
    this.controller,
    this.initialValue,
    this.readOnly = false,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final String? initialValue;
  final bool readOnly;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      readOnly: readOnly,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF5F8F6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
    );
  }
}
