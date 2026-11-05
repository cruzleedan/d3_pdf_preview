import 'dart:typed_data';

import 'package:d3_ui/d3_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'd3_pdf_viewer.dart';
import 'rasterizer.dart';

String _sizeLabel(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).round()} KB';

/// A full-screen preview of a generated PDF: the pages, zoomable, with a line
/// above them saying what is in the document and how big it is, and room below
/// for the app's own actions (Save, Share, Print).
///
/// The app builds the PDF and decides what the buttons do; this screen owns the
/// look, the loading and error states and the zoom. [bytes] resolves to the
/// PDF, and the screen shows progress until it does.
class D3PdfPreviewScreen extends StatelessWidget {
  const D3PdfPreviewScreen({
    super.key,
    required this.title,
    required this.bytes,
    this.summaryLines = const [],
    this.bottomBuilder,
    this.infoTitle = 'Preview',
    this.infoMessage,
    this.leading,
    this.errorTitle = 'Could not build the report',
    this.errorMessage = 'Nothing was saved. Go back and try again.',
    this.rasterizer = printingRasterizer,
  });

  final String title;

  /// Resolves to the PDF.
  final Future<Uint8List> bytes;

  /// What the document holds, for example "Nov 1 to Nov 30 · 7 visits". Joined
  /// with the file size once the PDF exists.
  final List<String> summaryLines;

  /// The app's actions under the pages. Gets the PDF once it exists, and null
  /// before, so buttons can be disabled while it builds.
  final Widget Function(BuildContext context, Uint8List? pdf)? bottomBuilder;

  /// Text for the (i) sheet; when null there is no (i) button.
  final String? infoMessage;
  final String infoTitle;

  /// The title bar's leading control; null keeps the default (a back arrow).
  final D3ScreenLeading? leading;

  final String errorTitle;
  final String errorMessage;

  final D3PdfRasterizer rasterizer;

  @override
  Widget build(BuildContext context) {
    final colors = context.d3Colors;
    final textTheme = Theme.of(context).textTheme;

    return D3Screen(
      title: title,
      leading: leading,
      actions: [
        if (infoMessage != null)
          D3ScreenAction.widget(
            D3InfoButton(title: infoTitle, message: infoMessage!),
          ),
      ],
      body: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return D3EmptyState(
              icon: Icons.error_outline,
              iconColor: colors.error,
              title: errorTitle,
              message: errorMessage,
              action: D3Button(
                label: 'Go back',
                variant: D3ButtonVariant.tonal,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            );
          }
          final data = snapshot.data;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  D3Spacing.s16,
                  D3Spacing.s8,
                  D3Spacing.s16,
                  D3Spacing.s8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          ...summaryLines,
                          if (data != null) _sizeLabel(data.length),
                        ].join(' · '),
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (data != null) ...[
                        const SizedBox(height: D3Spacing.s4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_in,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: D3Spacing.s4),
                            // Flexible so it wraps at a large text size instead of
                            // overflowing a narrow screen.
                            Flexible(
                              child: Text(
                                'Pinch or double-tap to zoom',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: data == null
                    ? const Center(child: CircularProgressIndicator())
                    : D3PdfViewer(bytes: data, rasterizer: rasterizer),
              ),
              if (bottomBuilder != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(D3Spacing.s16),
                    child: bottomBuilder!(context, data),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
