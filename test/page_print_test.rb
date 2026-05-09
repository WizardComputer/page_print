require 'minitest/autorun'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require_relative '../lib/page_print'

class PagePrintTest < Minitest::Test
  def test_has_a_version
    refute_nil PagePrint::VERSION
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

  def test_html_to_pdf_requires_page_size_to_be_a_symbol
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', page_size: 'letter')
    end

    assert_equal 'page_size must be a Symbol', error.message
  end

  def test_html_to_pdf_rejects_invalid_margins
    error = assert_raises(ArgumentError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', margins: :compact)
    end

    assert_equal 'margins must be one of: :none, :normal, :narrow, :moderate, :wide', error.message
  end

  def test_html_to_pdf_requires_margins_to_be_a_symbol
    error = assert_raises(TypeError) do
      PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', 'output.pdf', margins: 'narrow')
    end

    assert_equal 'margins must be a Symbol', error.message
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
end
