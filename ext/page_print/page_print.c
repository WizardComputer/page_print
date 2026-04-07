#include "ruby.h"
#include <plutobook/plutobook.h>

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

static VALUE pageprint_join_html_and_path(VALUE self, VALUE html, VALUE path) {
  const char *html_str;
  const char *path_str;

  VALUE result;

  html_str = StringValueCStr(html);
  path_str = StringValueCStr(path);

  result = rb_str_new_cstr("HTML: ");
  rb_str_cat_cstr(result, html_str);
  rb_str_cat_cstr(result, " | PATH:");
  rb_str_cat_cstr(result, path_str);

  return result;
}

static VALUE pageprint_html_to_pdf(VALUE self, VALUE html, VALUE path) {
    const char *html_str;
    const char *path_str;

    plutobook_t *book;
    int ok;

    html_str = StringValueCStr(html);
    path_str = StringValueCStr(path);

    /* 1. Create */
    book = plutobook_create(PLUTOBOOK_PAGE_SIZE_A4, PLUTOBOOK_PAGE_MARGINS_NORMAL, PLUTOBOOK_MEDIA_TYPE_PRINT);

    if (!book) {
        rb_raise(rb_eRuntimeError, "failed to create plutobook");
    }

    /* 2. Load HTML */
    ok = plutobook_load_html(
        book,
        html_str,
        -1,     /* null-terminated */
        "",     /* base URL */
        "",     /* encoding */
        ""      /* media */
    );

    if (!ok) {
        plutobook_destroy(book);
        rb_raise(rb_eRuntimeError, "failed to load html");
    }

    ok = plutobook_write_to_pdf(book, path_str);
    plutobook_destroy(book);

    if (!ok) {
        rb_raise(rb_eRuntimeError, "failed to write pdf");
    }

    return Qtrue;
}

void Init_page_print(void) {
    mPagePrint = rb_define_module("PagePrint");

    rb_define_singleton_method(mPagePrint, "hello", pageprint_hello, 0);
    rb_define_singleton_method(mPagePrint, "echo", pageprint_echo, 1);
    rb_define_singleton_method(mPagePrint, "join_html_and_path", pageprint_join_html_and_path, 2);
    rb_define_singleton_method(mPagePrint, "html_to_pdf", pageprint_html_to_pdf, 2);
}
