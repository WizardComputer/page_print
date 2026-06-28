require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require_relative '../lib/page_print'

class PagePrintTest < Minitest::Test
  def teardown
    PagePrint.resource_fetcher = nil
    PagePrint.base_url = nil
  end

  def test_has_a_version
    refute_nil PagePrint::VERSION
  end

  def test_configure_sets_default_resource_fetcher
    fetcher = proc { nil }

    PagePrint.configure do |config|
      config.resource_fetcher = fetcher
    end

    assert_same fetcher, PagePrint.resource_fetcher
  end

  def test_rails_resource_fetcher_reads_public_assets
    Dir.mktmpdir do |dir|
      public_dir = File.join(dir, 'public')
      assets_dir = File.join(public_dir, 'assets')
      FileUtils.mkdir_p(assets_dir)
      File.binwrite(File.join(assets_dir, 'pdf.css'), 'body { color: red; }')

      fetcher = PagePrint::RailsResourceFetcher.new(rails: fake_rails(public_dir))

      assert_equal(
        { content: 'body { color: red; }', mime_type: 'text/css' },
        fetcher.call('http://example.com/assets/pdf.css')
      )
    end
  end

  def test_rails_resource_fetcher_ignores_non_asset_urls
    fetcher = PagePrint::RailsResourceFetcher.new(rails: fake_rails(Dir.tmpdir))

    assert_nil fetcher.call('http://example.com/images/logo.png')
  end

  def test_rails_resource_fetcher_rejects_path_traversal_outside_public_path
    Dir.mktmpdir do |dir|
      public_dir = File.join(dir, 'public')
      nested_assets_dir = File.join(public_dir, 'assets', 'nested')
      FileUtils.mkdir_p(nested_assets_dir)
      File.binwrite(File.join(dir, 'secret.txt'), 'outside public')

      fetcher = PagePrint::RailsResourceFetcher.new(rails: fake_rails(public_dir))

      assert_nil fetcher.call('http://example.com/assets/../../secret.txt')
      assert_nil fetcher.call('http://example.com/assets/nested/../../../secret.txt')
    end
  end

  def test_rails_resource_fetcher_uses_propshaft_load_path_for_digested_assets
    asset = Struct.new(:logical_path).new('pdf.css')
    load_path = Class.new do
      def initialize(asset)
        @asset = asset
      end

      def find(path)
        @asset if path == 'pdf-abc123.css'
      end
    end.new(asset)

    resolver = Class.new do
      attr_reader :load_path

      def initialize(load_path)
        @load_path = load_path
      end

      def read(path)
        return 'body { color: blue; }' if path == 'pdf.css'
      end
    end.new(load_path)

    assets = Struct.new(:resolver).new(resolver)
    app = Struct.new(:assets).new(assets)
    rails = Struct.new(:public_path, :application).new(Dir.tmpdir, app)
    fetcher = PagePrint::RailsResourceFetcher.new(rails: rails)

    assert_equal(
      { content: 'body { color: blue; }', mime_type: 'text/css' },
      fetcher.call('http://example.com/assets/pdf-abc123.css')
    )
  end

  def test_configured_rails_resource_fetcher_works_with_pdf_rendering
    Dir.mktmpdir do |dir|
      public_dir = File.join(dir, 'public')
      assets_dir = File.join(public_dir, 'assets')
      FileUtils.mkdir_p(assets_dir)
      File.binwrite(File.join(assets_dir, 'pdf.css'), 'body { color: green; }')

      PagePrint.resource_fetcher = PagePrint::RailsResourceFetcher.new(rails: fake_rails(public_dir))
      pdf = PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="/assets/pdf.css"></head><body><h1>Hello</h1></body></html>',
        base_url: 'http://example.com'
      )

      assert_operator pdf.bytesize, :>, 0
      assert_equal '%PDF', pdf.byteslice(0, 4)
    end
  end

  def test_html_to_pdf_string_uses_configured_base_url
    urls = []

    PagePrint.base_url = 'http://example.com'

    pdf = PagePrint.html_to_pdf_string(
      '<html><head><link rel="stylesheet" href="/assets/pdf.css"></head><body><h1>Hello</h1></body></html>',
      resource_fetcher: lambda { |url|
        urls << url
        { content: 'body { color: purple; }', mime_type: 'text/css' }
      }
    )

    assert_includes urls, 'http://example.com/assets/pdf.css'
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_uses_request_local_base_url
    urls = []

    pdf = PagePrint.with_base_url('http://request.example') do
      PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="/assets/pdf.css"></head><body><h1>Hello</h1></body></html>',
        resource_fetcher: lambda { |url|
          urls << url
          { content: 'body { color: yellow; }', mime_type: 'text/css' }
        }
      )
    end

    assert_includes urls, 'http://request.example/assets/pdf.css'
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_with_base_url_restores_previous_base_url
    PagePrint.base_url = 'http://configured.example'

    PagePrint.with_base_url('http://request.example') do
      assert_equal 'http://request.example', PagePrint.base_url
    end

    assert_equal 'http://configured.example', PagePrint.base_url
  end

  def test_html_to_pdf_string_does_not_override_explicit_base_url
    urls = []

    pdf = PagePrint.with_base_url('http://request.example') do
      PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="/assets/pdf.css"></head><body><h1>Hello</h1></body></html>',
        base_url: 'http://explicit.example',
        resource_fetcher: lambda { |url|
          urls << url
          { content: 'body { color: orange; }', mime_type: 'text/css' }
        }
      )
    end

    assert_includes urls, 'http://explicit.example/assets/pdf.css'
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_requires_html_to_be_a_string
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf(123, 'output.pdf')
    end

    assert_equal 'html must be a String', error.message
  end

  def test_html_to_pdf_requires_path_to_be_a_string
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 123)
    end

    assert_equal 'path must be a String', error.message
  end

  def test_html_to_pdf_rejects_empty_html
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('', 'output.pdf')
    end

    assert_equal 'html must not be empty', error.message
  end

  def test_html_to_pdf_rejects_empty_path
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', '')
    end

    assert_equal 'path must not be empty', error.message
  end

  def test_html_to_pdf_writes_output_file
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.pdf')

      assert PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', output_path)
      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0
    end
  end

  def test_html_to_pdf_accepts_keyword_options
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.pdf')

      assert PagePrint.html_to_pdf(
        '<html><body><h1>Hello</h1></body></html>',
        output_path,
        base_url: 'https://example.com',
        page_size: :letter,
        margins: :narrow,
        media: :screen
      )

      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0
    end
  end

  def test_html_to_pdf_accepts_custom_page_size_and_margins
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.pdf')

      assert PagePrint.html_to_pdf(
        '<html><body><h1>Hello</h1></body></html>',
        output_path,
        page_size: { width: 100, height: 150, unit: :mm },
        margins: { top: 5, right: 6, bottom: 7, left: 8, unit: :mm }
      )

      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0
      assert_match(/Page size:\s+283\.\d+ x 425\.\d+ pts/, pdfinfo(output_path))
    end
  end

  def test_html_to_pdf_accepts_metadata
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.pdf')

      assert PagePrint.html_to_pdf(
        '<html><body><h1>Hello</h1></body></html>',
        output_path,
        metadata: {
          title: 'Test PDF',
          author: 'PagePrint',
          subject: 'Metadata test',
          keywords: 'pdf,test',
          creation_date: '2026-05-10T12:00:00Z',
          modification_date: nil
        }
      )

      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0

      info = pdfinfo(output_path)
      assert_includes info, 'Title:           Test PDF'
      assert_includes info, 'Subject:         Metadata test'
      assert_includes info, 'Keywords:        pdf,test'
      assert_includes info, 'Author:          PagePrint'
    end
  end

  def test_html_to_pdf_string_returns_pdf_bytes
    pdf = PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>')

    assert_instance_of String, pdf
    assert_equal Encoding::ASCII_8BIT, pdf.encoding
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_accepts_keyword_options
    pdf = PagePrint.html_to_pdf_string(
      '<html><body><h1>Hello</h1></body></html>',
      base_url: 'https://example.com',
      page_size: :letter,
      margins: :narrow,
      media: :screen
    )

    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_accepts_metadata
    pdf = PagePrint.html_to_pdf_string(
      '<html><body><h1>Hello</h1></body></html>',
      metadata: {
        title: 'Test PDF',
        author: 'PagePrint',
        subject: 'Metadata test',
        keywords: 'pdf,test',
        creation_date: '2026-05-10T12:00:00Z',
        modification_date: '2026-05-10T12:01:00Z'
      }
    )

    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_accepts_nil_metadata
    pdf = PagePrint.html_to_pdf_string(
      '<html><body><h1>Hello</h1></body></html>',
      metadata: nil
    )

    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_requires_metadata_to_be_a_hash_or_nil
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', metadata: 'title')
    end

    assert_equal 'metadata must be a Hash or nil', error.message
  end

  def test_html_to_pdf_string_requires_metadata_keys_to_be_symbols
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', metadata: { 'title' => 'Test PDF' })
    end

    assert_equal 'metadata keys must be Symbols', error.message
  end

  def test_html_to_pdf_string_rejects_unknown_metadata_keys
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', metadata: { publisher: 'PagePrint' })
    end

    assert_equal 'metadata contains unknown key: :publisher', error.message
  end

  def test_html_to_pdf_string_rejects_creator_metadata
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', metadata: { creator: 'PagePrint' })
    end

    assert_equal 'metadata contains unknown key: :creator', error.message
  end

  def test_html_to_pdf_string_requires_metadata_values_to_be_strings_or_nil
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', metadata: { title: 123 })
    end

    assert_equal 'metadata values must be Strings or nil', error.message
  end

  def test_html_to_pdf_string_reraises_metadata_errors_after_html_load
    metadata = { title: 'Test PDF' }
    html = '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>'

    assert_raises(TypeError) do
      PagePrint.html_to_pdf_string(
        html,
        metadata: metadata,
        resource_fetcher: lambda { |_url|
          metadata[:title] = 123
          { content: 'body {}', mime_type: 'text/css' }
        }
      )
    end

    pdf = PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>')
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_uses_resource_fetcher
    urls = []
    pdf = PagePrint.html_to_pdf_string(
      '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>',
      resource_fetcher: lambda { |url|
        urls << url
        { content: 'body { color: red; }', mime_type: 'text/css', text_encoding: 'utf-8' }
      }
    )

    assert_includes urls, 'custom:style'
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_uses_configured_resource_fetcher
    urls = []
    PagePrint.resource_fetcher = lambda { |url|
      urls << url
      { content: 'body { color: blue; }', mime_type: 'text/css' }
    }

    pdf = PagePrint.html_to_pdf_string(
      '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>'
    )

    assert_includes urls, 'custom:style'
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_requires_resource_fetcher_to_respond_to_call
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', resource_fetcher: Object.new)
    end

    assert_equal 'resource_fetcher must respond to call or be nil/false', error.message
  end

  def test_html_to_pdf_string_requires_resource_fetcher_result_to_be_a_hash_or_nil
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>',
        resource_fetcher: ->(_url) { [] }
      )
    end

    assert_equal 'resource_fetcher must return a Hash or nil', error.message
  end

  def test_html_to_pdf_string_requires_resource_fetcher_content_to_be_a_string
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>',
        resource_fetcher: ->(_url) { { content: nil, mime_type: 'text/css' } }
      )
    end

    assert_equal 'resource_fetcher result content must be a String', error.message
  end

  def test_html_to_pdf_string_requires_resource_fetcher_mime_type_to_be_a_string
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>',
        resource_fetcher: ->(_url) { { content: 'body {}', mime_type: nil } }
      )
    end

    assert_equal 'resource_fetcher result mime_type must be a String', error.message
  end

  def test_html_to_pdf_string_reraises_resource_fetcher_errors
    error = assert_raises(RuntimeError) do
      PagePrint.html_to_pdf_string(
        '<html><head><link rel="stylesheet" href="custom:style"></head><body><h1>Hello</h1></body></html>',
        resource_fetcher: ->(_url) { raise 'fetch failed' }
      )
    end

    assert_equal 'fetch failed', error.message
  end

  def test_html_to_pdf_string_denies_network_fetch_when_resource_fetcher_returns_nil
    html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head><body></body></html>'
    urls = []

    pdf = PagePrint.html_to_pdf_string(
      html,
      resource_fetcher: ->(url) {
        urls << url
        nil
      }
    )

    assert_includes urls, 'http://example.com/style.css'
    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_denies_network_fetch_without_resource_fetcher
    html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head><body></body></html>'

    pdf = PagePrint.html_to_pdf_string(html)

    assert_operator pdf.bytesize, :>, 0
    assert_equal '%PDF', pdf.byteslice(0, 4)
  end

  def test_html_to_pdf_string_requires_html_to_be_a_string
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string(123)
    end

    assert_equal 'html must be a String', error.message
  end

  def test_html_to_pdf_string_rejects_empty_html
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf_string('')
    end

    assert_equal 'html must not be empty', error.message
  end

  def test_html_to_pdf_string_rejects_invalid_options
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', :options)
    end

    assert_equal 'options must be a Hash', error.message
  end

  def test_html_to_pdf_string_rejects_unknown_keyword
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', foo: :bar)
    end

    assert_equal 'unknown keyword: :foo', error.message
  end

  def test_html_to_pdf_string_rejects_invalid_media
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf_string('<html><body><h1>Hello</h1></body></html>', media: :speech)
    end

    assert_equal 'media must be one of: :print, :screen', error.message
  end

  def test_html_to_pdf_includes_path_when_pdf_write_fails
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'missing', 'output.pdf')

      error = assert_raises(RuntimeError) do
        PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', output_path)
      end

      assert_match(/\Afailed to write PDF to #{Regexp.escape(output_path)}/, error.message)
    end
  end

  def test_html_to_pdf_accepts_nil_base_url
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.pdf')

      assert PagePrint.html_to_pdf(
        '<html><body><h1>Hello</h1></body></html>',
        output_path,
        base_url: nil
      )

      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0
    end
  end

  def test_html_to_pdf_requires_options_to_be_a_hash
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', :options)
    end

    assert_equal 'options must be a Hash', error.message
  end

  def test_html_to_pdf_requires_base_url_to_be_a_string_or_nil
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', base_url: 123)
    end

    assert_equal 'base_url must be a String or nil', error.message
  end

  def test_html_to_pdf_rejects_invalid_page_size
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', page_size: :tabloid)
    end

    assert_equal 'page_size must be one of: :a3, :a4, :a5, :b4, :b5, :letter, :legal, :ledger', error.message
  end

  def test_html_to_pdf_requires_page_size_to_be_a_symbol_or_hash
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', page_size: 'letter')
    end

    assert_equal 'page_size must be a Symbol or Hash', error.message
  end

  def test_html_to_pdf_requires_custom_page_size_unit
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', page_size: { width: 100, height: 150 })
    end

    assert_equal 'page_size requires :unit', error.message
  end

  def test_html_to_pdf_rejects_invalid_custom_page_size_unit
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', page_size: { width: 100, height: 150, unit: :meter })
    end

    assert_equal 'page_size unit must be one of: :pt, :pc, :in, :cm, :mm, :px', error.message
  end

  def test_html_to_pdf_rejects_non_positive_custom_page_size
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', page_size: { width: 0, height: 150, unit: :mm })
    end

    assert_equal 'page_size width must be greater than 0', error.message
  end

  def test_html_to_pdf_rejects_invalid_margins
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', margins: :compact)
    end

    assert_equal 'margins must be one of: :none, :normal, :narrow, :moderate, :wide', error.message
  end

  def test_html_to_pdf_requires_margins_to_be_a_symbol_or_hash
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', margins: 'narrow')
    end

    assert_equal 'margins must be a Symbol or Hash', error.message
  end

  def test_html_to_pdf_requires_custom_margins_unit
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', margins: { top: 1, right: 1, bottom: 1, left: 1 })
    end

    assert_equal 'margins requires :unit', error.message
  end

  def test_html_to_pdf_rejects_negative_custom_margins
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', margins: { top: -1, right: 1, bottom: 1, left: 1, unit: :mm })
    end

    assert_equal 'margins values must be greater than or equal to 0', error.message
  end

  def test_html_to_pdf_rejects_invalid_media
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', media: :speech)
    end

    assert_equal 'media must be one of: :print, :screen', error.message
  end

  def test_html_to_pdf_requires_media_to_be_a_symbol
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', media: 'screen')
    end

    assert_equal 'media must be a Symbol', error.message
  end

  def test_html_to_pdf_rejects_unknown_keyword
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', foo: :bar)
    end

    assert_equal 'unknown keyword: :foo', error.message
  end

  private
    def fake_rails(public_path)
      Struct.new(:public_path).new(public_path)
    end

    def pdfinfo(path)
      output, status = Open3.capture2('pdfinfo', path)

      return output if status.success?

      skip 'pdfinfo is unavailable'
    rescue Errno::ENOENT
      skip 'pdfinfo is unavailable'
    end

end
