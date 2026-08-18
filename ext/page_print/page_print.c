#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/thread.h"
#include <limits.h>
#include <stdint.h>
#include <string.h>
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
static ID id_metadata;
static ID id_width;
static ID id_height;
static ID id_unit;
static ID id_top;
static ID id_right;
static ID id_bottom;
static ID id_left;
static ID id_resource_fetcher_ivar;
static ID id_base_url_method;
static ID id_call;
static ID id_content;
static ID id_mime_type;
static ID id_text_encoding;
static ID id_title;
static ID id_author;
static ID id_subject;
static ID id_keywords;
static ID id_creation_date;
static ID id_modification_date;
static ID id_pt;
static ID id_pc;
static ID id_in;
static ID id_cm;
static ID id_mm;
static ID id_px;

typedef struct {
    plutobook_page_size_t page_size;
    plutobook_page_margins_t margins;
    plutobook_media_type_t media;
    VALUE base_url;
    VALUE resource_fetcher;
    VALUE metadata;
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

typedef struct {
    plutobook_t *book;
    VALUE metadata;
} pageprint_apply_metadata_args_t;

typedef struct {
    plutobook_t *book;
    VALUE html;
    VALUE base_url;
    VALUE resource_fetcher;
    VALUE metadata;
    pageprint_resource_fetcher_t resource_fetcher_state;
} pageprint_book_context_t;

typedef struct {
    pageprint_book_context_t book_context;
    VALUE html;
    VALUE path;
    VALUE options;
} pageprint_render_to_file_context_t;

typedef struct {
    pageprint_book_context_t book_context;
    VALUE html;
    VALUE options;
    pageprint_pdf_string_output_t output;
} pageprint_render_context_t;

static VALUE pageprint_append_pdf_string(VALUE value);
static plutobook_stream_status_t pageprint_write_pdf_string(void *closure, const char *data, unsigned int length);
static plutobook_resource_data_t *pageprint_fetch_resource(void *closure, const char *url);

static void pageprint_reject_embedded_nul(VALUE value, const char *name)
{
    if (memchr(RSTRING_PTR(value), '\0', (size_t)RSTRING_LEN(value))) {
        rb_raise(rb_eArgError, "%s must not contain NUL bytes", name);
    }
}

static VALUE pageprint_frozen_string_copy(VALUE value)
{
    VALUE copy = rb_str_dup(value);

    rb_obj_freeze(copy);

    return copy;
}

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

static double pageprint_unit_factor_from_value(VALUE value, const char *name)
{
    ID value_id;

    if (!RB_SYMBOL_P(value)) {
        rb_raise(rb_eTypeError, "%s must be a Symbol", name);
    }

    value_id = SYM2ID(value);

    if (value_id == id_pt) return PLUTOBOOK_UNITS_PT;
    if (value_id == id_pc) return PLUTOBOOK_UNITS_PC;
    if (value_id == id_in) return PLUTOBOOK_UNITS_IN;
    if (value_id == id_cm) return PLUTOBOOK_UNITS_CM;
    if (value_id == id_mm) return PLUTOBOOK_UNITS_MM;
    if (value_id == id_px) return PLUTOBOOK_UNITS_PX;

    rb_raise(rb_eArgError, "%s must be one of: :pt, :pc, :in, :cm, :mm, :px", name);
}

static plutobook_page_size_t pageprint_page_size_from_value(VALUE value)
{
    ID value_id;

    if (RB_TYPE_P(value, T_HASH)) {
        VALUE width = rb_hash_aref(value, ID2SYM(id_width));
        VALUE height = rb_hash_aref(value, ID2SYM(id_height));
        VALUE unit = rb_hash_aref(value, ID2SYM(id_unit));
        double width_number;
        double height_number;
        double factor;

        if (NIL_P(width)) {
            rb_raise(rb_eArgError, "page_size requires :width");
        }

        if (NIL_P(height)) {
            rb_raise(rb_eArgError, "page_size requires :height");
        }

        if (NIL_P(unit)) {
            rb_raise(rb_eArgError, "page_size requires :unit");
        }

        width_number = NUM2DBL(width);
        height_number = NUM2DBL(height);

        if (width_number <= 0) {
            rb_raise(rb_eArgError, "page_size width must be greater than 0");
        }

        if (height_number <= 0) {
            rb_raise(rb_eArgError, "page_size height must be greater than 0");
        }

        factor = pageprint_unit_factor_from_value(unit, "page_size unit");

        return PLUTOBOOK_MAKE_PAGE_SIZE((float)(width_number * factor), (float)(height_number * factor));
    }

    if (!RB_SYMBOL_P(value)) {
        rb_raise(rb_eTypeError, "page_size must be a Symbol or Hash");
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

    if (RB_TYPE_P(value, T_HASH)) {
        VALUE top = rb_hash_aref(value, ID2SYM(id_top));
        VALUE right = rb_hash_aref(value, ID2SYM(id_right));
        VALUE bottom = rb_hash_aref(value, ID2SYM(id_bottom));
        VALUE left = rb_hash_aref(value, ID2SYM(id_left));
        VALUE unit = rb_hash_aref(value, ID2SYM(id_unit));
        double top_number;
        double right_number;
        double bottom_number;
        double left_number;
        double factor;

        if (NIL_P(top)) {
            rb_raise(rb_eArgError, "margins requires :top");
        }

        if (NIL_P(right)) {
            rb_raise(rb_eArgError, "margins requires :right");
        }

        if (NIL_P(bottom)) {
            rb_raise(rb_eArgError, "margins requires :bottom");
        }

        if (NIL_P(left)) {
            rb_raise(rb_eArgError, "margins requires :left");
        }

        if (NIL_P(unit)) {
            rb_raise(rb_eArgError, "margins requires :unit");
        }

        top_number = NUM2DBL(top);
        right_number = NUM2DBL(right);
        bottom_number = NUM2DBL(bottom);
        left_number = NUM2DBL(left);

        if (top_number < 0 || right_number < 0 || bottom_number < 0 || left_number < 0) {
            rb_raise(rb_eArgError, "margins values must be greater than or equal to 0");
        }

        factor = pageprint_unit_factor_from_value(unit, "margins unit");

        return PLUTOBOOK_MAKE_PAGE_MARGINS(
            (float)(top_number * factor),
            (float)(right_number * factor),
            (float)(bottom_number * factor),
            (float)(left_number * factor)
        );
    }

    if (!RB_SYMBOL_P(value)) {
        rb_raise(rb_eTypeError, "margins must be a Symbol or Hash");
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

static int pageprint_metadata_id_known(ID key_id)
{
    return key_id == id_title ||
           key_id == id_author ||
           key_id == id_subject ||
           key_id == id_keywords ||
           key_id == id_creation_date ||
           key_id == id_modification_date;
}

static void pageprint_validate_metadata_key(VALUE key)
{
    ID key_id;

    if (!RB_SYMBOL_P(key)) {
        rb_raise(rb_eTypeError, "metadata keys must be Symbols");
    }

    key_id = SYM2ID(key);

    if (!pageprint_metadata_id_known(key_id)) {
        rb_raise(rb_eArgError, "metadata contains unknown key: :%s", rb_id2name(key_id));
    }
}

static void pageprint_validate_metadata(VALUE metadata)
{
    VALUE keys;
    long i;

    if (NIL_P(metadata)) {
        return;
    }

    if (!RB_TYPE_P(metadata, T_HASH)) {
        rb_raise(rb_eTypeError, "metadata must be a Hash or nil");
    }

    keys = rb_funcall(metadata, rb_intern("keys"), 0);

    for (i = 0; i < RARRAY_LEN(keys); i++) {
        VALUE key = rb_ary_entry(keys, i);
        VALUE value;

        pageprint_validate_metadata_key(key);

        value = rb_hash_aref(metadata, key);

        if (!NIL_P(value) && !RB_TYPE_P(value, T_STRING)) {
            rb_raise(rb_eTypeError, "metadata values must be Strings or nil");
        }
    }
}

static void pageprint_set_metadata_value(plutobook_t *book, VALUE metadata, ID key_id, plutobook_pdf_metadata_t metadata_key)
{
    VALUE value;

    value = rb_hash_aref(metadata, ID2SYM(key_id));

    if (NIL_P(value)) {
        return;
    }

    plutobook_set_metadata(book, metadata_key, StringValueCStr(value));
}

static void pageprint_apply_metadata(plutobook_t *book, VALUE metadata)
{
    if (NIL_P(metadata)) {
        return;
    }

    pageprint_set_metadata_value(book, metadata, id_title, PLUTOBOOK_PDF_METADATA_TITLE);
    pageprint_set_metadata_value(book, metadata, id_author, PLUTOBOOK_PDF_METADATA_AUTHOR);
    pageprint_set_metadata_value(book, metadata, id_subject, PLUTOBOOK_PDF_METADATA_SUBJECT);
    pageprint_set_metadata_value(book, metadata, id_keywords, PLUTOBOOK_PDF_METADATA_KEYWORDS);
    pageprint_set_metadata_value(book, metadata, id_creation_date, PLUTOBOOK_PDF_METADATA_CREATION_DATE);
    pageprint_set_metadata_value(book, metadata, id_modification_date, PLUTOBOOK_PDF_METADATA_MODIFICATION_DATE);
}

static VALUE pageprint_apply_metadata_with_gvl(VALUE ptr)
{
    pageprint_apply_metadata_args_t *args = (pageprint_apply_metadata_args_t *)ptr;

    pageprint_apply_metadata(args->book, args->metadata);

    return Qnil;
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

    if (!NIL_P(fetcher->object)) {
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
    }

    plutobook_set_error_message("network fetch disabled for URL '%s'", url);
    return NULL;
}

static pageprint_options_t pageprint_options_from_value(VALUE options)
{
    pageprint_options_t result;
    VALUE base_url_value;
    VALUE page_size_value;
    VALUE margins_value;
    VALUE media_value;
    VALUE resource_fetcher_value;
    VALUE metadata_value;
    VALUE keyword_values[6];
    ID keyword_ids[6];

    result.page_size = PLUTOBOOK_PAGE_SIZE_A4;
    result.margins = PLUTOBOOK_PAGE_MARGINS_NORMAL;
    result.media = PLUTOBOOK_MEDIA_TYPE_PRINT;
    result.base_url = Qnil;
    result.resource_fetcher = Qnil;
    result.metadata = Qnil;

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
    keyword_ids[5] = id_metadata;

    rb_get_kwargs(options, keyword_ids, 0, 6, keyword_values);

    base_url_value = keyword_values[0];
    page_size_value = keyword_values[1];
    margins_value = keyword_values[2];
    media_value = keyword_values[3];
    resource_fetcher_value = keyword_values[4];
    metadata_value = keyword_values[5];

    if (base_url_value == Qundef) {
        base_url_value = rb_funcall(mPagePrint, id_base_url_method, 0);
    }

    if (!NIL_P(base_url_value)) {
        if (!RB_TYPE_P(base_url_value, T_STRING)) {
            rb_raise(rb_eTypeError, "base_url must be a String or nil");
        }

        result.base_url = base_url_value;
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

    if (metadata_value != Qundef) {
        pageprint_validate_metadata(metadata_value);
        result.metadata = metadata_value;
    }

    return result;
}

static void pageprint_create_book_from_html(VALUE html, VALUE options, pageprint_book_context_t *context)
{
    pageprint_options_t pageprint_options;
    const char *base_url_str;
    long html_len;
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

    pageprint_reject_embedded_nul(html, "html");
    pageprint_options = pageprint_options_from_value(options);
    context->html = pageprint_frozen_string_copy(html);
    context->base_url = Qnil;
    context->resource_fetcher = pageprint_options.resource_fetcher;
    context->metadata = pageprint_options.metadata;

    if (!NIL_P(pageprint_options.base_url)) {
        pageprint_reject_embedded_nul(pageprint_options.base_url, "base_url");
        context->base_url = pageprint_frozen_string_copy(pageprint_options.base_url);
    }

    html_len = RSTRING_LEN(context->html);

    /* 1. Create */
    context->book = plutobook_create(pageprint_options.page_size, pageprint_options.margins, pageprint_options.media);

    if (!context->book) {
        rb_raise(rb_eRuntimeError, "failed to create plutobook");
    }

    context->resource_fetcher_state.object = context->resource_fetcher;
    context->resource_fetcher_state.state = 0;

    plutobook_set_custom_resource_fetcher(context->book, pageprint_fetch_resource, &context->resource_fetcher_state);

    /* 2. Load HTML */
    plutobook_clear_error_message();

    base_url_str = "";
    if (!NIL_P(context->base_url)) {
        base_url_str = RSTRING_PTR(context->base_url);
    }

    load_args.book = context->book;
    load_args.html = RSTRING_PTR(context->html);
    load_args.length = (int)html_len;
    load_args.user_style = "";
    load_args.user_script = "";
    load_args.base_url = base_url_str;
    load_args.ok = 0;

    rb_thread_call_without_gvl(
        pageprint_load_html_without_gvl,
        &load_args,
        RUBY_UBF_IO,
        NULL
    );

    RB_GC_GUARD(context->html);
    RB_GC_GUARD(context->base_url);

    if (!load_args.ok) {
        if (context->resource_fetcher_state.state) {
            rb_jump_tag(context->resource_fetcher_state.state);
        }

        pageprint_raise_plutobook_error(rb_eRuntimeError, "failed to load HTML into plutobook");
    }

    if (context->resource_fetcher_state.state) {
        rb_jump_tag(context->resource_fetcher_state.state);
    }

    {
        pageprint_apply_metadata_args_t metadata_args;
        int metadata_state = 0;

        metadata_args.book = context->book;
        metadata_args.metadata = context->metadata;

        rb_protect(pageprint_apply_metadata_with_gvl, (VALUE)&metadata_args, &metadata_state);
        RB_GC_GUARD(context->metadata);

        if (metadata_state) {
            rb_jump_tag(metadata_state);
        }
    }
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

static VALUE pageprint_destroy_book(VALUE value)
{
    pageprint_book_context_t *context = (pageprint_book_context_t *)value;
    plutobook_t *book = context->book;

    context->book = NULL;

    if (book) {
        plutobook_destroy(book);
    }

    return Qnil;
}

static VALUE pageprint_render_to_file_body(VALUE value)
{
    pageprint_render_to_file_context_t *context = (pageprint_render_to_file_context_t *)value;
    const char *path_str;
    pageprint_write_pdf_args_t write_args;

    pageprint_create_book_from_html(context->html, context->options, &context->book_context);
    path_str = RSTRING_PTR(context->path);

    plutobook_clear_error_message();

    write_args.book = context->book_context.book;
    write_args.path = path_str;
    write_args.ok = 0;

    rb_thread_call_without_gvl(
        pageprint_write_pdf_without_gvl,
        &write_args,
        RUBY_UBF_IO,
        NULL
    );

    RB_GC_GUARD(context->path);
    RB_GC_GUARD(context->book_context.resource_fetcher);
    RB_GC_GUARD(context->html);
    RB_GC_GUARD(context->options);

    if (context->book_context.resource_fetcher_state.state) {
        rb_jump_tag(context->book_context.resource_fetcher_state.state);
    }

    if (!write_args.ok) {
        pageprint_raise_plutobook_error_with_path(rb_eRuntimeError, "failed to write PDF to", path_str);
    }

    return Qtrue;
}

static VALUE pageprint_render_to_file(int argc, VALUE *argv, VALUE self)
{
    pageprint_render_to_file_context_t context = { 0 };

    rb_check_arity(argc, 2, 3);

    context.html = argv[0];
    context.options = argc == 3 ? argv[2] : Qnil;

    if (!RB_TYPE_P(argv[1], T_STRING)) {
        rb_raise(rb_eTypeError, "path must be a String");
    }

    if (RSTRING_LEN(argv[1]) == 0) {
        rb_raise(rb_eArgError, "path must not be empty");
    }

    pageprint_reject_embedded_nul(argv[1], "path");
    context.path = pageprint_frozen_string_copy(argv[1]);

    return rb_ensure(pageprint_render_to_file_body, (VALUE)&context, pageprint_destroy_book, (VALUE)&context.book_context);
}

static VALUE pageprint_render_body(VALUE value)
{
    pageprint_render_context_t *context = (pageprint_render_context_t *)value;
    pageprint_write_pdf_stream_args_t write_args;

    pageprint_create_book_from_html(context->html, context->options, &context->book_context);

    plutobook_clear_error_message();

    write_args.book = context->book_context.book;
    write_args.output = &context->output;
    write_args.ok = 0;

    rb_thread_call_without_gvl(
        pageprint_write_pdf_stream_without_gvl,
        &write_args,
        RUBY_UBF_IO,
        NULL
    );

    RB_GC_GUARD(context->book_context.resource_fetcher);
    RB_GC_GUARD(context->output.output);
    RB_GC_GUARD(context->html);
    RB_GC_GUARD(context->options);

    if (context->book_context.resource_fetcher_state.state) {
        rb_jump_tag(context->book_context.resource_fetcher_state.state);
    }

    if (context->output.state) {
        rb_jump_tag(context->output.state);
    }

    if (!write_args.ok) {
        pageprint_raise_plutobook_error(rb_eRuntimeError, "failed to write PDF to string");
    }

    return context->output.output;
}

static VALUE pageprint_render(int argc, VALUE *argv, VALUE self)
{
    pageprint_render_context_t context = { 0 };

    rb_check_arity(argc, 1, 2);

    context.html = argv[0];
    context.options = argc == 2 ? argv[1] : Qnil;
    context.output.output = rb_str_new(NULL, 0);
    context.output.state = 0;
    rb_enc_associate_index(context.output.output, rb_ascii8bit_encindex());

    return rb_ensure(pageprint_render_body, (VALUE)&context, pageprint_destroy_book, (VALUE)&context.book_context);
}

void Init_page_print(void) {
    mPagePrint = rb_define_module("PagePrint");

    id_base_url = rb_intern_const("base_url");
    id_page_size = rb_intern_const("page_size");
    id_margins = rb_intern_const("margins");
    id_media = rb_intern_const("media");
    id_resource_fetcher = rb_intern_const("resource_fetcher");
    id_metadata = rb_intern_const("metadata");
    id_width = rb_intern_const("width");
    id_height = rb_intern_const("height");
    id_unit = rb_intern_const("unit");
    id_top = rb_intern_const("top");
    id_right = rb_intern_const("right");
    id_bottom = rb_intern_const("bottom");
    id_left = rb_intern_const("left");
    id_resource_fetcher_ivar = rb_intern_const("@resource_fetcher");
    id_base_url_method = rb_intern_const("base_url");
    id_call = rb_intern_const("call");
    id_content = rb_intern_const("content");
    id_mime_type = rb_intern_const("mime_type");
    id_text_encoding = rb_intern_const("text_encoding");
    id_title = rb_intern_const("title");
    id_author = rb_intern_const("author");
    id_subject = rb_intern_const("subject");
    id_keywords = rb_intern_const("keywords");
    id_creation_date = rb_intern_const("creation_date");
    id_modification_date = rb_intern_const("modification_date");
    id_pt = rb_intern_const("pt");
    id_pc = rb_intern_const("pc");
    id_in = rb_intern_const("in");
    id_cm = rb_intern_const("cm");
    id_mm = rb_intern_const("mm");
    id_px = rb_intern_const("px");

    rb_define_singleton_method(mPagePrint, "render_to_file", RUBY_METHOD_FUNC(pageprint_render_to_file), -1);
    rb_define_singleton_method(mPagePrint, "render", RUBY_METHOD_FUNC(pageprint_render), -1);
}
