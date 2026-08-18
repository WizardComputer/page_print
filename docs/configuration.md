# Configuration and API reference

PagePrint exposes two rendering methods and a small set of keyword options.

## Rendering methods

### `PagePrint.render(html, **options)`

Renders a non-empty HTML string and returns the PDF as an `ASCII-8BIT` Ruby string.

```ruby
pdf = PagePrint.render("<h1>Report</h1>")
```

### `PagePrint.render_to_file(html, path, **options)`

Renders a non-empty HTML string directly to `path` and returns `true`. The destination directory must already exist and be writable.

```ruby
PagePrint.render_to_file("<h1>Report</h1>", "/tmp/report.pdf")
```

Writing directly to a file avoids keeping the finished PDF in a Ruby string and is preferable for large documents or background jobs.

## Options

Both rendering methods accept the same options.

| Option | Default | Accepted values |
| --- | --- | --- |
| `base_url:` | `nil` outside Rails | A string or `nil` |
| `page_size:` | `:a4` | A page preset or custom dimensions |
| `margins:` | `:normal` | A margin preset or custom dimensions |
| `media:` | `:print` | `:print` or `:screen` |
| `resource_fetcher:` | Configured global fetcher or `nil` | Any callable, `nil`, or `false` |
| `metadata:` | `nil` | A metadata hash or `nil` |

Unknown options raise `ArgumentError`; values of the wrong type raise `TypeError`.

### Base URL

`base_url` resolves relative URLs found in the HTML:

```ruby
html = '<link rel="stylesheet" href="/assets/report.css"><h1>Report</h1>'
PagePrint.render(html, base_url: "https://example.test", resource_fetcher: fetcher)
```

The fetcher receives `https://example.test/assets/report.css`. A base URL resolves the URL; it does not enable network access.

Set an application-wide default when rendering outside Rails:

```ruby
PagePrint.configure do |config|
  config.base_url = "https://example.test"
end
```

An explicit `base_url:` takes precedence over the configured value.

### Page size

Available presets:

```text
:a3  :a4  :a5  :b4  :b5  :letter  :legal  :ledger
```

Custom dimensions require a width, height, and unit:

```ruby
PagePrint.render(
  html,
  page_size: { width: 100, height: 150, unit: :mm }
)
```

Width and height must be greater than zero.

### Margins

Available presets:

```text
:none  :normal  :narrow  :moderate  :wide
```

Custom margins require all four sides and a unit:

```ruby
PagePrint.render(
  html,
  margins: { top: 5, right: 6, bottom: 7, left: 8, unit: :mm }
)
```

Margin values must be zero or greater.

Page sizes and margins support these units:

```text
:pt  :pc  :in  :cm  :mm  :px
```

### Media type

Use `:print` to apply print styles and `:screen` to apply screen styles:

```ruby
PagePrint.render(html, media: :screen)
```

### PDF metadata

Metadata keys and values must be symbols and strings, respectively. A value may also be `nil`.

```ruby
PagePrint.render(
  html,
  metadata: {
    title: "Quarterly report",
    author: "Example Ltd",
    subject: "Q2 results",
    keywords: "finance,quarterly",
    creation_date: "2026-05-10T12:00:00Z",
    modification_date: nil
  }
)
```

Supported keys are:

- `:title`
- `:author`
- `:subject`
- `:keywords`
- `:creation_date`
- `:modification_date`

Use ISO 8601 strings for creation and modification dates.

## Resource fetchers

A resource fetcher is a callable that receives a resolved URL. It must return either `nil` or a hash containing binary `content` and its `mime_type`. `text_encoding` is optional.

```ruby
fetcher = lambda do |url|
  case url
  when "asset:report.css"
    {
      content: File.binread("app/assets/stylesheets/report.css"),
      mime_type: "text/css",
      text_encoding: "utf-8"
    }
  when "asset:logo.png"
    {
      content: File.binread("app/assets/images/logo.png"),
      mime_type: "image/png"
    }
  end
end

PagePrint.render(html, resource_fetcher: fetcher)
```

Returning `nil` skips the URL. PagePrint does not fall back to an HTTP request. Exceptions raised by the fetcher are propagated to the caller.

Configure a default fetcher for every render:

```ruby
PagePrint.configure do |config|
  config.resource_fetcher = MyResourceFetcher.new
end
```

Pass `resource_fetcher: false` or `nil` to disable a configured fetcher for one render.

Keep fetchers narrowly scoped. Prefer an allowlist or a fixed asset map over fetching arbitrary URLs supplied by HTML.

## Rails behavior

When Rails is loaded, PagePrint installs two defaults:

1. During controller actions, the current `request.base_url` becomes the default base URL for that request.
2. `PagePrint::RailsResourceFetcher` resolves URLs under `/assets/` from `public/assets` or Propshaft.

An explicit `base_url:` or `resource_fetcher:` still takes precedence. To replace the Rails fetcher globally:

```ruby
# config/initializers/page_print.rb
PagePrint.configure do |config|
  config.resource_fetcher = MyResourceFetcher.new
end
```

The built-in Rails fetcher only handles `/assets/...` URLs. Other paths are skipped.

## CSS and rendering support

PagePrint delegates HTML and CSS support to PlutoBook. It supports print-oriented features including `@page`, page counters, and running headers and footers, but it is not a full web browser. JavaScript and CSS Grid are not supported.

Consult the upstream [PlutoBook feature matrix](https://github.com/plutoprint/plutobook/blob/main/FEATURES.md) when designing or migrating templates. Test representative documents after every renderer or font change because pagination can change even when the HTML does not.

[Back to the README](../README.md)
