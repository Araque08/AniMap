import 'package:animap/widgets/bottom_menu_animap.dart';
import 'package:animap/widgets/location_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  testWidgets('el menú inferior usa los mismos tres destinos', (tester) async {
    Future<void> expectDestination({
      required int currentIndex,
      required IconData icon,
      required String destination,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: const Text('origen'),
            bottomNavigationBar: BottomMenuAnimap(currentIndex: currentIndex),
          ),
          routes: {
            '/home': (_) => const Scaffold(body: Text('destino-inicio')),
            '/create-report': (_) =>
                const Scaffold(body: Text('destino-reporte')),
            '/profile': (_) => const Scaffold(body: Text('destino-perfil')),
          },
        ),
      );

      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      expect(find.text(destination), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    }

    await expectDestination(
      currentIndex: -1,
      icon: Icons.home_rounded,
      destination: 'destino-inicio',
    );
    await expectDestination(
      currentIndex: -1,
      icon: Icons.pets_rounded,
      destination: 'destino-reporte',
    );
    await expectDestination(
      currentIndex: -1,
      icon: Icons.person_rounded,
      destination: 'destino-perfil',
    );
    await expectDestination(
      currentIndex: 0,
      icon: Icons.pets_rounded,
      destination: 'destino-reporte',
    );
    await expectDestination(
      currentIndex: 1,
      icon: Icons.person_rounded,
      destination: 'destino-perfil',
    );
    await expectDestination(
      currentIndex: 2,
      icon: Icons.home_rounded,
      destination: 'destino-inicio',
    );
  });

  testWidgets('selector de mapa confirma y devuelve la ubicación', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _LocationPickerHarness()));

    await tester.tap(find.text('Abrir selector'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar ubicación'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fake-map')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-location')));
    await tester.pumpAndSettle();

    expect(find.text('4.650000,-74.100000'), findsOneWidget);
  });
}

class _LocationPickerHarness extends StatefulWidget {
  const _LocationPickerHarness();

  @override
  State<_LocationPickerHarness> createState() => _LocationPickerHarnessState();
}

class _LocationPickerHarnessState extends State<_LocationPickerHarness> {
  LatLng? _location;

  Future<void> _openPicker() async {
    final location = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialPosition: const LatLng(4.6569, -74.1095),
          mapBuilder: (context, initial, selected, onSelect) {
            return GestureDetector(
              key: const ValueKey('fake-map'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(const LatLng(4.65, -74.10)),
              child: const ColoredBox(color: Colors.blueGrey),
            );
          },
        ),
      ),
    );
    if (mounted && location != null) setState(() => _location = location);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: _openPicker,
            child: const Text('Abrir selector'),
          ),
          if (_location != null)
            Text(
              '${_location!.latitude.toStringAsFixed(6)},'
              '${_location!.longitude.toStringAsFixed(6)}',
            ),
        ],
      ),
    );
  }
}
