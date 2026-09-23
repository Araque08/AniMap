import 'package:flutter/material.dart';

import '../../map/presentation/pages/map_page.dart';
import '../../admin/presentation/pages/admin_home_page.dart';
import '../data/session_manager.dart';
import 'pages/login_page.dart';

class SessionGate extends StatefulWidget {
  final SessionManager sessionManager;
  final WidgetBuilder? authenticatedBuilder;
  final WidgetBuilder? unauthenticatedBuilder;

  const SessionGate({
    super.key,
    required this.sessionManager,
    this.authenticatedBuilder,
    this.unauthenticatedBuilder,
  });

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  @override
  void initState() {
    super.initState();
    widget.sessionManager.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.sessionManager,
      builder: (context, _) {
        switch (widget.sessionManager.status) {
          case SessionStatus.authenticated:
            return widget.authenticatedBuilder?.call(context) ??
                (widget.sessionManager.role == 'ADMINISTRADOR'
                    ? AdminHomePage(sessionManager: widget.sessionManager)
                    : widget.sessionManager.role == 'USUARIO'
                    ? const MapPage()
                    : const LoginPage());
          case SessionStatus.unauthenticated:
            return widget.unauthenticatedBuilder?.call(context) ??
                const LoginPage();
          case SessionStatus.connectionError:
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No fue posible comprobar tu sesión. Revisa tu conexión.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: widget.sessionManager.bootstrap,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          case SessionStatus.checking:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
        }
      },
    );
  }
}
