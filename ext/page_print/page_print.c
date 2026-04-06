#include "ruby.h"

static VALUE mPagePrint;

static VALUE pageprint_hello(VALUE self) {
    return rb_str_new_cstr("hello from C");
}

static VALUE pageprint_echo(VALUE self, VALUE input) {
  const char *str;

  // Ensure it's a string and get C pointer
  str = StringValueCStr(input);

  // Build new Ruby string
  VALUE result = rb_str_new_cstr("C says: ");
  rb_str_cat_cstr(result, str);

  return result;
}

void Init_page_print(void) {
    mPagePrint = rb_define_module("PagePrint");

    rb_define_singleton_method(mPagePrint, "hello", pageprint_hello, 0);
    rb_define_singleton_method(mPagePrint, "echo", pageprint_echo, 1);
}
