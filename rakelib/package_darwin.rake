require "fileutils"
require "bundler"
require "rbconfig"
require "shellwords"

PAGE_PRINT_PLUTOBOOK_VERSION = "v0.19.0" unless defined?(PAGE_PRINT_PLUTOBOOK_VERSION)
PAGE_PRINT_DARWIN_PLATFORM = "arm64-darwin"
PAGE_PRINT_DARWIN_SYSTEM_PREFIXES = [
  "/System/Library/",
  "/usr/lib/"
].freeze
PAGE_PRINT_DARWIN_EXCLUDED_LIBRARIES = %w[
  libruby.
].freeze

namespace :package do
  desc "Build a precompiled Apple Silicon macOS gem with vendored PlutoBook"
  task :darwin_arm64 do
    abort "package:darwin_arm64 currently supports arm64 macOS only" unless darwin_arm64?

    root = File.expand_path("..", __dir__)
    vendor_dir = File.join(root, "lib", "page_print", "vendor", PAGE_PRINT_DARWIN_PLATFORM)
    plutobook_source_dir = File.join(root, "tmp", "plutobook-src-darwin")
    plutobook_build_dir = File.join(root, "tmp", "plutobook-build-darwin")
    plutobook_install_dir = File.join(root, "tmp", "plutobook-install", PAGE_PRINT_DARWIN_PLATFORM)

    FileUtils.rm_rf(plutobook_source_dir)
    FileUtils.rm_rf(plutobook_build_dir)
    FileUtils.rm_rf(plutobook_install_dir)
    FileUtils.rm_rf(vendor_dir)
    FileUtils.mkdir_p(File.dirname(plutobook_source_dir))
    FileUtils.mkdir_p(File.join(root, "pkg"))

    sh "git clone --depth 1 --branch #{PAGE_PRINT_PLUTOBOOK_VERSION.shellescape} https://github.com/plutoprint/plutobook.git #{plutobook_source_dir.shellescape}"
    sh "meson setup #{plutobook_build_dir.shellescape} #{plutobook_source_dir.shellescape} --prefix=#{plutobook_install_dir.shellescape} --libdir=lib --buildtype=release -Dcurl=disabled -Dturbojpeg=disabled -Dwebp=disabled -Dtools=disabled -Dtests=disabled -Dexamples=disabled"
    sh "meson compile -C #{plutobook_build_dir.shellescape}"
    sh "meson install -C #{plutobook_build_dir.shellescape}"

    FileUtils.mkdir_p(vendor_dir)
    FileUtils.cp_r(File.join(plutobook_install_dir, "include"), vendor_dir)
    FileUtils.cp_r(File.join(plutobook_install_dir, "lib"), vendor_dir)
    materialize_darwin_symlinks(File.join(vendor_dir, "lib"))

    ENV["PAGE_PRINT_VENDOR_PLATFORM"] = PAGE_PRINT_DARWIN_PLATFORM
    Rake::Task["clean"].invoke if Rake::Task.task_defined?("clean")
    Rake::Task["compile"].invoke

    extension_path = File.join(root, "lib", "page_print", "page_print.bundle")
    vendor_lib_dir = File.join(vendor_dir, "lib")
    vendor_darwin_shared_libraries(extension_path, vendor_lib_dir)
    patch_darwin_install_names(extension_path, vendor_lib_dir)
    sign_darwin_binaries(extension_path, vendor_lib_dir)
    verify_darwin_code_signatures(extension_path, vendor_lib_dir)
    verify_no_missing_darwin_libraries(extension_path, vendor_lib_dir)
    FileUtils.rm_f(extension_path)

    Bundler.with_unbundled_env do
      sh({ "PAGE_PRINT_VENDOR_ONLY" => "1", "PAGE_PRINT_PRECOMPILED_PLATFORM" => PAGE_PRINT_DARWIN_PLATFORM }, "gem build page_print.gemspec")
    end

    gem_path = Dir.glob(File.join(root, "page_print-*-#{PAGE_PRINT_DARWIN_PLATFORM}.gem")).max_by { |path| File.mtime(path) }
    abort "gem build failed" unless gem_path && File.file?(gem_path)

    FileUtils.mv(gem_path, File.join(root, "pkg", File.basename(gem_path)), force: true)
  end
end

def darwin_arm64?
  RbConfig::CONFIG.fetch("host_os").include?("darwin") && RbConfig::CONFIG.fetch("host_cpu") == "arm64"
end

def vendor_darwin_shared_libraries(extension_path, vendor_lib_dir)
  queue = [ extension_path, *Dir.glob(File.join(vendor_lib_dir, "*.dylib")) ]
  seen = {}
  source_paths = { extension_path => extension_path }

  until queue.empty?
    binary = queue.shift
    next if seen[binary]

    seen[binary] = true

    darwin_libraries_for(binary).each do |library_path|
      next if darwin_system_library?(library_path)
      next if darwin_excluded_library?(library_path)

      resolved_path = resolve_darwin_library_path(library_path, binary, vendor_lib_dir, source_paths)
      next unless resolved_path

      target_path = File.join(vendor_lib_dir, File.basename(library_path))

      unless File.exist?(target_path)
        File.binwrite(target_path, File.binread(File.realpath(resolved_path)))
        FileUtils.chmod(0o755, target_path)
      end

      source_paths[target_path] = resolved_path
      queue << target_path
    end
  end
end

def materialize_darwin_symlinks(vendor_lib_dir)
  Dir.glob(File.join(vendor_lib_dir, "*.dylib")).each do |library_path|
    next unless File.symlink?(library_path)

    real_path = File.realpath(library_path)
    FileUtils.rm(library_path)
    File.binwrite(library_path, File.binread(real_path))
    FileUtils.chmod(0o755, library_path)
  end
end

def patch_darwin_install_names(extension_path, vendor_lib_dir)
  vendor_libraries = Dir.glob(File.join(vendor_lib_dir, "*.dylib"))
  all_binaries = [ extension_path, *vendor_libraries ]

  add_darwin_rpath(extension_path, "@loader_path/vendor/#{PAGE_PRINT_DARWIN_PLATFORM}/lib")
  vendor_libraries.each do |library_path|
    sh "install_name_tool -id @rpath/#{File.basename(library_path).shellescape} #{library_path.shellescape}"
    add_darwin_rpath(library_path, "@loader_path")
  end

  all_binaries.each do |binary|
    darwin_libraries_for(binary).each do |library_path|
      next if darwin_system_library?(library_path)
      next if darwin_excluded_library?(library_path)

      vendored_path = File.join(vendor_lib_dir, File.basename(library_path))
      next unless File.exist?(vendored_path)

      new_path = "@rpath/#{File.basename(library_path)}"
      next if library_path == new_path

      sh "install_name_tool -change #{library_path.shellescape} #{new_path.shellescape} #{binary.shellescape}"
    end
  end
end

def add_darwin_rpath(binary, rpath)
  return if darwin_rpaths_for(binary).include?(rpath)

  sh "install_name_tool -add_rpath #{rpath.shellescape} #{binary.shellescape}"
end

def sign_darwin_binaries(extension_path, vendor_lib_dir)
  [extension_path, *Dir.glob(File.join(vendor_lib_dir, "*.dylib"))].each do |binary|
    sh "codesign --force --sign - #{binary.shellescape}"
  end
end

def verify_darwin_code_signatures(extension_path, vendor_lib_dir)
  [extension_path, *Dir.glob(File.join(vendor_lib_dir, "*.dylib"))].each do |binary|
    sh "codesign --verify --strict #{binary.shellescape}"
  end
end

def verify_no_missing_darwin_libraries(extension_path, vendor_lib_dir)
  vendored_names = Dir.glob(File.join(vendor_lib_dir, "*.dylib")).map { |path| File.basename(path) }

  [ extension_path, *Dir.glob(File.join(vendor_lib_dir, "*.dylib")) ].each do |binary|
    darwin_libraries_for(binary).each do |library_path|
      next if darwin_system_library?(library_path)
      next if darwin_excluded_library?(library_path)
      next if library_path.start_with?("@rpath/") && vendored_names.include?(library_path.delete_prefix("@rpath/"))
      next if library_path.start_with?("@loader_path/") && resolve_darwin_library_path(library_path, binary, vendor_lib_dir, {})

      abort "Unvendored macOS shared library for #{binary}: #{library_path}"
    end
  end
end

def resolve_darwin_library_path(library_path, binary, vendor_lib_dir, source_paths)
  if library_path.start_with?("/")
    return library_path if File.exist?(library_path)
  elsif library_path.start_with?("@loader_path/")
    source_binary = source_paths.fetch(binary, binary)
    source_resolved_path = File.expand_path(library_path.delete_prefix("@loader_path/"), File.dirname(source_binary))
    return source_resolved_path if File.exist?(source_resolved_path)

    resolved_path = File.expand_path(library_path.delete_prefix("@loader_path/"), File.dirname(binary))
    return resolved_path if File.exist?(resolved_path)
  elsif library_path.start_with?("@rpath/")
    relative_path = library_path.delete_prefix("@rpath/")
    source_binary = source_paths.fetch(binary, binary)

    darwin_rpaths_for(binary).each do |rpath|
      [ File.dirname(source_binary), File.dirname(binary) ].each do |loader_path|
        resolved_rpath = rpath.sub("@loader_path", loader_path)
        resolved_path = File.expand_path(relative_path, resolved_rpath)
        return resolved_path if File.exist?(resolved_path)
      end
    end

    vendored_path = File.join(vendor_lib_dir, relative_path)
    return vendored_path if File.exist?(vendored_path)
  end

  nil
end

def darwin_libraries_for(binary)
  `otool -L #{binary.shellescape}`.lines.drop(1).filter_map do |line|
    line.strip.split.first
  end
end

def darwin_rpaths_for(binary)
  output = `otool -l #{binary.shellescape}`
  lines = output.lines
  rpaths = []

  lines.each_with_index do |line, index|
    next unless line.include?("cmd LC_RPATH")

    path_line = lines[index + 2].to_s.strip
    rpaths << path_line.split[1] if path_line.start_with?("path ")
  end

  rpaths
end

def darwin_system_library?(library_path)
  PAGE_PRINT_DARWIN_SYSTEM_PREFIXES.any? { |prefix| library_path.start_with?(prefix) }
end

def darwin_excluded_library?(library_path)
  basename = File.basename(library_path)
  PAGE_PRINT_DARWIN_EXCLUDED_LIBRARIES.any? { |name| basename.start_with?(name) }
end
