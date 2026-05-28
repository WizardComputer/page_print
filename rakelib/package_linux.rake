require "fileutils"
require "bundler"
require "rbconfig"
require "rubygems/package_task"
require "shellwords"

namespace :package do
  PLUTOBOOK_VERSION = "v0.17.0"
  LINUX_PLATFORM = "x86_64-linux"

  desc "Build a precompiled Linux gem with vendored PlutoBook"
  task :linux do
    abort "package:linux currently supports x86_64 Linux only" unless linux_x86_64?

    root = File.expand_path("..", __dir__)
    vendor_dir = File.join(root, "lib", "page_print", "vendor", LINUX_PLATFORM)
    plutobook_source_dir = File.join(root, "tmp", "plutobook-src")
    plutobook_build_dir = File.join(root, "tmp", "plutobook-build")
    plutobook_install_dir = File.join(root, "tmp", "plutobook-install", LINUX_PLATFORM)

    FileUtils.rm_rf(plutobook_source_dir)
    FileUtils.rm_rf(plutobook_build_dir)
    FileUtils.rm_rf(plutobook_install_dir)
    FileUtils.rm_rf(vendor_dir)
    FileUtils.mkdir_p(File.dirname(plutobook_source_dir))
    FileUtils.mkdir_p(File.join(root, "pkg"))

    sh "git clone --depth 1 --branch #{PLUTOBOOK_VERSION.shellescape} https://github.com/plutoprint/plutobook.git #{plutobook_source_dir.shellescape}"
    sh "meson setup #{plutobook_build_dir.shellescape} #{plutobook_source_dir.shellescape} --prefix=#{plutobook_install_dir.shellescape} --libdir=lib --buildtype=release"
    sh "meson compile -C #{plutobook_build_dir.shellescape}"
    sh "meson install -C #{plutobook_build_dir.shellescape}"

    FileUtils.mkdir_p(vendor_dir)
    FileUtils.cp_r(File.join(plutobook_install_dir, "include"), vendor_dir)
    FileUtils.cp_r(File.join(plutobook_install_dir, "lib"), vendor_dir)

    ENV["PAGE_PRINT_VENDOR_PLATFORM"] = LINUX_PLATFORM
    Rake::Task["clean"].invoke if Rake::Task.task_defined?("clean")
    Rake::Task["compile"].invoke

    Bundler.with_unbundled_env do
      sh({ "PAGE_PRINT_PRECOMPILED" => "1", "PAGE_PRINT_PRECOMPILED_PLATFORM" => LINUX_PLATFORM }, "gem build page_print.gemspec")
    end

    gem_path = Dir.glob(File.join(root, "page_print-*-#{LINUX_PLATFORM}.gem")).max_by { |path| File.mtime(path) }
    abort "gem build failed" unless gem_path && File.file?(gem_path)

    FileUtils.mv(gem_path, File.join(root, "pkg", File.basename(gem_path)), force: true)
  end
end

def linux_x86_64?
  RbConfig::CONFIG.fetch("host_os").include?("linux") && RbConfig::CONFIG.fetch("host_cpu") == "x86_64"
end
