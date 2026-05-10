# AGENTS.md

## Project Overview

`page_print` is a Ruby gem with a native C extension that renders HTML strings to PDF files using the `plutobook` C library.

The public Ruby API is intentionally small. `PagePrint.html_to_pdf` is the primary entry point.

## Repository Layout

- `lib/page_print.rb` loads the gem version and native extension.
- `lib/page_print/version.rb` defines the gem version.
- `ext/page_print/page_print.c` contains the native Ruby C extension.
- `ext/page_print/extconf.rb` configures compilation and locates `plutobook`.
- `test/page_print_test.rb` contains the Minitest suite.
- `Rakefile` defines compile, test, and default tasks.
- `page_print.gemspec` defines gem metadata, files, and extension build config.

## Setup

Install Ruby dependencies:

```sh
bundle install
```

The native extension requires `plutobook` development headers and library files.

On macOS with Homebrew:

```sh
brew install plutobook pkg-config
```

If `pkg-config` cannot find `plutobook`, pass explicit paths when building or installing the gem.

## Build And Test

Compile the native extension:

```sh
bundle exec rake compile
```

Run tests only:

```sh
bundle exec rake test
```

Run the default task, which compiles and tests:

```sh
bundle exec rake
```

Use `bin/console` for a local development console. It compiles the extension before starting IRB.

## Development Guidelines

- Keep the Ruby-facing API minimal and documented in `README.md`.
- When changing `PagePrint.html_to_pdf`, update tests for both successful output and validation/error behavior.
- Prefer inline Ruby calls for readability; only break Ruby argument lists across lines when the line would exceed 120 characters.
- Format Ruby private sections with `private` at the class indentation level and private method definitions indented beneath it, without a blank line between `private` and the first private method.
- Validate Ruby argument types before passing data into `plutobook`.
- Ensure native resources are destroyed on failure paths before raising Ruby exceptions.
- Prefer clear Ruby exception messages because tests assert exact messages.
- Do not commit generated native build artifacts such as `.bundle`, `.o`, `Makefile`, `mkmf.log`, `pkg/`, or `tmp/`.

## Native Extension Notes

- `ext/page_print/extconf.rb` uses `mkmf`, `pkg_config('plutobook')`, and `dir_config('plutobook')`.
- The extension currently supports keyword options for `base_url`, `page_size`, `margins`, and `media`.
- Keep accepted option values synchronized across `README.md`, tests, and `ext/page_print/page_print.c`.

## Verification

Before finishing changes, run:

```sh
bundle exec rake
```

If the environment lacks `plutobook`, report that compilation or tests could not be completed and include the relevant error.
