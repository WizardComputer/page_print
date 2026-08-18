# PagePrint

Fast, in-process HTML-to-PDF rendering for Ruby, powered by [PlutoBook](https://github.com/plutoprint/plutobook).

> [!IMPORTANT]
> PagePrint is still pre-1.0 and is not yet recommended as a drop-in production dependency without application-specific testing. Native packaging and platform compatibility are still being validated. See the [production guide](docs/production.md) before deploying it.

PagePrint turns an HTML string into PDF bytes—or writes it directly to a file—through a small native C extension. It is designed for server-generated documents such as invoices, reports, labels, and statements where the HTML is known in advance and does not depend on JavaScript.


## Why PagePrint?

PDFKit and Wicked PDF render documents by launching the `wkhtmltopdf` executable. PagePrint instead embeds a purpose-built paged-media renderer in the Ruby process.

That gives PagePrint a few useful properties:

- **No renderer subprocess:** no executable discovery, shelling out, or process startup per render.
- **A small Ruby API:** pass HTML in and receive PDF bytes, or write directly to a path.
- **Print-oriented CSS:** PlutoBook supports paged-media features such as `@page`, page counters, and running headers and footers.
- **Controlled resource loading:** PagePrint does not fetch unresolved HTTP URLs. Your application decides which stylesheets, images, and fonts may be loaded.
- **Rails asset integration:** Propshaft and `public/assets` resources work without HTTP requests back into the application.

### How does it compare with PDFKit and Wicked PDF?

PDFKit and Wicked PDF are Ruby integrations for `wkhtmltopdf`; their rendering behavior and operational requirements come from that executable.

| | PagePrint / PlutoBook | PDFKit or Wicked PDF / `wkhtmltopdf` |
| --- | --- | --- |
| Runtime model | Native library in the Ruby process | External `wkhtmltopdf` executable |
| Rendering engine | Purpose-built for static documents and CSS paged media | Legacy Qt WebKit browser engine |
| JavaScript | Not supported | Supported by legacy Qt WebKit |
| Network access | Denied unless your fetcher supplies the resource | Built in |
| CSS compatibility | Print-focused and partial; no CSS Grid | Limited by the old WebKit engine |
| Operational footprint | Native gem and bundled libraries on supported platforms | `wkhtmltopdf` binary plus Qt/WebKit dependencies |
| Upstream status | PagePrint currently packages PlutoBook 0.19.0 | `wkhtmltopdf` was archived in 2023 |

PagePrint is a strong fit when you control the templates, value predictable print layout, and do not need JavaScript. Stay with a `wkhtmltopdf`-based gem if your existing templates depend on its JavaScript or WebKit-specific rendering behavior. When migrating, compare representative output carefully because changing engines can alter pagination, fonts, and layout.

The `wkhtmltopdf` project was [archived in 2023](https://github.com/wkhtmltopdf/wkhtmltopdf) and its own [status document](https://github.com/wkhtmltopdf/wkhtmltopdf/blob/master/docs/status.md) describes its Qt 4 / WebKit stack as unsupported and outdated. PlutoBook is purpose-built for static paged output, but has a narrower feature set; review its [feature matrix](https://github.com/plutoprint/plutobook/blob/main/FEATURES.md) before migrating a complex template.

## Installation

Add the gem to your `Gemfile`:

```ruby
gem "page_print"
```

Then run:

```sh
bundle install
```

PagePrint requires Ruby 3.2 or newer. Native gems with vendored PlutoBook libraries are published for:

- `x86_64-linux`
- `arm64-darwin` (Apple Silicon)

Other platforms build from source and require PlutoBook development headers and libraries. See [Installing on other platforms](docs/production.md#installing-on-other-platforms).

## Quick start

Require PagePrint and render an HTML string:

```ruby
require "page_print"

html = <<~HTML
  <!doctype html>
  <html>
    <head>
      <meta charset="utf-8">
      <style>
        @page {
          size: A4;

          @bottom-center {
            content: counter(page) " / " counter(pages);
            color: #666;
            font-size: 10pt;
          }
        }

        body { font-family: sans-serif; }
      </style>
    </head>
    <body>
      <h1>Invoice #1042</h1>
      <p>Thank you for your business.</p>
    </body>
  </html>
HTML

pdf = PagePrint.render(html, page_size: :a4, margins: :normal)
```

For large documents, write directly to a file instead of retaining the PDF in a Ruby string:

```ruby
PagePrint.render_to_file(html, "invoice.pdf", page_size: :a4, margins: :normal)
```

`render_to_file` returns `true`; `render` returns an `ASCII-8BIT` Ruby string containing the PDF.

## Rails

PagePrint integrates automatically with Rails applications that use Propshaft. Render a template to HTML, pass it to PagePrint, then send the resulting bytes:

```ruby
class InvoicesController < ApplicationController
  def show
    html = render_to_string(template: "invoices/show", formats: [:html], layout: "pdf")
    pdf = PagePrint.render(html, page_size: :a4, margins: :normal, metadata: { title: "Invoice ##{params[:id]}", author: "Example Ltd" })

    send_data pdf, filename: "invoice-#{params[:id]}.pdf", type: "application/pdf", disposition: "inline"
  end
end
```

Normal asset helpers can be used in the PDF template:

```erb
<%= stylesheet_link_tag "pdf" %>
<%= image_tag "logo.png", alt: "Example Ltd" %>
```

During a controller action, PagePrint uses `request.base_url` to resolve relative URLs. Its Rails resource fetcher reads `/assets/...` from Propshaft or `public/assets`; it does not make an HTTP request back to Rails.

## Assets and network access

PagePrint intentionally does not download unresolved resources. Supply a `resource_fetcher` when non-Rails HTML needs external styles, images, or fonts:

```ruby
assets = {
  "asset:pdf.css" => {
    content: File.binread("app/assets/stylesheets/pdf.css"),
    mime_type: "text/css"
  }
}

pdf = PagePrint.render(
  "<link rel=\"stylesheet\" href=\"asset:pdf.css\"><h1>Report</h1>",
  resource_fetcher: ->(url) { assets[url] }
)
```

The fetcher receives each resolved URL and returns `{ content:, mime_type: }` or `nil`. Returning `nil` skips the resource. This makes resource access explicit, but it does not make untrusted HTML safe; see [Security](docs/production.md#security).

## Configuration

The common rendering options are:

```ruby
PagePrint.render(
  html,
  base_url: "https://example.test",
  page_size: :letter,
  margins: :narrow,
  media: :print,
  metadata: { title: "Quarterly report" },
  resource_fetcher: fetcher
)
```

Defaults are A4 paper, normal margins, and print media. See the [configuration reference](docs/configuration.md) for every preset, custom dimensions, metadata fields, global configuration, and resource fetcher behavior.

## Performance

The repository includes a reproducible benchmark against PDFKit using the same static HTML input. On May 30, 2026, the recorded run used Ruby 3.4.7 on an Apple Silicon development machine:

| Renderer | Average wall time | P95 wall time | Average peak RSS |
| --- | ---: | ---: | ---: |
| PagePrint | 78.2 ms | 89.6 ms | 42.1 MB |
| PDFKit | 782.2 ms | 2,127.1 ms | 59.4 MB |

These numbers are illustrative, not a capacity guarantee. Rendering cost varies significantly with fonts, images, document length, and host configuration. Run the benchmark—or your own production templates—on the deployment target before sizing infrastructure.

```sh
RUNS=30 WARMUPS=3 bundle exec ruby benchmark/pdf_renderers.rb
```

See [benchmark/README.md](benchmark/README.md) for methodology and CSV output.

## Documentation

- [Configuration and API reference](docs/configuration.md)
- [Production guide](docs/production.md)
- [Benchmark methodology](benchmark/README.md)
- [PlutoBook feature matrix](https://github.com/plutoprint/plutobook/blob/main/FEATURES.md)

## Development

Install dependencies, compile the extension, and run the test suite:

```sh
bundle install
bundle exec rake
```

Use `bin/console` for an IRB session with the extension compiled and PagePrint loaded.

## License

PagePrint is available under the [MIT License](LICENSE).
