require 'page_print/version'
require_relative 'page_print/page_print'
require 'page_print/rails_resource_fetcher'

module PagePrint
  class << self
    attr_accessor :resource_fetcher

    def configure
      yield self
    end
  end
end
