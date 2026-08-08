require 'mkmf'

def page_print_native_platform
  platform = Gem::Platform.local

  if platform.os == 'linux' && platform.cpu == 'x86_64'
    'x86_64-linux'
  elsif platform.os == 'darwin' && platform.cpu == 'arm64'
    'arm64-darwin'
  else
    platform.to_s
  end
end

def restore_vendor_so_aliases(vendor_lib_dir)
  manifest_path = File.join(vendor_lib_dir, 'so_aliases')
  return unless File.file?(manifest_path)

  File.foreach(manifest_path) do |line|
    alias_name, target_name = line.strip.split("\t", 2)
    next if alias_name.nil? || alias_name.empty? || target_name.nil? || target_name.empty?
    next if alias_name.include?('/') || target_name.include?('/') || alias_name.start_with?('.') || target_name.start_with?('.')

    alias_path = File.join(vendor_lib_dir, alias_name)
    target_path = File.join(vendor_lib_dir, target_name)
    next unless File.file?(target_path)
    next if File.exist?(alias_path) || File.symlink?(alias_path)

    File.symlink(target_name, alias_path)
  end
end

project_root = File.expand_path('../..', __dir__)
vendor_platform = ENV.fetch('PAGE_PRINT_VENDOR_PLATFORM', page_print_native_platform)
vendor_dir = File.join(project_root, 'lib', 'page_print', 'vendor', vendor_platform)
vendor_include_dir = File.join(vendor_dir, 'include')
vendor_lib_dir = File.join(vendor_dir, 'lib')

if File.directory?(vendor_include_dir) && File.directory?(vendor_lib_dir)
  restore_vendor_so_aliases(vendor_lib_dir)
  dir_config('plutobook', vendor_include_dir, vendor_lib_dir)

  if vendor_platform.end_with?('-linux')
    $LDFLAGS = "-Wl,-rpath,\\$$ORIGIN/vendor/#{vendor_platform}/lib #{$LDFLAGS}"
  elsif vendor_platform.end_with?('-darwin')
    $LDFLAGS = "-Wl,-rpath,@loader_path/vendor/#{vendor_platform}/lib #{$LDFLAGS}"
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
