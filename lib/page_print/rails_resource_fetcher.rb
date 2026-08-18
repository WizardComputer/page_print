require 'pathname'
require 'uri'

module PagePrint
  class RailsResourceFetcher
    DEFAULT_ASSET_PREFIX = '/assets'

    def initialize(rails: nil, asset_prefix: DEFAULT_ASSET_PREFIX)
      @rails = rails || rails_constant
      @asset_prefix = normalize_asset_prefix(asset_prefix)

      raise ArgumentError, 'Rails is not available' unless @rails
    end

    def call(url)
      path = path_from_url(url)
      return unless path&.start_with?("#{@asset_prefix}/")

      read_public_asset(path) || read_resolved_asset(path)
    end

    private

    attr_reader :rails, :asset_prefix

    def rails_constant
      Object.const_get(:Rails) if Object.const_defined?(:Rails)
    end

    def normalize_asset_prefix(value)
      prefix = value.to_s
      prefix = "/#{prefix}" unless prefix.start_with?('/')
      prefix.delete_suffix('/')
    end

    def path_from_url(url)
      parsed = URI.parse(url.to_s)
      parsed.path.empty? ? url.to_s : parsed.path
    rescue URI::InvalidURIError
      url.to_s
    end

    def read_public_asset(path)
      public_path = rails_public_path
      return unless public_path

      relative_path = path.delete_prefix('/')
      public_path = public_path.realpath
      file_path = public_path.join(relative_path).realpath
      return unless inside_path?(file_path, public_path)
      return unless file_path.file?

      resource(File.binread(file_path), file_path.extname)
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
      nil
    end

    def read_resolved_asset(path)
      asset_path = path.delete_prefix("#{asset_prefix}/")
      content = read_from_propshaft(asset_path)
      return resource(content, File.extname(asset_path)) if content

      logical_path = propshaft_logical_path(asset_path)
      return unless logical_path

      content = read_from_propshaft(logical_path)
      return unless content

      resource(content, File.extname(logical_path))
    end

    def read_from_propshaft(path)
      resolver = rails_application&.assets&.resolver
      return unless resolver&.respond_to?(:read)

      resolver.read(path)
    rescue StandardError
      nil
    end

    def propshaft_logical_path(asset_path)
      resolver = rails_application&.assets&.resolver
      return unless resolver&.respond_to?(:load_path)
      return unless resolver.load_path.respond_to?(:find)

      asset = resolver.load_path.find(asset_path)
      asset&.logical_path&.to_s
    rescue StandardError
      nil
    end

    def rails_application
      rails.application if rails.respond_to?(:application)
    end

    def rails_public_path
      path = rails.public_path if rails.respond_to?(:public_path)
      path ||= rails_application.public_path if rails_application&.respond_to?(:public_path)
      return unless path

      Pathname.new(path.to_s).cleanpath
    end

    def inside_path?(path, root)
      relative_path = path.relative_path_from(root).to_s
      relative_path != '..' && !relative_path.start_with?('../')
    rescue ArgumentError
      false
    end

    def resource(content, extension)
      { content: content, mime_type: mime_type_for(extension) }
    end

    def mime_type_for(extension)
      if defined?(Rack::Mime)
        Rack::Mime.mime_type(extension, 'application/octet-stream')
      else
        fallback_mime_type_for(extension)
      end
    end

    def fallback_mime_type_for(extension)
      case extension.to_s.downcase
      when '.css' then 'text/css'
      when '.gif' then 'image/gif'
      when '.html', '.htm' then 'text/html'
      when '.jpeg', '.jpg' then 'image/jpeg'
      when '.js', '.mjs' then 'text/javascript'
      when '.otf' then 'font/otf'
      when '.png' then 'image/png'
      when '.svg' then 'image/svg+xml'
      when '.ttf' then 'font/ttf'
      when '.webp' then 'image/webp'
      when '.woff' then 'font/woff'
      when '.woff2' then 'font/woff2'
      else 'application/octet-stream'
      end
    end
  end
end
