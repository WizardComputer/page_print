require 'minitest/autorun'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require_relative '../lib/page_print'

class PagePrintConcurrencyTest < Minitest::Test
  def test_concurrent_renders
    thread_count = 4
    iterations = Integer(ENV.fetch('PAGE_PRINT_CONCURRENCY_ITERATIONS', '2'))

    threads = thread_count.times.map do |thread_index|
      Thread.new do
        iterations.times do |iteration|
          render_concurrently(thread_index, iteration)
        end
      end
    end

    assert_equal [iterations] * thread_count, threads.map(&:value)
  end

  private
    def render_concurrently(thread_index, iteration)
      asset_url = "custom:style-#{thread_index}-#{iteration}"
      fetched_urls = []
      html = %(<html><head><link rel="stylesheet" href="#{asset_url}"></head><body><h1>Hello</h1></body></html>)
      options = {
        resource_fetcher: lambda { |url|
          fetched_urls << url
          { content: 'body { color: navy; }', mime_type: 'text/css' }
        }
      }

      pdf = PagePrint.render(html, **options)
      raise 'invalid streamed PDF' unless pdf.start_with?('%PDF')

      Dir.mktmpdir do |dir|
        path = File.join(dir, 'output.pdf')
        PagePrint.render_to_file(html, path, **options)
        raise 'invalid file PDF' unless File.binread(path, 4) == '%PDF'
      end

      raise "resource fetch mismatch: #{fetched_urls.inspect}" unless fetched_urls == [asset_url, asset_url]
    end
end
