require "mkmf"

#pkg_config("plutobook") -> someting is wrong with pluto

pluto_prefix = "/opt/homebrew/opt/plutobook"

dir_config("plutobook","#{pluto_prefix}/include", "#{pluto_prefix}/lib")

$INCFLAGS << " -I#{pluto_prefix}/include"

abort "header not found" unless have_header("plutobook/plutobook.h")
abort "lib not found" unless have_library("plutobook", "plutobook_create")

create_makefile("page_print/page_print")
