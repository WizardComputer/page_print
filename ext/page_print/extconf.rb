require "mkmf"

pkg_config("plutobook")
dir_config("plutobook", "/opt/homebrew/opt/plutobook/include", "/opt/homebrew/opt/plutobook/lib")

abort "plutobook/plutobook.h not found" unless have_header("plutobook/plutobook.h")
abort "libplutobook not found" unless have_library("plutobook", "plutobook_version_string")

create_makefile("page_print/page_print")
