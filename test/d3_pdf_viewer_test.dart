import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:d3_pdf_preview/d3_pdf_preview.dart';
import 'package:d3_ui/d3_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A stand-in for the platform rasterizer: A4-shaped images, recorded calls.
class _Fake {
  _Fake(this.base, {this.pages = 3});

  final ui.Image base;
  final int pages;
  final calls = <({double dpi, List<int>? pages})>[];
  bool fail = false;

  Stream<ui.Image> call(
    Uint8List pdf, {
    required double dpi,
    List<int>? pages,
  }) async* {
    calls.add((dpi: dpi, pages: pages));
    if (fail) throw StateError('no rasterizer');
    final count = pages == null ? this.pages : pages.length;
    for (var i = 0; i < count; i++) {
      yield base.clone();
    }
  }
}

Future<ui.Image> _a4(WidgetTester t) async {
  return (await t.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 60, 85),
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
    return recorder.endRecording().toImage(60, 85);
  }))!;
}

Widget _app(Widget child) => MaterialApp(
  theme: D3AppTheme.light(),
  home: Scaffold(body: child),
);

double _scale(WidgetTester t) => t
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

void main() {
  late _Fake fake;
  final pdf = Uint8List.fromList([1, 2, 3]);

  Future<void> pump(WidgetTester t, {int pages = 3}) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    fake = _Fake(await _a4(t), pages: pages);
    await t.pumpWidget(_app(D3PdfViewer(bytes: pdf, rasterizer: fake.call)));
    await t.pumpAndSettle();
  }

  testWidgets('shows every page, and says which one you are on', (t) async {
    await pump(t);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('the page counter follows the page in the middle of the view', (
    t,
  ) async {
    await pump(t);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    // Scroll by about one and a bit pages: page 2 now fills the middle even
    // though a sliver of page 1 is still at the top.
    await t.drag(find.byType(InteractiveViewer), const Offset(0, -500));
    await t.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('a single page shows no page counter', (t) async {
    await pump(t, pages: 1);
    expect(find.textContaining('Page 1 of'), findsNothing);
  });

  testWidgets(
    'after the list loads, pages are re-rendered sharper, page by page',
    (t) async {
      await pump(t);
      // First call: all pages, tiny. Then one call per page at a higher dpi.
      expect(fake.calls.first.pages, isNull);
      final thumbDpi = fake.calls.first.dpi;
      final detail = fake.calls.skip(1).toList();
      expect(detail.map((c) => c.pages), [
        [0],
        [1],
        [2],
      ]);
      expect(detail.every((c) => c.dpi > thumbDpi), isTrue);
    },
  );

  Future<void> pinchOut(WidgetTester t, double by) async {
    final c = t.getCenter(find.byType(InteractiveViewer));
    final a = await t.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await t.startGesture(c + const Offset(30, 0), pointer: 2);
    // Fingers move in small steps, as they do on a screen; one big jump is
    // read as the start of the gesture.
    const steps = 14;
    for (var i = 0; i < steps; i++) {
      await a.moveBy(Offset(-by / steps, 0));
      await b.moveBy(Offset(by / steps, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
  }

  testWidgets('pinch zooms in from the first touch', (t) async {
    await pump(t);
    expect(_scale(t), 1);
    await pinchOut(t, 50);
    expect(_scale(t), greaterThan(1.2));
  });

  testWidgets('pinch stops at the zoom limit', (t) async {
    await pump(t);
    await pinchOut(t, 140);
    expect(_scale(t), closeTo(3, 0.01));
  });

  testWidgets('double-tap zooms in, and double-tap again returns to the page', (
    t,
  ) async {
    await pump(t);
    final target = find.byType(InteractiveViewer);
    Future<void> doubleTap() async {
      await t.tap(target);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(target);
      await t.pumpAndSettle();
    }

    await doubleTap();
    expect(_scale(t), closeTo(2.5, 0.01));
    await doubleTap();
    expect(_scale(t), closeTo(1, 0.01));
  });

  testWidgets('pages are flat: a border, no shadow', (t) async {
    await pump(t);
    final boxes = t
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>();
    expect(
      boxes.any((d) => d.boxShadow != null && d.boxShadow!.isNotEmpty),
      isFalse,
    );
    expect(
      boxes.any((d) => d.border != null && d.color == const Color(0xFFFFFFFF)),
      isTrue,
    );
  });

  testWidgets(
    'a rasterizer that fails leaves a quiet empty viewer, not a crash',
    (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      fake = _Fake(await _a4(t))..fail = true;
      await t.pumpWidget(_app(D3PdfViewer(bytes: pdf, rasterizer: fake.call)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsNothing);
      // Not a mystery blank: it says the pages, not the report, failed.
      expect(find.textContaining('could not be shown'), findsOneWidget);
    },
  );
}
