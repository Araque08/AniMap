import 'package:flutter/material.dart';

import '../features/report/data/geofence_service.dart';

class GeofenceValidationPanel extends StatelessWidget {
  const GeofenceValidationPanel({
    super.key,
    required this.state,
    required this.onChangeLocation,
    required this.onRetry,
  });

  final GeofenceValidationState state;
  final VoidCallback onChangeLocation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == GeofenceValidationState.idle ||
        state == GeofenceValidationState.inside) {
      return const SizedBox.shrink();
    }

    final checking = state == GeofenceValidationState.checking;
    final warning = state == GeofenceValidationState.outsideWarning;
    final message = switch (state) {
      GeofenceValidationState.checking => 'Validando zona permitida…',
      GeofenceValidationState.inside => '',
      GeofenceValidationState.outsideWarning =>
        outsideAllowedAreaWarningMessage,
      GeofenceValidationState.outsideBlocked => outsideAllowedAreaMessage,
      GeofenceValidationState.networkError => geofenceNetworkErrorMessage,
      GeofenceValidationState.idle => '',
    };

    return Container(
      key: const ValueKey('geofence-validation-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning
            ? const Color(0xFFFFF5D9)
            : checking
            ? const Color(0xFFF2F7F3)
            : const Color(0xFFFFE8E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: warning
              ? const Color(0xFFC88900)
              : checking
              ? const Color(0xFFB7CDBD)
              : const Color(0xFFD9655B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (checking)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  warning ? Icons.warning_amber_rounded : Icons.error_outline,
                  color: warning
                      ? const Color(0xFFA66F00)
                      : const Color(0xFFD1493F),
                ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          if (!checking) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  key: const ValueKey('change-geofence-location'),
                  onPressed: onChangeLocation,
                  child: const Text('Cambiar ubicación'),
                ),
                if (state == GeofenceValidationState.networkError)
                  TextButton(
                    key: const ValueKey('retry-geofence-validation'),
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
