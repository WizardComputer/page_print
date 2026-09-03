# Changelog

## 0.1.11

- Register `PagePrint.render` and `PagePrint.render_to_file` with the original `rb_define_singleton_method` function-pointer API instead of `RUBY_METHOD_FUNC`. That removes a GCC 15 / C23 incompatible-pointer-types error that blocked source builds on Heroku-26, while remaining compatible with older compilers such as GCC 13 on Heroku-24 and macOS clang.
