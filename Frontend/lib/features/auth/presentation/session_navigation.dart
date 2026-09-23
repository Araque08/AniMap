import 'package:flutter/material.dart';

import '../data/session_manager.dart';

Future<bool> confirmLogoutAndNavigate(
  BuildContext context, {
  SessionManager? sessionManager,
  bool closeDrawer = false,
}) async {
  final navigator = Navigator.of(context);
  if (closeDrawer && navigator.canPop()) navigator.pop();

  final confirmed = await showDialog<bool>(
    context: navigator.context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('¿Cerrar sesión?'),
      content: const Text(
        '¿Estás seguro de que deseas cerrar tu sesión en AniMap?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;
  if (!navigator.mounted) return false;
  await logoutAndNavigate(navigator.context, sessionManager: sessionManager);
  return true;
}

Future<void> logoutAndNavigate(
  BuildContext context, {
  SessionManager? sessionManager,
  bool closeDrawer = false,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (closeDrawer && navigator.canPop()) navigator.pop();
  final result = await (sessionManager ?? SessionManager.instance).logout();
  navigator.pushNamedAndRemoveUntil('/login', (_) => false);
  if (result.hadStoredSession && !result.remoteRevoked) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Sesión cerrada en este dispositivo. No se pudo confirmar la revocación remota.',
          ),
        ),
      );
    });
  }
}
