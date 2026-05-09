#include "ruby.h"
#include <limits.h>
#include <plutobook/plutobook.h>

#if defined(__GNUC__) || defined(__clang__)
#define PAGEPRINT_NORETURN __attribute__((noreturn))
#else
#define PAGEPRINT_NORETURN
#endif

static VALUE mPagePrint;
static ID id_base_url;
static ID id_page_size;
static ID id_margins;
static ID id_media;

static void PAGEPRINT_NORETURN pageprint_raise_plutobook_error(VALUE error_class, const char *message)
{
    const char *error_message = plutobook_get_error_message();

    if (error_message && error_message[0] != '\0') {
        rb_raise(error_class, "%s: %s", message, error_message);
    }

    rb_raise(error_class, "%s", message);
}

static void PAGEPRINT_NORETURN pageprint_raise_plutobook_error_with_path(VALUE error_class, const char *message, const char *path)
{
    const char *error_message = plutobook_get_error_message();

    if (error_message && error_message[0] != '\0') {
        rb_raise(error_class, "%s %s: %s", message, path, error_message);
    }

    rb_raise(error_class, "%s %s", message, path);
}

static plutobook_page_size_t pageprint_page_size_from_value(VALUE value)
{
    ID value_id;

    if (!RB_SYMBOL_P(value)) {
        rb_raise(rb_eTypeError, "page_size must be a Symbol");
    }

    value_id = SYM2ID(value);

    if (value_id == rb_intern("a3")) return PLUTOBOOK_PAGE_SIZE_A3;
    if (value_id == rb_intern("a4")) return PLUTOBOOK_PAGE_SIZE_A4;
    if (value_id == rb_intern("a5")) return PLUTOBOOK_PAGE_SIZE_A5;
    if (value_id == rb_intern("b4")) return PLUTOBOOK_PAGE_SIZE_B4;
    if (value_id == rb_intern("b5")) return PLUTOBOOK_PAGE_SIZE_B5;
    if (value_id == rb_intern("letter")) return PLUTOBOOK_PAGE_SIZE_LETTER;
    if (value_id == rb_intern("legal")) return PLUTOBOOK_PAGE_SIZE_LEGAL;
    if (value_id == rb_intern("ledger")) return PLUTOBOOK_PAGE_SIZE_LEDGER;

    rb_raise(rb_eArgError, "page_size must be one of: :a3, :a4, :a5, :b4, :b5, :letter, :legal, :ledger");
}

static plutobook_page_margins_t pageprint_margins_from_value(VALUE value)
{
    ID value_id;

    if (!RB_SYMBOL_P(value)) {
        rb_raise(rb_eTypeError, "margins must be a Symbol");
    }

    value_id = SYM2ID(value);

    if (value_id == rb_intern("none")) return PLUTOBOOK_PAGE_MARGINS_NONE;
    if (value_id == rb_intern("normal")) return PLUTOBOOK_PAGE_MARGINS_NORMAL;
    if (value_id == rb_intern("narrow")) return PLUTOBOOK_PAGE_MARGINS_NARROW;
    if (value_id == rb_intern("moderate")) return PLUTOBOOK_PAGE_MARGINS_MODERATE;
    if (value_id == rb_intern("wide")) return PLUTOBOOK_PAGE_MARGINS_WIDE;

    rb_raise(rb_eArgError, "margins must be one of: :none, :normal, :narrow, :moderate, :wide");
}

static plutobook_media_type_t pageprint_media_from_value(VALUE value)
{
    ID value_id;

    if (!RB_SYMBOL_P(value)) {
        rb_raise(rb_eTypeError, "media must be a Symbol");
    }

    value_id = SYM2ID(value);

    if (value_id == rb_intern("print")) return PLUTOBOOK_MEDIA_TYPE_PRINT;
    if (value_id == rb_intern("screen")) return PLUTOBOOK_MEDIA_TYPE_SCREEN;

    rb_raise(rb_eArgError, "media must be one of: :print, :screen");
}

static VALUE pageprint_html_to_pdf(int argc, VALUE *argv, VALUE self) {
    VALUE html;
    VALUE path;
    VALUE options;
    VALUE base_url_value;
    VALUE page_size_value;
    VALUE margins_value;
    VALUE media_value;
    VALUE keyword_values[4];
    ID keyword_ids[4];

    const char *html_str;
    const char *path_str;
    const char *base_url_str;
    long html_len;

    plutobook_t *book;
    int ok;
    plutobook_page_size_t page_size = PLUTOBOOK_PAGE_SIZE_A4;
    plutobook_page_margins_t margins = PLUTOBOOK_PAGE_MARGINS_NORMAL;
    plutobook_media_type_t media = PLUTOBOOK_MEDIA_TYPE_PRINT;

    rb_check_arity(argc, 2, 3);

    html = argv[0];
    path = argv[1];
    options = argc == 3 ? argv[2] : Qnil;

    if (!RB_TYPE_P(html, T_STRING)) {
        rb_raise(rb_eTypeError, "html must be a String");
    }

    if (!RB_TYPE_P(path, T_STRING)) {
        rb_raise(rb_eTypeError, "path must be a String");
    }

    if (RSTRING_LEN(html) == 0) {
        rb_raise(rb_eArgError, "html must not be empty");
    }

    if (RSTRING_LEN(path) == 0) {
        rb_raise(rb_eArgError, "path must not be empty");
    }

    if (RSTRING_LEN(html) > INT_MAX) {
        rb_raise(rb_eArgError, "html is too large");
    }

    if (NIL_P(options)) {
        options = rb_hash_new();
    } else if (!RB_TYPE_P(options, T_HASH)) {
        rb_raise(rb_eTypeError, "options must be a Hash");
    }

    keyword_ids[0] = id_base_url;
    keyword_ids[1] = id_page_size;
    keyword_ids[2] = id_margins;
    keyword_ids[3] = id_media;

    rb_get_kwargs(options, keyword_ids, 0, 4, keyword_values);

    base_url_value = keyword_values[0];
    page_size_value = keyword_values[1];
    margins_value = keyword_values[2];
    media_value = keyword_values[3];

    if (base_url_value == Qundef || NIL_P(base_url_value)) {
        base_url_str = "";
    } else {
        if (!RB_TYPE_P(base_url_value, T_STRING)) {
            rb_raise(rb_eTypeError, "base_url must be a String or nil");
        }

        base_url_str = StringValueCStr(base_url_value);
    }

    if (page_size_value != Qundef) {
        page_size = pageprint_page_size_from_value(page_size_value);
    }

    if (margins_value != Qundef) {
        margins = pageprint_margins_from_value(margins_value);
    }

    if (media_value != Qundef) {
        media = pageprint_media_from_value(media_value);
    }

    html_str = RSTRING_PTR(html);
    html_len = RSTRING_LEN(html);
    path_str = StringValueCStr(path);

    /* 1. Create */
    book = plutobook_create(page_size, margins, media);

    if (!book) {
        rb_raise(rb_eRuntimeError, "failed to create plutobook");
    }

    /* 2. Load HTML */
    plutobook_clear_error_message();

    ok = plutobook_load_html(
        book,
        html_str,
        (int)html_len,
        "",     /* user style */
        "",     /* user script */
        base_url_str
    );

    if (!ok) {
        plutobook_destroy(book);
        pageprint_raise_plutobook_error(rb_eRuntimeError, "failed to load HTML into plutobook");
    }

    plutobook_clear_error_message();

    ok = plutobook_write_to_pdf(book, path_str);
    plutobook_destroy(book);

    if (!ok) {
        pageprint_raise_plutobook_error_with_path(rb_eRuntimeError, "failed to write PDF to", path_str);
    }

    return Qtrue;
}

void Init_page_print(void) {
    mPagePrint = rb_define_module("PagePrint");

    id_base_url = rb_intern_const("base_url");
    id_page_size = rb_intern_const("page_size");
    id_margins = rb_intern_const("margins");
    id_media = rb_intern_const("media");

    rb_define_singleton_method(mPagePrint, "html_to_pdf", RUBY_METHOD_FUNC(pageprint_html_to_pdf), -1);
}
