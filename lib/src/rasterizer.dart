import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:printing/printing.dart';

/// Turns a PDF into page images, in page order.
///
/// [dpi] is dots per inch of the page (a PDF page is measured in points, 72 to
/// the inch, so `dpi: 72` gives one pixel per point). [pages] limits the
/// output to those zero-based page numbers.
///
/// This is a seam so zoom and layout can be tested without a platform: tests
/// pass a function that returns plain images. Callers own the images they
/// receive and dispose them.
typedef D3PdfRasterizer = Stream<ui.Image> Function(
  Uint8List pdf, {
  required double dpi,
  List<int>? pages,
});

/// The default rasterizer, over `package:printing`.
Stream<ui.Image> printingRasterizer(
  Uint8List pdf, {
  required double dpi,
  List<int>? pages,
}) async* {
  await for (final raster in Printing.raster(pdf, pages: pages, dpi: dpi)) {
    yield await raster.toImage();
  }
}
