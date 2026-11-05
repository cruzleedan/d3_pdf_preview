import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Opens Android's print and Save-as-PDF dialog for [pdf]. For apps that offer
/// it beside Share on the preview, so nothing the system dialog gave is lost.
/// Returns whether the user went through with it.
Future<bool> d3PrintPdf(Uint8List pdf, {required String name}) =>
    Printing.layoutPdf(name: name, onLayout: (_) async => pdf);
