## 0.1.0

Initial release. Extracted from Site Inspector's report preview so Site
Inspector and Snore Tracker preview a PDF the same way.

* `D3PdfPreviewScreen`, `D3PdfViewer` and `d3PrintPdf`.
* Pages are flat (a border, no shadow). Pinch zooms from the first touch,
  double-tap zooms in and out, and zoomed pages are re-rendered sharper within
  a memory budget.
