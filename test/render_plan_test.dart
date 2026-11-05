import 'package:d3_pdf_preview/d3_pdf_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detailScaleFor', () {
    test('a short document is rendered at the full detail scale', () {
      // Two pages of 1.6 MP at 1x: 2x costs 12.8 MP, well under 32 MP.
      expect(
        detailScaleFor(basePixels: [1.6e6, 1.6e6], budgetPixels: 32e6),
        2.0,
      );
    });

    test(
      'a long document gets a lower scale, never below screen resolution',
      () {
        final five = detailScaleFor(
          basePixels: List.filled(5, 1.6e6),
          budgetPixels: 32e6,
        );
        expect(five, closeTo(2.0, 0.001)); // 5 x 1.6 MP x 4 = 32 MP exactly
        final ten = detailScaleFor(
          basePixels: List.filled(10, 1.6e6),
          budgetPixels: 32e6,
        );
        expect(ten, closeTo(1.414, 0.01));
        final huge = detailScaleFor(
          basePixels: List.filled(100, 1.6e6),
          budgetPixels: 32e6,
        );
        expect(huge, 1.0);
      },
    );

    test('the result stays within the stated memory budget', () {
      for (final pages in [1, 3, 8, 20, 60]) {
        final bases = List.filled(pages, 1.6e6);
        final s = detailScaleFor(basePixels: bases, budgetPixels: 32e6);
        final cost = bases.fold<double>(0, (a, b) => a + b) * s * s;
        // Over budget only when even 1x is (a document too big to help).
        expect(
          cost <= 32e6 * 1.0001 || s == 1.0,
          isTrue,
          reason: '$pages pages',
        );
      }
    });

    test('no pages means no scaling', () {
      expect(detailScaleFor(basePixels: [], budgetPixels: 32e6), 1.0);
    });
  });

  test('dpiForWidth makes an A4 page come out the requested width', () {
    // A4 is 595 points wide: 72 dpi gives 595 px; 1190 px needs 144 dpi.
    expect(
      dpiForWidth(widthPoints: 595, targetWidthPx: 595),
      closeTo(72, 0.001),
    );
    expect(
      dpiForWidth(widthPoints: 595, targetWidthPx: 1190),
      closeTo(144, 0.001),
    );
  });

  group('pageIndexAt', () {
    const heights = [100.0, 100.0, 100.0];
    test('finds the page at a position', () {
      expect(pageIndexAt(0, heights, 10), 0);
      expect(pageIndexAt(99, heights, 10), 0);
      expect(pageIndexAt(115, heights, 10), 1);
      expect(pageIndexAt(235, heights, 10), 2);
    });
    test('clamps outside the column', () {
      expect(pageIndexAt(-50, heights, 10), 0);
      expect(pageIndexAt(5000, heights, 10), 2);
      expect(pageIndexAt(10, const [], 10), 0);
    });
  });

  group('clampTranslation', () {
    test('keeps a zoomed document covering the viewport', () {
      // 300 wide content at 2x in a 300 viewport can shift by at most -300.
      expect(clampTranslation(50, scale: 2, viewport: 300, content: 300), 0);
      expect(
        clampTranslation(-500, scale: 2, viewport: 300, content: 300),
        -300,
      );
      expect(
        clampTranslation(-120, scale: 2, viewport: 300, content: 300),
        -120,
      );
    });
    test('content smaller than the viewport does not move', () {
      expect(clampTranslation(-40, scale: 1, viewport: 600, content: 300), 0);
    });
  });
}
