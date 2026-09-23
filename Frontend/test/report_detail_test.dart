import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

MapReport detailReport({
  ReportType type = ReportType.lost,
  bool isOwner = false,
}) => MapReport(
  id: 'lost_77',
  title: 'Mascota perdida',
  petName: 'Nombre muy largo de mascota temporal para validar adaptación',
  details: 'Perro · Raza extraordinariamente larga · Café y blanco',
  location: 'Punto marcado en el mapa',
  reference: 'Frente al parque principal, junto a la portería',
  description: 'Descripción completa del reporte de prueba.',
  dateText: '12/09/2026, 10:30',
  createdDateText: '12/09/2026, 10:30',
  closedDateText: type == ReportType.found ? '12/09/2026, 12:30' : '',
  occurredAt: DateTime(2026, 9, 12, 10, 30),
  imageUrl: 'https://invalid.local/principal.png',
  imageUrls: const [
    'https://invalid.local/principal.png',
    'https://invalid.local/dos.png',
    'https://invalid.local/tres.png',
  ],
  position: const LatLng(4.6569, -74.1095),
  type: type,
  showContact: true,
  isOwner: isOwner,
  ownerName: '',
  ownerPhone: '3000000000',
  ownerEmail: '',
);

Widget fakeMap(BuildContext context, LatLng position, bool interactive) {
  return ColoredBox(
    key: ValueKey(interactive ? 'full-report-map' : 'mini-report-map'),
    color: Colors.blueGrey,
    child: Text('${position.latitude},${position.longitude}'),
  );
}

void main() {
  testWidgets('detalle activo separa ubicación y referencia', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailPage(report: detailReport(), mapBuilder: fakeMap),
      ),
    );
    await tester.pump();
    expect(find.text('ACTIVO'), findsOneWidget);
    expect(find.text('Información del reporte'), findsOneWidget);
    expect(find.text('Última ubicación reportada'), findsOneWidget);
    expect(
      find.textContaining('Ubicación: Punto marcado en el mapa'),
      findsOneWidget,
    );
    expect(find.textContaining('Referencia adicional:'), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-report-map')), findsOneWidget);
  });

  testWidgets('detalle finalizado muestra fecha del reporte y cierre', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailPage(
          report: detailReport(type: ReportType.found),
          mapBuilder: fakeMap,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('FINALIZADO'), findsOneWidget);
    expect(find.textContaining('Fecha del reporte:'), findsOneWidget);
    expect(find.textContaining('Fecha de cierre:'), findsOneWidget);
  });

  testWidgets('reporte propio nunca muestra teléfono ni contacto', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailPage(
          report: detailReport(isOwner: true),
          mapBuilder: fakeMap,
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Este reporte es tuyo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Este reporte es tuyo'), findsOneWidget);
    expect(find.text('Contactar dueño'), findsNothing);
    expect(find.text('3000000000'), findsNothing);
  });

  testWidgets('galería conserva principal primero y es solo lectura', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailPage(report: detailReport(), mapBuilder: fakeMap),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-report-gallery')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(detailReport().imageUrls.first, contains('principal.png'));
    expect(
      find.byKey(const ValueKey('report-preview-photo-0')),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-report-gallery')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('read-only-report-gallery')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('report-gallery-photo-0')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.textContaining('Cambiar principal'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('report-gallery-photo-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-photo-viewer')), findsOneWidget);
    expect(find.text('1 de 3'), findsOneWidget);
  });

  testWidgets('mapa completo conserva coordenadas y es solo consulta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailPage(report: detailReport(), mapBuilder: fakeMap),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-report-location')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-report-location')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('full-report-map')), findsOneWidget);
    expect(find.text('4.6569,-74.1095'), findsOneWidget);
    expect(find.text('Confirmar ubicación'), findsNothing);
  });

  testWidgets('detalle no genera overflow a 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailPage(report: detailReport(), mapBuilder: fakeMap),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
