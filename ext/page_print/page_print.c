#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/thread.h"
#include <limits.h>
#include <stdint.h>
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
static ID id_resource_fetcher;
static ID id_resource_fetcher_ivar;
static ID id_base_url_method;
static ID id_call;
static ID id_content;
static ID id_mime_type;
static ID id_text_encoding;

typedef struct {
    plutobook_page_size_t page_size;
    plutobook_page_margins_t margins;
    plutobook_media_type_t media;
    const char *base_url;
    VALUE resource_fetcher;
} pageprint_options_t;

typedef struct {
    VALUE object;
    int state;
} pageprint_resource_fetcher_t;

typedef struct {
    pageprint_resource_fetcher_t *fetcher;
    const char *url;
    plutobook_resource_data_t *resource;
} pageprint_resource_fetch_args_t;

typedef struct {
    VALUE output;
    int state;
} pageprint_pdf_string_output_t;

typedef struct {
    VALUE output;
    const char *data;
    unsigned int length;
} pageprint_pdf_string_append_t;

typedef struct {
    plutobook_t *book;
    const char *html;
    int length;
    const char *user_style;
    const char *user_script;
    const char *base_url;
    int ok;
} pageprint_load_html_args_t;

typedef struct {
    plutobook_t *book;
    const char *path;
    int ok;
} pageprint_write_pdf_args_t;

typedef struct {
    plutobook_t *book;
    pageprint_pdf_string_output_t *output;
    int ok;
} pageprint_write_pdf_stream_args_t;

static VALUE pageprint_append_pdf_string(VALUE value);
static plutobook_stream_status_t pageprint_write_pdf_string(void *closure, const char *data, unsigned int length);
static plutobook_resource_data_t *pageprint_fetch_resource(void *closure, const char *url);

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

static void *pageprint_load_html_without_gvl(void *ptr)
{
    pageprint_load_html_args_t *args = ptr;

    args->ok = plutobook_load_html(
        args->book,
        args->html,
        args->length,
        args->user_style,
        args->user_script,
        args->base_url
    );

    return NULL;
}

static void *pageprint_write_pdf_without_gvl(void *ptr)
{
    pageprint_write_pdf_args_t *args = ptr;

    args->ok = plutobook_write_to_pdf(args->book, args->path);

    return NULL;
}

static void *pageprint_append_pdf_string_with_gvl(void *ptr)
{
    pageprint_pdf_string_append_t *append = ptr;
    int state = 0;

    rb_protect(pageprint_append_pdf_string, (VALUE)append, &state);

    return (void *)(intptr_t)state;
}

static void *pageprint_write_pdf_stream_without_gvl(void *ptr)
{
    pageprint_write_pdf_stream_args_t *args = ptr;

    args->ok = plutobook_write_to_pdf_stream(args->book, pageprint_write_pdf_string, args->output);

    return NULL;
}

static VALUE pageprint_call_resource_fetcher(VALUE value)
{
    pageprint_resource_fetch_args_t *args = (pageprint_resource_fetch_args_t *)value;
    VALUE url;
    VALUE result;
    VALUE content;
    VALUE mime_type;
    VALUE text_encoding;
    const char *text_encoding_str = "";

    url = rb_str_new_cstr(args->url);
    result = rb_funcall(args->fetcher->object, id_call, 1, url);

    if (NIL_P(result)) {
        return Qnil;
    }

    if (!RB_TYPE_P(result, T_HASH)) {
        rb_raise(rb_eTypeError, "resource_fetcher must return a Hash or nil");
    }

    content = rb_hash_aref(result, ID2SYM(id_content));
    mime_type = rb_hash_aref(result, ID2SYM(id_mime_type));
    text_encoding = rb_hash_aref(result, ID2SYM(id_text_encoding));

    if (!RB_TYPE_P(content, T_STRING)) {
        rb_raise(rb_eTypeError, "resource_fetcher result content must be a String");
    }

    if (!RB_TYPE_P(mime_type, T_STRING)) {
        rb_raise(rb_eTypeError, "resource_fetcher result mime_type must be a String");
    }

    if (!NIL_P(text_encoding)) {
        if (!RB_TYPE_P(text_encoding, T_STRING)) {
            rb_raise(rb_eTypeError, "resource_fetcher result text_encoding must be a String or nil");
        }

        text_encoding_str = StringValueCStr(text_encoding);
    }

    if (RSTRING_LEN(content) > UINT_MAX) {
        rb_raise(rb_eArgError, "resource_fetcher result content is too large");
    }

    args->resource = plutobook_resource_data_create(
        RSTRING_PTR(content),
        (unsigned int)RSTRING_LEN(content),
        StringValueCStr(mime_type),
        text_encoding_str
    );

    if (!args->resource) {
        pageprint_raise_plutobook_error(rb_eRuntimeError, "failed to create resource data");
    }

    return Qnil;
}

static void *pageprint_call_resource_fetcher_with_gvl(void *ptr)
{
    pageprint_resource_fetch_args_t *args = ptr;
    int state = 0;

    rb_protect(pageprint_call_resource_fetcher, (VALUE)args, &state);

    return (void *)(intptr_t)state;
}

static plutobook_resource_data_t *pageprint_fetch_resource(void *closure, const char *url)
{
    pageprint_resource_fetcher_t *fetcher = closure;
    pageprint_resource_fetch_args_t args;
    int state;

    args.fetcher = fetcher;
    args.url = url;
    args.resource = NULL;

    state = (int)(intptr_t)rb_thread_call_with_gvl(pageprint_call_resource_fetcher_with_gvl, &args);

    if (state) {
        fetcher->state = state;
        plutobook_set_error_message("failed to fetch URL '%s'", url);
        return NULL;
    }

    if (args.resource) {
        return args.resource;
    }

    return plutobook_fetch_url(url);
}

static pageprint_options_t pageprint_options_from_value(VALUE options)
{
    pageprint_options_t result;
    VALUE base_url_value;
    VALUE page_size_value;
    VALUE margins_value;
    VALUE media_value;
    VALUE resource_fetcher_value;
    VALUE keyword_values[5];
    ID keyword_ids[5];

    result.page_size = PLUTOBOOK_PAGE_SIZE_A4;
    result.margins = PLUTOBOOK_PAGE_MARGINS_NORMAL;
    result.media = PLUTOBOOK_MEDIA_TYPE_PRINT;
    result.base_url = "";
    result.resource_fetcher = Qnil;

    if (NIL_P(options)) {
        options = rb_hash_new();
    } else if (!RB_TYPE_P(options, T_HASH)) {
        rb_raise(rb_eTypeError, "options must be a Hash");
    }

    keyword_ids[0] = id_base_url;
    keyword_ids[1] = id_page_size;
    keyword_ids[2] = id_margins;
    keyword_ids[3] = id_media;
    keyword_ids[4] = id_resource_fetcher;

    rb_get_kwargs(options, keyword_ids, 0, 5, keyword_values);

    base_url_value = keyword_values[0];
    page_size_value = keyword_values[1];
    margins_value = keyword_values[2];
    media_value = keyword_values[3];
    resource_fetcher_value = keyword_values[4];

    if (base_url_value == Qundef) {
        base_url_value = rb_funcall(mPagePrint, id_base_url_method, 0);
    }

    if (!NIL_P(base_url_value)) {
        if (!RB_TYPE_P(base_url_value, T_STRING)) {
            rb_raise(rb_eTypeError, "base_url must be a String or nil");
        }

        result.base_url = StringValueCStr(base_url_value);
    }

    if (page_size_value != Qundef) {
        result.page_size = pageprint_page_size_from_value(page_size_value);
    }

    if (margins_value != Qundef) {
        result.margins = pageprint_margins_from_value(margins_value);
    }

    if (media_value != Qundef) {
        result.media = pageprint_media_from_value(media_value);
    }

    if (resource_fetcher_value == Qundef) {
        resource_fetcher_value = rb_ivar_get(mPagePrint, id_resource_fetcher_ivar);
    }

    if (!NIL_P(resource_fetcher_value) && resource_fetcher_value != Qfalse) {
        if (!rb_respond_to(resource_fetcher_value, id_call)) {
            rb_raise(rb_eTypeError, "resource_fetcher must respond to call or be nil/false");
        }

        result.resource_fetcher = resource_fetcher_value;
    }

    return result;
}

static plutobook_t *pageprint_create_book_from_html(VALUE html, VALUE options, pageprint_resource_fetcher_t *resource_fetcher)
{
    pageprint_options_t pageprint_options;

    const char *html_str;
    long html_len;

    plutobook_t *book;
    pageprint_load_html_args_t load_args;

    if (!RB_TYPE_P(html, T_STRING)) {
        rb_raise(rb_eTypeError, "html must be a String");
    }

    if (RSTRING_LEN(html) == 0) {
        rb_raise(rb_eArgError, "html must not be empty");
    }

    if (RSTRING_LEN(html) > INT_MAX) {
        rb_raise(rb_eArgError, "html is too large");
    }

    pageprint_options = pageprint_options_from_value(options);

    html_str = RSTRING_PTR(html);
    html_len = RSTRING_LEN(html);

    /* 1. Create */
    book = plutobook_create(pageprint_options.page_size, pageprint_options.margins, pageprint_options.media);

    if (!book) {
        rb_raise(rb_eRuntimeError, "failed to create plutobook");
    }

    resource_fetcher->object = pageprint_options.resource_fetcher;
    resource_fetcher->state = 0;

    if (!NIL_P(resource_fetcher->object)) {
        plutobook_set_custom_resource_fetcher(book, pageprint_fetch_resource, resource_fetcher);
    }

    /* 2. Load HTML */
    plutobook_clear_error_message();

    load_args.book = book;
    load_args.html = html_str;
    load_args.length = (int)html_len;
    load_args.user_style = "";
    load_args.user_script = "";
    load_args.base_url = pageprint_options.base_url;
    load_args.ok = 0;

    rb_thread_call_without_gvl(
        pageprint_load_html_without_gvl,
        &load_args,
        RUBY_UBF_IO,
        NULL
    );

    if (!load_args.ok) {
        plutobook_destroy(book);

        if (resource_fetcher->state) {
            rb_jump_tag(resource_fetcher->state);
        }

        pageprint_raise_plutobook_error(rb_eRuntimeError, "failed to load HTML into plutobook");
    }

    if (resource_fetcher->state) {
        plutobook_destroy(book);
        rb_jump_tag(resource_fetcher->state);
    }

    return book;
}

static VALUE pageprint_append_pdf_string(VALUE value)
{
    pageprint_pdf_string_append_t *append = (pageprint_pdf_string_append_t *)value;

    rb_str_cat(append->output, append->data, append->length);

    return Qnil;
}

static plutobook_stream_status_t pageprint_write_pdf_string(void *closure, const char *data, unsigned int length)
{
    pageprint_pdf_string_output_t *output = closure;
    pageprint_pdf_string_append_t append;
    int state;

    append.output = output->output;
    append.data = data;
    append.length = length;

    state = (int)(intptr_t)rb_thread_call_with_gvl(pageprint_append_pdf_string_with_gvl, &append);

    if (state) {
        output->state = state;
        return PLUTOBOOK_STREAM_STATUS_WRITE_ERROR;
    }

    return PLUTOBOOK_STREAM_STATUS_SUCCESS;
}

static VALUE pageprint_html_to_pdf(int argc, VALUE *argv, VALUE self) {
    VALUE html;
    VALUE path;
    VALUE options;

    const char *path_str;

    plutobook_t *book;
    pageprint_resource_fetcher_t resource_fetcher;
    pageprint_write_pdf_args_t write_args;

    rb_check_arity(argc, 2, 3);

    html = argv[0];
    path = argv[1];
    options = argc == 3 ? argv[2] : Qnil;

    if (!RB_TYPE_P(path, T_STRING)) {
        rb_raise(rb_eTypeError, "path must be a String");
    }

    if (RSTRING_LEN(path) == 0) {
        rb_raise(rb_eArgError, "path must not be empty");
    }

    path_str = StringValueCStr(path);

    book = pageprint_create_book_from_html(html, options, &resource_fetcher);

    plutobook_clear_error_message();

    write_args.book = book;
    write_args.path = path_str;
    write_args.ok = 0;

    rb_thread_call_without_gvl(
        pageprint_write_pdf_without_gvl,
        &write_args,
        RUBY_UBF_IO,
        NULL
    );

    plutobook_destroy(book);

    if (resource_fetcher.state) {
        rb_jump_tag(resource_fetcher.state);
    }

    if (!write_args.ok) {
        pageprint_raise_plutobook_error_with_path(rb_eRuntimeError, "failed to write PDF to", path_str);
    }

    RB_GC_GUARD(resource_fetcher.object);

    return Qtrue;
}

static VALUE pageprint_html_to_pdf_string(int argc, VALUE *argv, VALUE self) {
    VALUE html;
    VALUE options;
    pageprint_pdf_string_output_t output;

    plutobook_t *book;
    pageprint_resource_fetcher_t resource_fetcher;
    pageprint_write_pdf_stream_args_t write_args;

    rb_check_arity(argc, 1, 2);

    html = argv[0];
    options = argc == 2 ? argv[1] : Qnil;
    output.output = rb_str_new(NULL, 0);
    output.state = 0;
    rb_enc_associate_index(output.output, rb_ascii8bit_encindex());

    book = pageprint_create_book_from_html(html, options, &resource_fetcher);

    plutobook_clear_error_message();

    write_args.book = book;
    write_args.output = &output;
    write_args.ok = 0;

    rb_thread_call_without_gvl(
        pageprint_write_pdf_stream_without_gvl,
        &write_args,
        RUBY_UBF_IO,
        NULL
    );

    plutobook_destroy(book);

    if (resource_fetcher.state) {
        rb_jump_tag(resource_fetcher.state);
    }

    if (output.state) {
        rb_jump_tag(output.state);
    }

    if (!write_args.ok) {
        pageprint_raise_plutobook_error(rb_eRuntimeError, "failed to write PDF to string");
    }

    RB_GC_GUARD(resource_fetcher.object);
    RB_GC_GUARD(output.output);

    return output.output;
}

void Init_page_print(void) {
    mPagePrint = rb_define_module("PagePrint");

    id_base_url = rb_intern_const("base_url");
    id_page_size = rb_intern_const("page_size");
    id_margins = rb_intern_const("margins");
    id_media = rb_intern_const("media");
    id_resource_fetcher = rb_intern_const("resource_fetcher");
    id_resource_fetcher_ivar = rb_intern_const("@resource_fetcher");
    id_base_url_method = rb_intern_const("base_url");
    id_call = rb_intern_const("call");
    id_content = rb_intern_const("content");
    id_mime_type = rb_intern_const("mime_type");
    id_text_encoding = rb_intern_const("text_encoding");

    rb_define_singleton_method(mPagePrint, "html_to_pdf", RUBY_METHOD_FUNC(pageprint_html_to_pdf), -1);
    rb_define_singleton_method(mPagePrint, "html_to_pdf_string", RUBY_METHOD_FUNC(pageprint_html_to_pdf_string), -1);
}
