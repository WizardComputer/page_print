# Production guide

PagePrint is pre-1.0 software. Treat adoption as an application-specific engineering decision: validate the native package, representative documents, throughput, memory use, fonts, and failure behavior on the same platform used in production.

## Production readiness checklist

Before deploying PagePrint:

- [ ] Confirm the deployment platform has a native gem or can build PlutoBook from source.
- [ ] Render representative short, long, image-heavy, and multilingual documents in CI.
- [ ] Visually compare pagination, fonts, images, headers, and footers against approved fixtures.
- [ ] Verify every stylesheet, image, and font is available through the Rails integration or an allowlisted resource fetcher.
- [ ] Confirm templates do not depend on JavaScript, CSS Grid, or other unsupported browser features.
- [ ] Load-test with production-sized documents and the same worker/thread configuration used in deployment.
- [ ] Set application-level job timeouts and monitor render latency, failures, and output size.
- [ ] Prefer `render_to_file` for large PDFs, and clean up temporary output in both success and failure paths.
- [ ] Pin the gem version and test upgrades before rollout; renderer upgrades can alter layout and pagination.

## Platform support

PagePrint requires Ruby 3.2 or newer.

| Platform | Installation |
| --- | --- |
| `x86_64-linux` | Native gem with vendored PlutoBook libraries; the Ruby extension is compiled against the local Ruby |
| `arm64-darwin` | Native gem with vendored PlutoBook libraries; the Ruby extension is compiled against the local Ruby |
| Other platforms | Source build using an installed PlutoBook |

The published native gems disable PlutoBook's optional curl, TurboJPEG, and WebP features to keep the bundled dependency set smaller. PagePrint uses its own Ruby resource fetcher boundary and does not expose PlutoBook's optional network fetcher.

Your production image still needs a compiler and Ruby development headers because the small PagePrint extension is compiled during installation.

### Installing on other platforms

Install PlutoBook development headers and libraries before installing the gem. On macOS with Homebrew:

```sh
brew install plutobook pkg-config
bundle install
```

If `pkg-config` cannot find PlutoBook, provide explicit paths:

```sh
gem install page_print -- \
  --with-plutobook-include=/path/to/include \
  --with-plutobook-lib=/path/to/lib
```

Use equivalent Bundler build configuration in repeatable deployments:

```sh
bundle config set --local build.page_print \
  "--with-plutobook-include=/path/to/include --with-plutobook-lib=/path/to/lib"
bundle install
```

Run a render smoke test while building the deployment artifact, rather than only checking that the gem can be required:

```sh
bundle exec ruby -e '
  require "page_print"
  pdf = PagePrint.render("<h1>Deployment check</h1>")
  abort "invalid PDF" unless pdf.start_with?("%PDF")
'
```

## Security

PagePrint's resource policy is deny-by-default: an unresolved URL is not fetched over the network. Preserve that property in custom fetchers.

- Do not build a fetcher that blindly downloads arbitrary URLs. Doing so can introduce server-side request forgery (SSRF), access to cloud metadata endpoints, and unbounded downloads.
- Prefer a fixed asset map, an application-owned URI scheme, or strict allowlists for scheme, host, path, content type, and size.
- Do not treat PagePrint as a sandbox for hostile HTML. It parses complex input in native code and should run with the minimum filesystem and process permissions needed by the application.
- Never place secrets in HTML, asset URLs, metadata, or error logs.
- Validate and limit user-controlled content before inserting it into a trusted template.

PagePrint's disabled network fallback improves predictability and reduces accidental outbound access, but it is not a complete security boundary.

## Template compatibility

PagePrint is intended for static, server-rendered documents. It does not execute JavaScript. PlutoBook supports much of CSS 3 and selected CSS 4 functionality, but important gaps include CSS Grid and some advanced visual features.

Before migrating from PDFKit, `wkhtmltopdf`, or a browser renderer:

1. Inventory JavaScript, layout modules, fonts, SVG, and remote assets used by the templates.
2. Check the [PlutoBook feature matrix](https://github.com/plutoprint/plutobook/blob/main/FEATURES.md).
3. Render a fixture set with both engines.
4. Compare page breaks and visual output, not only whether a PDF was produced.

Use explicit `@page`, print styles, and embedded or controlled fonts. Font substitution is a common cause of different line wrapping and pagination across development and production.

## Assets and networking

For deterministic output, package document assets with the application and return them from a resource fetcher. Avoid making rendering depend on the availability or latency of another service.

Rails applications using Propshaft get a default fetcher for `/assets/...`. Outside Rails, configure a fetcher once at process startup:

```ruby
PagePrint.configure do |config|
  config.resource_fetcher = ProductionPdfAssets.new
end
```

See the [resource fetcher reference](configuration.md#resource-fetchers) for the callable contract.

## Capacity and concurrency

HTML parsing, layout, and PDF writing are native CPU- and memory-intensive work. The extension releases Ruby's Global VM Lock during PlutoBook loading and writing, but Ruby callbacks such as a custom resource fetcher run with the lock.

Do not size workers from the repository benchmark alone. Measure:

- latency percentiles, not only averages;
- peak resident memory with concurrent renders;
- the largest realistic HTML, image, and PDF sizes;
- application behavior when a render raises or a job times out;
- both `render` and `render_to_file` if you expect large outputs.

Use bounded job concurrency. For background processing, let the job system retry only failures known to be transient; invalid templates and unsupported resources will fail repeatedly.

## Failure handling

PagePrint validates option types and raises Ruby exceptions for invalid input, resource fetcher failures, HTML loading failures, and PDF write failures. Treat a successful method return—and, where appropriate, a `%PDF` signature and non-zero output size—as the completion signal.

When writing temporary files:

```ruby
require "tempfile"

Tempfile.create(["invoice", ".pdf"]) do |file|
  PagePrint.render_to_file(html, file.path)
  deliver(file.path)
end
```

Do not expose native error text directly to end users. Record enough context to identify the template and render options, without logging document contents that may contain personal or confidential data.

## Upgrade strategy

Pin PagePrint in the application lockfile. Before upgrading PagePrint or PlutoBook:

1. Build on every production platform.
2. Run the complete PDF fixture suite.
3. Compare visual output and page count.
4. Repeat a focused load test.
5. Roll out gradually while watching latency and render failures.

[Back to the README](../README.md)
