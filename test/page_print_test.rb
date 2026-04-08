require 'minitest/autorun'
require 'tmpdir'
require 'page_print'

class PagePrintTest < Minitest::Test
  def test_has_a_version
    refute_nil PagePrint::VERSION
  end

  def test_hello_round_trip
    assert_equal 'hello from C', PagePrint.hello
  end

  def test_echo_round_trip
    assert_equal 'C says: hello', PagePrint.echo('hello')
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
