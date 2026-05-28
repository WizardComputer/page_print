lib_dir = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require 'page_print/version'

Gem::Specification.new do |spec|
  spec.name = 'page_print'
  spec.version = PagePrint::VERSION
  spec.authors = ['Dino Maric']
  spec.email = ['dino.onex@gmail.com']

  spec.summary = 'Render HTML to PDF from Ruby using plutobook'
  spec.description = 'A Ruby gem with a native extension that renders HTML strings to PDF files via the plutobook C library.'
  spec.homepage = 'https://example.com/page_print'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  precompiled = ENV['PAGE_PRINT_PRECOMPILED'] == '1'

  spec.files = Dir.glob('{lib,ext}/**/*', File::FNM_DOTMATCH).reject do |path|
    File.directory?(path) || path.match?(%r{/(?:Makefile|mkmf\.log|.*\.(?:o|bundle))\z})
  end + ['README.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = []
  spec.require_paths = ['lib']

  if precompiled
    spec.platform = Gem::Platform.new(ENV.fetch('PAGE_PRINT_PRECOMPILED_PLATFORM', Gem::Platform.local.to_s))
    spec.files += Dir.glob('lib/page_print/**/*.{so,dylib}', File::FNM_DOTMATCH)
  else
    spec.extensions = ['ext/page_print/extconf.rb']
  end

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
end
