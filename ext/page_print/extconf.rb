require 'mkmf'

pkg_config('plutobook')

dir_config('plutobook')

unless have_header('plutobook/plutobook.h')
  abort 'plutobook header not found. Install plutobook or pass --with-plutobook-include=/path/to/include'
end

unless have_library('plutobook', 'plutobook_create')
  abort 'plutobook library not found. Install plutobook or pass --with-plutobook-lib=/path/to/lib'
end

create_makefile('page_print/page_print')
