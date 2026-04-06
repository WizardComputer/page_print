#include "ruby.h"

static VALUE mPagePrint;

static VALUE pageprint_hello(VALUE self) {
    return rb_str_new_cstr("hello from C");
}

void Init_page_print(void) {
    mPagePrint = rb_define_module("PagePrint");
    rb_define_singleton_method(mPagePrint, "hello", pageprint_hello, 0);
}
