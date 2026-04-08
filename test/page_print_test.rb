require 'minitest/autorun'
require 'tmpdir'
require 'page_print'

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

  def test_html_to_pdf_writes_output_file
    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'output.pdf')

      assert PagePrint.html_to_pdf('<html><body><h1>Hello</h1></body></html>', output_path)
      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0
    end
  end
end
