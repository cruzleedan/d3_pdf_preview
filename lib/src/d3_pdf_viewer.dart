import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:d3_ui/d3_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'rasterizer.dart';
import 'render_plan.dart';

/// The pages of a PDF in a column that you scroll by dragging and zoom by
/// pinching or double-tapping.
///
/// Pages are drawn at screen resolution first, then re-rendered sharper (up to
/// [maxDetailScale] times, within [pixelBudget]) so a zoomed page stays
/// readable. A page is white paper with a thin border, never a shadow.
///
/// Pinch works from the first touch; there is no mode to enter. Double-tap
/// zooms to [doubleTapScale] about the tapped point, and double-tap again
/// returns to the whole page.
class D3PdfViewer extends StatefulWidget {
  const D3PdfViewer({
    super.key,
    required this.bytes,
    this.rasterizer = printingRasterizer,
    this.maxScale = 3,
    this.doubleTapScale = 2.5,
    this.maxDetailScale = 2,
    this.pixelBudget = 32e6,
    this.padding = const EdgeInsets.all(D3Spacing.s16),
    this.backgroundColor,
  });

  /// The PDF.
  final Uint8List bytes;

  /// Renders pages to images; replace in tests.
  final D3PdfRasterizer rasterizer;

  /// The furthest the user can zoom.
  final double maxScale;

  /// Where a double-tap zooms to.
  final double doubleTapScale;

  /// The most the render scale is raised above screen resolution.
  final double maxDetailScale;

  /// A cap on the pixels held for all pages at once (about 4 bytes each).
  final double pixelBudget;

  /// Space around the column of pages.
  final EdgeInsets padding;

  /// Behind the pages; defaults to the theme's raised surface.
  final Color? backgroundColor;

  @override
  State<D3PdfViewer> createState() => _D3PdfViewerState();
}

class _Slot {
  _Slot({required this.aspect, required this.widthPoints, required this.thumb});

  /// Width over height.
  final double aspect;
  final double widthPoints;
  ui.Image? thumb;
  ui.Image? full;

  ui.Image? get image => full ?? thumb;

  void dispose() {
    thumb?.dispose();
    full?.dispose();
    thumb = null;
    full = null;
  }
}

class _D3PdfViewerState extends State<D3PdfViewer>
    with SingleTickerProviderStateMixin {
  static const _thumbDpi = 12.0;
  static const _gap = D3Spacing.s12;

  final _controller = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: D3Motion.base,
  );
  final _page = ValueNotifier<int>(0);

  List<_Slot> _slots = [];
  bool _listed = false;
  bool _failed = false;
  int _generation = 0;
  int _detailGeneration = 0;
  double? _detailForWidthPx;
  Offset _doubleTapAt = Offset.zero;
  Size _viewport = Size.zero;
  double _contentHeight = 0;
  List<double> _pageHeights = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
    _zoomAnim.addListener(_onZoomTick);
    _load();
  }

  @override
  void didUpdateWidget(D3PdfViewer old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _controller.value = Matrix4.identity();
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _detailGeneration++;
    _controller
      ..removeListener(_onTransform)
      ..dispose();
    _zoomAnim
      ..removeListener(_onZoomTick)
      ..dispose();
    _page.dispose();
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  // ---- loading -----------------------------------------------------------

  Future<void> _load() async {
    final generation = ++_generation;
    _detailGeneration++;
    for (final s in _slots) {
      s.dispose();
    }
    setState(() {
      _slots = [];
      _listed = false;
      _failed = false;
      _detailForWidthPx = null;
    });
    final slots = <_Slot>[];
    try {
      // A quick, tiny pass to learn how many pages there are and their shape,
      // so the column is laid out at once and fills in as pages sharpen.
      await for (final image in widget.rasterizer(
        widget.bytes,
        dpi: _thumbDpi,
      )) {
        if (!mounted || generation != _generation) {
          image.dispose();
          return;
        }
        slots.add(
          _Slot(
            aspect: image.width / image.height,
            widthPoints: image.width * 72 / _thumbDpi,
            thumb: image,
          ),
        );
        setState(() => _slots = List.of(slots));
      }
      if (!mounted || generation != _generation) return;
      setState(() => _listed = true);
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _listed = true;
      });
    }
  }

  Future<void> _renderDetail(double widthPx) async {
    final generation = ++_detailGeneration;
    final slots = List.of(_slots);
    final scale = detailScaleFor(
      basePixels: [for (final s in slots) widthPx * widthPx / s.aspect],
      budgetPixels: widget.pixelBudget,
      maxScale: widget.maxDetailScale,
    );
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final dpi = dpiForWidth(
        widthPoints: slot.widthPoints,
        targetWidthPx: widthPx * scale,
      );
      try {
        await for (final image in widget.rasterizer(
          widget.bytes,
          dpi: dpi,
          pages: [i],
        )) {
          if (!mounted || generation != _detailGeneration) {
            image.dispose();
            return;
          }
          setState(() {
            slot.full?.dispose();
            slot.full = image;
            slot.thumb?.dispose();
            slot.thumb = null;
          });
        }
      } on Object {
        // Keep the screen-resolution page if a sharper one cannot be made.
        return;
      }
    }
  }

  // ---- zoom --------------------------------------------------------------

  void _onTransform() {
    if (_pageHeights.isEmpty) return;
    final m = _controller.value;
    final scale = m.getMaxScaleOnAxis();
    final top = -m.getTranslation().y / scale - widget.padding.top;
    _page.value = pageIndexAt(top, _pageHeights, _gap);
  }

  // Interpolated state of an in-flight double-tap zoom: (scale, tx, ty).
  (double, double, double) _zoomFrom = (1, 0, 0);
  (double, double, double) _zoomTo = (1, 0, 0);

  void _applyZoom((double, double, double) v) {
    _controller.value = Matrix4(
      v.$1,
      0,
      0,
      0, //
      0,
      v.$1,
      0,
      0,
      0,
      0,
      1,
      0,
      v.$2,
      v.$3,
      0,
      1,
    );
  }

  void _onZoomTick() {
    final t = D3Motion.standard.transform(_zoomAnim.value);
    _applyZoom((
      _zoomFrom.$1 + (_zoomTo.$1 - _zoomFrom.$1) * t,
      _zoomFrom.$2 + (_zoomTo.$2 - _zoomFrom.$2) * t,
      _zoomFrom.$3 + (_zoomTo.$3 - _zoomFrom.$3) * t,
    ));
  }

  void _toggleZoom() {
    final m = _controller.value;
    final from = m.getMaxScaleOnAxis();
    final to = from > 1.05
        ? 1.0
        : widget.doubleTapScale.clamp(1.0, widget.maxScale);
    final focal = _doubleTapAt;
    final t0 = m.getTranslation();
    // The content point under the finger stays under the finger.
    final cx = (focal.dx - t0.x) / from;
    final cy = (focal.dy - t0.y) / from;
    final tx = clampTranslation(
      focal.dx - cx * to,
      scale: to,
      viewport: _viewport.width,
      content: _viewport.width,
    );
    final ty = clampTranslation(
      focal.dy - cy * to,
      scale: to,
      viewport: _viewport.height,
      content: _contentHeight,
    );
    _zoomFrom = (from, t0.x, t0.y);
    _zoomTo = (to, tx, ty);
    if (MediaQuery.disableAnimationsOf(context)) {
      _applyZoom(_zoomTo);
      return;
    }
    _zoomAnim.forward(from: 0);
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.d3Colors;
    final background = widget.backgroundColor ?? colors.surfaceContainer;

    if (_failed) {
      return ColoredBox(color: background, child: const SizedBox.expand());
    }
    if (_slots.isEmpty) {
      return ColoredBox(
        color: background,
        child: Center(
          child: _listed
              ? const SizedBox.shrink()
              : const CircularProgressIndicator(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final pageWidth = viewport.width - widget.padding.horizontal;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final heights = [for (final s in _slots) pageWidth / s.aspect];
        _viewport = viewport;
        _pageHeights = heights;
        _contentHeight =
            widget.padding.vertical +
            heights.fold<double>(0, (a, b) => a + b) +
            _gap * (heights.length - 1);

        // Sharpen once the page list is known, and again if the width changes
        // (rotation, split screen).
        final widthPx = pageWidth * dpr;
        if (_listed && !_failed && _detailForWidthPx != widthPx) {
          _detailForWidthPx = widthPx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _detailForWidthPx == widthPx) _renderDetail(widthPx);
          });
        }

        return ColoredBox(
          color: background,
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                onDoubleTap: _toggleZoom,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1,
                  maxScale: widget.maxScale,
                  constrained: false,
                  child: SizedBox(
                    width: viewport.width,
                    child: Padding(
                      padding: widget.padding,
                      child: Column(
                        children: [
                          for (var i = 0; i < _slots.length; i++) ...[
                            if (i > 0) const SizedBox(height: _gap),
                            _PageView(
                              slot: _slots[i],
                              index: i,
                              count: _slots.length,
                              width: pageWidth,
                              borderColor: colors.outlineVariant,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_slots.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: D3Spacing.s12,
                  child: IgnorePointer(
                    child: Center(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _page,
                        builder: (context, page, _) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(D3Radius.full),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: D3Spacing.s12,
                              vertical: D3Spacing.s4,
                            ),
                            child: Text(
                              'Page ${page + 1} of ${_slots.length}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: colors.onSurface),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({
    required this.slot,
    required this.index,
    required this.count,
    required this.width,
    required this.borderColor,
  });

  final _Slot slot;
  final int index;
  final int count;
  final double width;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final image = slot.image;
    return Semantics(
      container: true,
      image: true,
      label: count == 1 ? 'Page' : 'Page ${index + 1} of $count',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: borderColor),
        ),
        child: SizedBox(
          width: width,
          height: width / slot.aspect,
          child: image == null
              ? null
              : RawImage(
                  image: image,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      ),
    );
  }
}
