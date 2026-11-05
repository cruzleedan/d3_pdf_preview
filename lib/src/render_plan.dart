import 'dart:math' as math;

/// How much sharper than the screen to render pages for zoom, without letting
/// a long document use unbounded memory.
///
/// [basePixels] is each page's pixel count when drawn at screen resolution.
/// Rendering every page at scale `s` costs `s * s` times that, so the largest
/// scale that fits [budgetPixels] is the square root of the ratio. The result
/// is never below 1 (a document too big for the budget is still drawn at
/// screen resolution) and never above [maxScale].
double detailScaleFor({
  required Iterable<double> basePixels,
  required double budgetPixels,
  double maxScale = 2.0,
}) {
  final total = basePixels.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return 1;
  return math.sqrt(budgetPixels / total).clamp(1.0, maxScale);
}

/// The dpi that makes a page [widthPoints] wide come out [targetWidthPx] wide.
double dpiForWidth({
  required double widthPoints,
  required double targetWidthPx,
}) => targetWidthPx / (widthPoints / 72);

/// Which page is at vertical position [y] in a column of pages with the given
/// [heights] and [gap] between them. Clamped to the first and last page.
int pageIndexAt(double y, List<double> heights, double gap) {
  if (heights.isEmpty) return 0;
  var top = 0.0;
  for (var i = 0; i < heights.length; i++) {
    final bottom = top + heights[i];
    // The gap after a page belongs to that page, so the index never flickers.
    if (y < bottom + gap) return i;
    top = bottom + gap;
  }
  return heights.length - 1;
}

/// Keeps a zoomed document covering its viewport: returns the translation
/// (one axis) that stays within the content, for a content extent of [content]
/// drawn at [scale] in a viewport of [viewport].
double clampTranslation(
  double t, {
  required double scale,
  required double viewport,
  required double content,
}) {
  final min = viewport - content * scale;
  if (min >= 0) return 0; // content is smaller than the viewport: stay put
  return t.clamp(min, 0.0);
}
