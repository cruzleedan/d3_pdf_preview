import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';

/// Opens Android's print and Save-as-PDF dialog for [pdf]. For apps that offer
/// it beside Share on the preview, so nothing the system dialog gave is lost.
///
/// Set [landscape] for a PDF whose pages are landscape, so the dialog starts
/// on the right orientation instead of squeezing them onto a portrait page.
/// Returns whether the user went through with it.
Future<bool> d3PrintPdf(
  Uint8List pdf, {
  required String name,
  bool landscape = false,
}) => Printing.layoutPdf(
  name: name,
  format: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
  onLayout: (_) async => pdf,
);
