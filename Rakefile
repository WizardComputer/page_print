require "rake/extensiontask"
require "rake/testtask"

spec = Gem::Specification.load("page_print.gemspec")

Rake::ExtensionTask.new("page_print", spec) do |ext|
  ext.ext_dir = "ext/page_print"
  ext.lib_dir = "lib/page_print"
end

Rake::TestTask.new(:test) do |test|
  test.libs << "lib"
  test.libs << "test"
  test.pattern = "test/**/*_test.rb"
  test.warning = true
end

task default: [:compile, :test]
