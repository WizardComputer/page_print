# PDF Renderer Benchmark

This benchmark compares `page_print` with PDFKit using the same HTML input. The development bundle includes `pdfkit` and `wkhtmltopdf-binary` for repeatable local testing.

The script records wall time, CPU time, peak RSS for the renderer process tree, and output PDF size. Detailed per-run results are written to `results.csv` in the output directory.

Run the default fixture benchmark:

```sh
bundle exec ruby benchmark/pdf_renderers.rb
```

Run more iterations:

```sh
RUNS=30 WARMUPS=3 bundle exec ruby benchmark/pdf_renderers.rb
```

Use your own HTML file:

```sh
HTML=/path/to/report.html BASE_URL=https://example.com RUNS=30 bundle exec ruby benchmark/pdf_renderers.rb
```

Use it from a Rails app with a real template:

```sh
TEMPLATE=prints/pdf LAYOUT=pdf RUNS=30 bin/rails runner /path/to/page_print/benchmark/pdf_renderers.rb
```

Environment variables:

- `RENDERERS=page_print,pdfkit` selects renderers to run. Supported values are `page_print` and `pdfkit`.
- `RUNS=10` controls measured iterations per renderer.
- `WARMUPS=2` controls unreported warmup iterations per renderer.
- `HTML=benchmark/fixtures/report.html` selects an HTML file when not rendering a Rails template.
- `TEMPLATE=prints/pdf` renders a Rails template when running through `bin/rails runner`.
- `LAYOUT=pdf` selects the Rails layout for `TEMPLATE`.
- `OUTPUT_DIR=tmp/benchmarks/pdf_renderers` controls where PDFs and `results.csv` are written.
- `PAGE_SIZE=A4`, `MARGINS=normal`, and `MEDIA=print` keep renderer options aligned.
- `BASE_URL=https://example.com` resolves relative URLs for `page_print`.
- `WKHTMLTOPDF=wkhtmltopdf` selects the `wkhtmltopdf` binary used by PDFKit.

For Rails comparisons, prefer real production templates and run benchmarks on a quiet machine so CPU and memory numbers are less noisy.
