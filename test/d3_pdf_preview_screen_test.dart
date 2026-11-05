import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:d3_pdf_preview/d3_pdf_preview.dart';
import 'package:d3_ui/d3_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<ui.Image> _page(WidgetTester t) async => (await t.runAsync(() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(
    const ui.Rect.fromLTWH(0, 0, 60, 85),
    ui.Paint()..color = const Color(0xFFFFFFFF),
  );
  return r.endRecording().toImage(60, 85);
}))!;

void main() {
  Widget app(Widget screen) =>
      MaterialApp(theme: D3AppTheme.light(), home: screen);

  testWidgets(
    'shows progress, then the summary, the zoom hint and the actions',
    (t) async {
      final image = await _page(t);
      final pdf = Completer<Uint8List>();
      Uint8List? seen;
      var calls = 0;
      await t.pumpWidget(
        app(
          D3PdfPreviewScreen(
            title: 'Visit log',
            summaryLines: const ['Nov 1 to Nov 30', '7 visits'],
            bytes: pdf.future,
            infoMessage: 'This is what the PDF will contain.',
            rasterizer: (bytes, {required dpi, pages}) async* {
              yield image.clone();
            },
            bottomBuilder: (context, data) {
              calls++;
              seen = data;
              return D3Button(
                label: 'Save',
                onPressed: data == null ? null : () {},
              );
            },
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Pinch or double-tap to zoom'), findsNothing);
      expect(seen, isNull, reason: 'buttons get null while the PDF builds');

      pdf.complete(Uint8List(2048));
      await t.pumpAndSettle();
      expect(find.text('Nov 1 to Nov 30 · 7 visits · 2 KB'), findsOneWidget);
      expect(find.text('Pinch or double-tap to zoom'), findsOneWidget);
      expect(seen, isNotNull);
      expect(calls, greaterThan(1));
      expect(find.byType(D3PdfViewer), findsOneWidget);
      expect(find.byType(D3InfoButton), findsOneWidget);
    },
  );

  testWidgets('no info button unless there is an info text', (t) async {
    await t.pumpWidget(
      app(
        D3PdfPreviewScreen(
          title: 'x',
          bytes: Future.value(Uint8List(10)),
          rasterizer: (bytes, {required dpi, pages}) => const Stream.empty(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(D3InfoButton), findsNothing);
  });

  testWidgets('a PDF that fails to build shows the error, not the pages', (
    t,
  ) async {
    final pdf = Completer<Uint8List>();
    await t.pumpWidget(
      app(D3PdfPreviewScreen(title: 'Visit log', bytes: pdf.future)),
    );
    pdf.completeError(StateError('boom'));
    await t.pumpAndSettle();
    expect(find.text('Could not build the report'), findsOneWidget);
    expect(find.byType(D3PdfViewer), findsNothing);
    expect(find.text('Go back'), findsOneWidget);
  });
}
