require 'page_print/version'
require_relative 'page_print/page_print'
require 'page_print/rails_resource_fetcher'

module PagePrint
  class << self
    attr_accessor :resource_fetcher
    attr_writer :base_url

    def base_url
      Thread.current[:page_print_base_url] || @base_url
    end

    def configure
      yield self
    end

    def with_base_url(base_url)
      previous_base_url = Thread.current[:page_print_base_url]
      Thread.current[:page_print_base_url] = base_url
      yield
    ensure
      Thread.current[:page_print_base_url] = previous_base_url
    end
  end
end

require 'page_print/railtie' if defined?(Rails::Railtie)
