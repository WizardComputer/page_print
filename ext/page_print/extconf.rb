require 'mkmf'

def page_print_native_platform
  platform = Gem::Platform.local

  if platform.os == 'linux' && platform.cpu == 'x86_64'
    'x86_64-linux'
  else
    platform.to_s
  end
end

project_root = File.expand_path('../..', __dir__)
vendor_platform = ENV.fetch('PAGE_PRINT_VENDOR_PLATFORM', page_print_native_platform)
vendor_dir = File.join(project_root, 'lib', 'page_print', 'vendor', vendor_platform)
vendor_include_dir = File.join(vendor_dir, 'include')
vendor_lib_dir = File.join(vendor_dir, 'lib')

if File.directory?(vendor_include_dir) && File.directory?(vendor_lib_dir)
  dir_config('plutobook', vendor_include_dir, vendor_lib_dir)

  if vendor_platform.end_with?('-linux')
    $LDFLAGS = "-Wl,-rpath,\\$$ORIGIN/vendor/#{vendor_platform}/lib #{$LDFLAGS}"
  end
else
  pkg_config('plutobook')
end

dir_config('plutobook')

['/opt/homebrew/opt/plutobook', '/usr/local/opt/plutobook'].each do |prefix|
  next unless File.directory?(prefix)

  dir_config('plutobook', File.join(prefix, 'include'), File.join(prefix, 'lib'))
  break
end

unless have_header('plutobook/plutobook.h')
  abort 'plutobook header not found. Install plutobook or pass --with-plutobook-include=/path/to/include'
end

unless have_library('plutobook', 'plutobook_create')
  abort 'plutobook library not found. Install plutobook or pass --with-plutobook-lib=/path/to/lib'
end

create_makefile('page_print/page_print')
