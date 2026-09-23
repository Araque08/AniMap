import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/account_settings_service.dart';
import '../../data/profile_service.dart';

typedef PersonalProfileUpdater =
    Future<Map<String, dynamic>> Function({
      required String nombre,
      required String telefono,
    });
typedef PersonalProfileLoader = Future<Map<String, dynamic>> Function();

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({
    super.key,
    required this.profile,
    required this.onUpdated,
    this.onProfileUpdated,
    this.profileUpdater,
    this.profileLoader,
  });

  final Map<String, dynamic> profile;
  final VoidCallback onUpdated;
  final ValueChanged<Map<String, dynamic>>? onProfileUpdated;
  final PersonalProfileUpdater? profileUpdater;
  final PersonalProfileLoader? profileLoader;

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late Map<String, dynamic> _currentProfile;
  late String _originalName;
  late String _originalPhone;
  bool _isSaving = false;

  static const Color darkGreen = Color(0xFF3F9B67);

  @override
  void initState() {
    super.initState();
    _currentProfile = Map<String, dynamic>.from(widget.profile);
    _originalName = _normalizeName(_currentProfile['nombre']?.toString() ?? '');
    _originalPhone = _normalizePhone(
      _currentProfile['telefono']?.toString() ?? '',
    );
    _nameController = TextEditingController(text: _originalName);
    _phoneController = TextEditingController(text: _originalPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _normalizeName(_nameController.text);
    final phone = _normalizePhone(_phoneController.text);
    if (name == _originalName &&
        _phoneForComparison(phone) == _phoneForComparison(_originalPhone)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No realizaste cambios.')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updater = widget.profileUpdater ?? ProfileService.actualizarPerfil;
      final updatedProfile = await updater(nombre: name, telefono: phone);
      if (!mounted) return;

      final finalProfile = Map<String, dynamic>.from(updatedProfile);
      final savedName = _normalizeName(
        finalProfile['nombre']?.toString() ?? name,
      );
      final savedPhone = _normalizePhone(
        finalProfile['telefono']?.toString() ?? phone,
      );
      setState(() {
        _currentProfile = finalProfile;
        _originalName = savedName;
        _originalPhone = savedPhone;
        _nameController.text = savedName;
        _phoneController.text = savedPhone;
        _isSaving = false;
      });
      widget.onProfileUpdated?.call(finalProfile);
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

  static String _normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _normalizePhone(String value) => value.trim();

  static String _phoneForComparison(String value) =>
      value.replaceAll(RegExp(r'\s+'), '');

  @override
  Widget build(BuildContext context) {
    final photoUrl = ProfileService.absolutePhotoUrl(
      _currentProfile['foto_url'],
    );
    final hasPhoto = photoUrl != null;
    final name = _normalizeName(_currentProfile['nombre']?.toString() ?? '');
    final email = _currentProfile['email']?.toString().trim() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F4),
      appBar: AppBar(
        title: const Text('Información Personal'),
        backgroundColor: const Color(0xFFF3F7F4),
        foregroundColor: const Color(0xFF263238),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4AAA70), Color(0xFF75C990)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    key: const ValueKey('personal-info-avatar'),
                    radius: 52,
                    backgroundColor: const Color(0xFFD8E7DD),
                    backgroundImage: hasPhoto
                        ? NetworkImage(
                            photoUrl,
                            headers: ProfileService.imageHeaders,
                          )
                        : null,
                    onBackgroundImageError: hasPhoto ? (_, _) {} : null,
                    child: hasPhoto
                        ? null
                        : const Icon(
                            Icons.person_rounded,
                            size: 58,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name.isEmpty ? 'Usuario AniMap' : name,
                    key: const ValueKey('personal-info-header-name'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFEAF7EE)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Datos de tu cuenta',
                    style: TextStyle(
                      color: Color(0xFF33483E),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ProfileField(
                    label: 'Nombre',
                    controller: _nameController,
                    icon: Icons.person_outline,
                    enabled: !_isSaving,
                    validator: (value) {
                      final normalized = _normalizeName(value ?? '');
                      if (normalized.length < 3) {
                        return 'El nombre es muy corto';
                      }
                      if (normalized.length > 120) {
                        return 'El nombre es demasiado largo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _ProfileField(
                    label: 'Correo',
                    initialValue: email,
                    icon: Icons.email_outlined,
                    readOnly: true,
                  ),
                  const SizedBox(height: 14),
                  _ProfileField(
                    label: 'Teléfono',
                    controller: _phoneController,
                    icon: Icons.phone_outlined,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+\-\s()]'),
                      ),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    validator: (value) {
                      final phone = _normalizePhone(value ?? '');
                      if (phone.length < 10 ||
                          phone.length > 20 ||
                          !RegExp(r'^[0-9+\-\s()]+$').hasMatch(phone)) {
                        return 'Número de teléfono no válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveProfile,
                      icon: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
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
          ],
        ),
      ),
    );
  }
}

typedef ActiveSessionsLoader = Future<List<ActiveSessionData>> Function();
typedef ActiveSessionRevoker = Future<void> Function(int sessionId);

class ActiveSessionsPage extends StatefulWidget {
  const ActiveSessionsPage({super.key, this.loader, this.revoker});

  final ActiveSessionsLoader? loader;
  final ActiveSessionRevoker? revoker;

  @override
  State<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends State<ActiveSessionsPage> {
  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);

  List<ActiveSessionData>? _sessions;
  String? _error;
  bool _loading = true;
  final Set<int> _revoking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? AccountSettingsService.loadSessions;
      final sessions = await loader();
      sessions.sort((a, b) {
        if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _confirmRevoke(ActiveSessionData session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cerrar esta sesión?'),
        content: const Text('El dispositivo deberá iniciar sesión nuevamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-revoke-session'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revoking.add(session.id));
    try {
      final revoker = widget.revoker ?? AccountSettingsService.revokeSession;
      await revoker(session.id);
      if (!mounted) return;
      setState(() {
        _sessions?.removeWhere((item) => item.id == session.id);
        _revoking.remove(session.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión cerrada correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _revoking.remove(session.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesiones activas'),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _LoadError(message: _error!, onRetry: _load);
    }
    final sessions = _sessions ?? const <ActiveSessionData>[];
    if (sessions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay sesiones activas para mostrar.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final revoking = _revoking.contains(session.id);
        return Container(
          key: ValueKey('active-session-${session.id}'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: session.isCurrent
                ? const Color(0xFFEAF7EF)
                : const Color(0xFFF5F8F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: session.isCurrent ? primaryGreen : const Color(0xFFE0E0E0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                session.isCurrent ? Icons.phone_android : Icons.devices,
                color: darkGreen,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.isCurrent
                          ? 'Este dispositivo'
                          : 'Otro dispositivo',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.isCurrent ? 'Sesión actual' : session.deviceId,
                      style: TextStyle(
                        fontSize: 12,
                        color: session.isCurrent ? darkGreen : Colors.black54,
                        fontWeight: session.isCurrent
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Inicio: ${_formatDate(session.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    if (!session.isCurrent) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: ValueKey('revoke-session-${session.id}'),
                          onPressed: revoking
                              ? null
                              : () => _confirmRevoke(session),
                          child: revoking
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Cerrar sesión'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef NotificationPreferencesLoader =
    Future<NotificationPreferencesData> Function();
typedef NotificationPreferencesUpdater =
    Future<NotificationPreferencesData> Function(
      NotificationPreferencesData preferences,
    );

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key, this.loader, this.updater});

  final NotificationPreferencesLoader? loader;
  final NotificationPreferencesUpdater? updater;

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);

  static const species = ['Todas', 'Perro', 'Gato'];
  static const events = ['Todos', 'Pérdida', 'Avistamiento', 'Encontrado'];
  static const radiuses = [1, 2, 5];

  NotificationPreferencesData? _original;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  bool notificationsEnabled = true;
  bool onlyMyZone = false;
  String selectedSpecies = 'Todas';
  String selectedEvent = 'Todos';
  int selectedRadius = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loader = widget.loader ?? AccountSettingsService.loadPreferences;
      final preferences = await loader();
      if (!mounted) return;
      setState(() {
        _apply(preferences);
        _original = preferences;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _apply(NotificationPreferencesData preferences) {
    notificationsEnabled = preferences.notificationsEnabled;
    onlyMyZone = preferences.onlyMyZone;
    selectedSpecies = preferences.species ?? 'Todas';
    selectedEvent = switch (preferences.eventType) {
      'PERDIDA' => 'Pérdida',
      'AVISTAMIENTO' => 'Avistamiento',
      'ENCONTRADO' => 'Encontrado',
      _ => 'Todos',
    };
    selectedRadius = preferences.radiusKm;
  }

  NotificationPreferencesData _current() {
    return NotificationPreferencesData(
      notificationsEnabled: notificationsEnabled,
      onlyMyZone: onlyMyZone,
      species: selectedSpecies == 'Todas' ? null : selectedSpecies,
      eventType: switch (selectedEvent) {
        'Pérdida' => 'PERDIDA',
        'Avistamiento' => 'AVISTAMIENTO',
        'Encontrado' => 'ENCONTRADO',
        _ => null,
      },
      radiusKm: selectedRadius,
    );
  }

  Future<void> _save() async {
    final original = _original;
    if (original == null || _saving) return;
    final current = _current();
    if (current.hasSameValues(original)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No realizaste cambios.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final updater = widget.updater ?? AccountSettingsService.savePreferences;
      final saved = await updater(current);
      if (!mounted) return;
      setState(() {
        _apply(saved);
        _original = saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferencias guardadas correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          action: SnackBarAction(label: 'Reintentar', onPressed: _save),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferencias de notificación'),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _original == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _original == null) {
      return _LoadError(message: _loadError!, onRetry: _load);
    }

    return ListView(
      key: const ValueKey('notification-preferences-form'),
      padding: const EdgeInsets.all(20),
      children: [
        SwitchListTile(
          key: const ValueKey('notifications-enabled'),
          contentPadding: EdgeInsets.zero,
          value: notificationsEnabled,
          activeThumbColor: darkGreen,
          title: const Text('Recibir notificaciones'),
          subtitle: const Text('Permite recibir alertas de AniMap'),
          onChanged: (value) => setState(() {
            notificationsEnabled = value;
          }),
        ),
        const Divider(),
        SwitchListTile(
          key: const ValueKey('only-my-zone'),
          contentPadding: EdgeInsets.zero,
          value: onlyMyZone,
          activeThumbColor: darkGreen,
          title: const Text('Solo mi zona'),
          subtitle: const Text('Limita las alertas al radio configurado'),
          onChanged: notificationsEnabled
              ? (value) => setState(() {
                  onlyMyZone = value;
                })
              : null,
        ),
        const SizedBox(height: 14),
        _sectionTitle('Especie'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('notification-species'),
          initialValue: selectedSpecies,
          isExpanded: true,
          decoration: _inputDecoration(),
          items: species
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: notificationsEnabled
              ? (value) => setState(() {
                  selectedSpecies = value ?? selectedSpecies;
                })
              : null,
        ),
        const SizedBox(height: 14),
        _sectionTitle('Tipo de evento'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('notification-event'),
          initialValue: selectedEvent,
          isExpanded: true,
          decoration: _inputDecoration(),
          items: events
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: notificationsEnabled
              ? (value) => setState(() {
                  selectedEvent = value ?? selectedEvent;
                })
              : null,
        ),
        const SizedBox(height: 14),
        _sectionTitle('Distancia'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: const ValueKey('notification-radius'),
          initialValue: selectedRadius,
          decoration: _inputDecoration(),
          items: radiuses
              .map(
                (radius) =>
                    DropdownMenuItem(value: radius, child: Text('$radius km')),
              )
              .toList(),
          onChanged: notificationsEnabled && onlyMyZone
              ? (value) => setState(() {
                  selectedRadius = value ?? selectedRadius;
                })
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          onlyMyZone
              ? 'Se usarán $selectedRadius km para definir tu zona.'
              : 'El radio se conserva y se aplicará al activar Solo mi zona.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            key: const ValueKey('save-notification-preferences'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
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
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('retry-account-settings'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
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
