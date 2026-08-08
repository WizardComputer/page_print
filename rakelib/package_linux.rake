require "fileutils"
require "bundler"
require "rbconfig"
require "rubygems/package_task"
require "shellwords"

PAGE_PRINT_PLUTOBOOK_VERSION = "v0.18.0" unless defined?(PAGE_PRINT_PLUTOBOOK_VERSION)
PAGE_PRINT_LINUX_PLATFORM = "x86_64-linux"
PAGE_PRINT_LINUX_SYSTEM_LIBRARIES = %w[
  ld-linux
  libc.so
  libdl.so
  libgcc_s.so
  libm.so
  libpthread.so
  libresolv.so
  librt.so
  libstdc++.so
  linux-vdso
].freeze

namespace :package do
  desc "Build a Linux gem with vendored PlutoBook"
  task :linux do
    abort "package:linux currently supports x86_64 Linux only" unless linux_x86_64?

    root = File.expand_path("..", __dir__)
    vendor_dir = File.join(root, "lib", "page_print", "vendor", PAGE_PRINT_LINUX_PLATFORM)
    plutobook_source_dir = File.join(root, "tmp", "plutobook-src")
    plutobook_build_dir = File.join(root, "tmp", "plutobook-build")
    plutobook_install_dir = File.join(root, "tmp", "plutobook-install", PAGE_PRINT_LINUX_PLATFORM)

    FileUtils.rm_rf(plutobook_source_dir)
    FileUtils.rm_rf(plutobook_build_dir)
    FileUtils.rm_rf(plutobook_install_dir)
    FileUtils.rm_rf(vendor_dir)
    FileUtils.mkdir_p(File.dirname(plutobook_source_dir))
    FileUtils.mkdir_p(File.join(root, "pkg"))

    sh "git clone --depth 1 --branch #{PAGE_PRINT_PLUTOBOOK_VERSION.shellescape} https://github.com/plutoprint/plutobook.git #{plutobook_source_dir.shellescape}"
    sh "meson setup #{plutobook_build_dir.shellescape} #{plutobook_source_dir.shellescape} --prefix=#{plutobook_install_dir.shellescape} --libdir=lib --buildtype=release -Dcpp_args=\"['-include', 'memory_resource']\" --force-fallback-for=harfbuzz -Dcurl=disabled -Dturbojpeg=disabled -Dwebp=disabled -Dtools=disabled -Dtests=disabled -Dexamples=disabled"
    sh "meson compile -C #{plutobook_build_dir.shellescape}"
    sh "meson install -C #{plutobook_build_dir.shellescape}"

    FileUtils.mkdir_p(vendor_dir)
    FileUtils.cp_r(File.join(plutobook_install_dir, "include"), vendor_dir)
    FileUtils.cp_r(File.join(plutobook_install_dir, "lib"), vendor_dir)

    ENV["PAGE_PRINT_VENDOR_PLATFORM"] = PAGE_PRINT_LINUX_PLATFORM
    Rake::Task["clean"].invoke if Rake::Task.task_defined?("clean")
    Rake::Task["compile"].invoke

    extension_path = File.join(root, "lib", "page_print", "page_print.so")
    vendor_lib_dir = File.join(vendor_dir, "lib")
    vendor_linux_shared_libraries(extension_path, vendor_lib_dir)
    patch_linux_rpaths(extension_path, vendor_lib_dir)
    verify_no_missing_linux_libraries(extension_path, vendor_lib_dir)
    collapse_vendor_shared_library_aliases(vendor_lib_dir)
    FileUtils.rm_f(extension_path)

    Bundler.with_unbundled_env do
      sh({ "PAGE_PRINT_VENDOR_ONLY" => "1", "PAGE_PRINT_PRECOMPILED_PLATFORM" => PAGE_PRINT_LINUX_PLATFORM }, "gem build page_print.gemspec")
    end

    gem_path = Dir.glob(File.join(root, "page_print-*-#{PAGE_PRINT_LINUX_PLATFORM}.gem")).max_by { |path| File.mtime(path) }
    abort "gem build failed" unless gem_path && File.file?(gem_path)

    FileUtils.mv(gem_path, File.join(root, "pkg", File.basename(gem_path)), force: true)
  end
end

def linux_x86_64?
  RbConfig::CONFIG.fetch("host_os").include?("linux") && RbConfig::CONFIG.fetch("host_cpu") == "x86_64"
end

def vendor_linux_shared_libraries(extension_path, vendor_lib_dir)
  queue = [ extension_path, *Dir.glob(File.join(vendor_lib_dir, "*.so*")) ]
  seen = {}

  until queue.empty?
    binary = queue.shift
    next if seen[binary]

    seen[binary] = true

    shared_libraries_for(binary).each do |library_path|
      next if linux_system_library?(library_path)

      target_path = File.join(vendor_lib_dir, File.basename(library_path))

      unless File.exist?(target_path)
        File.binwrite(target_path, File.binread(File.realpath(library_path)))
        FileUtils.chmod(0o755, target_path)
      end

      queue << target_path
    end
  end
end

def collapse_vendor_shared_library_aliases(vendor_lib_dir)
  aliases = {}

  Dir.glob(File.join(vendor_lib_dir, "*.so*")).each do |library_path|
    next unless File.symlink?(library_path)

    target_name = File.basename(File.realpath(library_path))
    alias_name = File.basename(library_path)
    next if alias_name == target_name

    aliases[alias_name] = target_name
    FileUtils.rm(library_path)
  end

  manifest_path = File.join(vendor_lib_dir, "so_aliases")
  if aliases.empty?
    FileUtils.rm_f(manifest_path)
  else
    File.write(manifest_path, aliases.sort.map { |alias_name, target_name| "#{alias_name}\t#{target_name}\n" }.join)
  end
end

def patch_linux_rpaths(extension_path, vendor_lib_dir)
  sh "patchelf --set-rpath '$ORIGIN/vendor/#{package_linux_platform}/lib' #{extension_path.shellescape}"

  Dir.glob(File.join(vendor_lib_dir, "*.so*")).each do |library_path|
    next if File.symlink?(library_path)

    sh "patchelf --set-rpath '$ORIGIN' #{library_path.shellescape}"
  end
end

def verify_no_missing_linux_libraries(extension_path, vendor_lib_dir)
  binaries = [extension_path]
  Dir.glob(File.join(vendor_lib_dir, "*.so*")).each do |library_path|
    next if File.symlink?(library_path)

    binaries << library_path
  end

  binaries.each do |binary|
    output = `ldd #{binary.shellescape}`
    abort "Missing shared library for #{binary}:\n#{output}" if output.include?("not found")
  end
end

def shared_libraries_for(binary)
  `ldd #{binary.shellescape}`.lines.filter_map do |line|
    if (match = line.match(/=>\s+(\/\S+)/))
      match[1]
    elsif (match = line.match(/^\s*(\/\S+)/))
      match[1]
    end
  end
end

def linux_system_library?(library_path)
  basename = File.basename(library_path)
  PAGE_PRINT_LINUX_SYSTEM_LIBRARIES.any? { |name| basename.start_with?(name) }
end

def package_linux_platform
  PAGE_PRINT_LINUX_PLATFORM
end
