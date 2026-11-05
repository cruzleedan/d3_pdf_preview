# d3_pdf_preview

An in-app preview for a generated PDF, in the d3 look: flat pages, a line
saying what the document holds, zoom that stays sharp, and room for your own
actions (Save, Share, Print).

It exists so every d3 app previews a PDF the same way, instead of each one
choosing between its own screen and Android's print dialog.

## What you get

- **`D3PdfPreviewScreen`**: the whole screen. You give it a title, summary
  lines and a `Future<Uint8List>`; it shows progress, the pages, and an error
  state. You supply the buttons.
- **`D3PdfViewer`**: just the pages, if you want your own screen.
- **`d3PrintPdf`**: Android's print and Save-as-PDF dialog, as an action to
  offer next to Share.

Building the PDF, saving it and sharing it stay in your app.

## Using it

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => D3PdfPreviewScreen(
      title: 'Visit log',
      summaryLines: const ['Nov 1 to Nov 30', '7 visits'],
      bytes: buildPdf(), // Future<Uint8List>
      infoMessage: 'This is what the PDF will contain.',
      bottomBuilder: (context, pdf) => D3Button(
        label: 'Share',
        isFullWidth: true,
        onPressed: pdf == null ? null : () => share(pdf),
      ),
    ),
  ),
);
```

`bottomBuilder` gets `null` until the PDF exists, so buttons can stay disabled
while it builds.

## Zoom

Pinch works from the first touch (up to 3x) and double-tap zooms in and out. A
page is drawn at screen resolution first, then re-rendered sharper so a zoomed
page stays readable. How much sharper is limited by a pixel budget
(`pixelBudget`, default 32 million pixels across all pages), so a long
document cannot use unbounded memory; past the budget pages stay at screen
resolution.

Page images come from `package:printing`. Pass your own `rasterizer` to
`D3PdfViewer` to test without a platform.

## Setup

```yaml
dependencies:
  d3_pdf_preview:
    git:
      url: https://github.com/cruzleedan/d3_pdf_preview.git
      ref: main
```

It needs `d3_ui` and `package:printing` (Android print service and PDF
rendering, so a native plugin).
