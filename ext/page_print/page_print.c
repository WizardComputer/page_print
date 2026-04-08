#include "ruby.h"
#include <plutobook/plutobook.h>

static VALUE mPagePrint;

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

    rb_define_singleton_method(mPagePrint, "html_to_pdf", pageprint_html_to_pdf, 2);
}
