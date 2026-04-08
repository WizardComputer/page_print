require 'mkmf'

pkg_config('plutobook')

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
