#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
DEFAULT_HTML_PATH = File.join(ROOT, 'benchmark/fixtures/report.html')
DEFAULT_OUTPUT_DIR = File.join(ROOT, 'tmp/benchmarks/pdf_renderers')

unless defined?(Rails)
  $LOAD_PATH.unshift(File.join(ROOT, 'lib'))
end

require 'page_print'

def require_pdfkit
  require 'pdfkit'

  PDFKit.configure do |config|
    config.wkhtmltopdf = ENV['WKHTMLTOPDF'] if ENV['WKHTMLTOPDF'] && !ENV['WKHTMLTOPDF'].empty?
  end
rescue LoadError
  abort 'pdfkit is not available. Run `bundle install` or omit it with RENDERERS=page_print.'
end

def env_int(name, default)
  value = ENV[name]
  return default if value.nil? || value.empty?

  Integer(value)
rescue ArgumentError
  abort "#{name} must be an integer"
end

def env_list(name, default)
  value = ENV[name]
  return default if value.nil? || value.empty?

  value.split(',').map(&:strip).reject(&:empty?)
end

def rss_kb(pid = Process.pid)
  output = `ps -o rss= -p #{pid.to_i}`
  output.to_i
end

def process_table
  `ps -axo pid=,ppid=,rss=`.each_line.each_with_object({}) do |line, table|
    pid, ppid, rss = line.split.map(&:to_i)
    table[pid] = { ppid: ppid, rss: rss } if pid && ppid && rss
  end
end

def descendant_pids(pid, table)
  children_by_parent = table.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(child_pid, info), children|
    children[info[:ppid]] << child_pid
  end
  descendants = []
  queue = children_by_parent[pid]

  until queue.empty?
    child_pid = queue.shift
    descendants << child_pid
    queue.concat(children_by_parent[child_pid])
  end

  descendants
end

def process_tree_rss_kb(pid = Process.pid)
  table = process_table
  pids = [pid] + descendant_pids(pid, table)
  pids.sum { |tree_pid| table.dig(tree_pid, :rss).to_i }
end

def cpu_ms
  times = Process.times
  ((times.utime + times.stime + times.cutime + times.cstime) * 1000.0).round(3)
end

def monotonic_ms
  Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
end

def load_html
  if ENV['TEMPLATE'] && defined?(Rails)
    ApplicationController.renderer.render(
      template: ENV.fetch('TEMPLATE'),
      layout: ENV['LAYOUT'],
      formats: [:html]
    )
  else
    html_path = File.expand_path(ENV.fetch('HTML', DEFAULT_HTML_PATH))
    File.read(html_path)
  end
end

def page_print_options
  options = {
    page_size: ENV.fetch('PAGE_SIZE', 'a4').to_sym,
    margins: ENV.fetch('MARGINS', 'normal').to_sym,
    media: ENV.fetch('MEDIA', 'print').to_sym
  }

  options[:base_url] = ENV['BASE_URL'] if ENV['BASE_URL'] && !ENV['BASE_URL'].empty?
  options
end

def pdfkit_options
  options = {
    page_size: ENV.fetch('PAGE_SIZE', 'A4').upcase,
    print_media_type: ENV.fetch('MEDIA', 'print') == 'print'
  }

  if ENV['MARGINS'] == 'none'
    options[:margin_top] = options[:margin_right] = options[:margin_bottom] = options[:margin_left] = '0'
  end

  options
end

def render_page_print(html, output_path)
  PagePrint.html_to_pdf(html, output_path, **page_print_options)
end

def render_pdfkit(html, output_path)
  PDFKit.new(html, pdfkit_options).to_file(output_path)
  nil
end

def measure(renderer, run, html, output_dir, warmup: false)
  output_path = File.join(output_dir, renderer, "#{warmup ? 'warmup' : 'run'}-#{run}.pdf")
  FileUtils.mkdir_p(File.dirname(output_path))
  FileUtils.rm_f(output_path)
  GC.start

  rss_before = rss_kb
  cpu_before = cpu_ms
  wall_before = monotonic_ms
  peak_process_tree_rss_kb = process_tree_rss_kb
  error = nil
  rendering = true

  sampler = Thread.new do
    while rendering
      peak_process_tree_rss_kb = [peak_process_tree_rss_kb, process_tree_rss_kb].max
      sleep 0.01
    end
  end

  begin
    case renderer
    when 'page_print'
      render_page_print(html, output_path)
    when 'pdfkit'
      render_pdfkit(html, output_path)
    else
      raise "unknown renderer: #{renderer}"
    end
  rescue StandardError => e
    error = e.message
  ensure
    rendering = false
    sampler.join
  end

  wall_after = monotonic_ms
  cpu_after = cpu_ms
  rss_after = rss_kb
  pdf_size = File.exist?(output_path) ? File.size(output_path) : 0

  {
    renderer: renderer,
    run: run,
    warmup: warmup,
    success: error.nil?,
    wall_time_ms: (wall_after - wall_before).round(3),
    cpu_time_ms: (cpu_after - cpu_before).round(3),
    rss_before_kb: rss_before,
    rss_after_kb: rss_after,
    rss_delta_kb: rss_after - rss_before,
    peak_process_tree_rss_kb: peak_process_tree_rss_kb,
    pdf_size_bytes: pdf_size,
    output_path: output_path,
    error: error
  }
end

def percentile(values, percentile)
  sorted = values.sort
  return 0 if sorted.empty?

  index = ((percentile / 100.0) * (sorted.length - 1)).ceil
  sorted[index]
end

def average(values)
  return 0 if values.empty?

  values.sum / values.length.to_f
end

def csv_value(value)
  string = value.to_s
  return string unless string.match?(/[",\n]/)

  %("#{string.gsub('"', '""')}")
end

def write_csv(path, rows)
  return if rows.empty?

  File.open(path, 'w') do |file|
    keys = rows.first.keys
    file.puts(keys.map { |key| csv_value(key) }.join(','))
    rows.each do |row|
      file.puts(keys.map { |key| csv_value(row[key]) }.join(','))
    end
  end
end

def print_summary(results)
  successful = results.reject { |result| result[:warmup] }.select { |result| result[:success] }
  failed = results.reject { |result| result[:warmup] }.reject { |result| result[:success] }

  puts
  puts 'Renderer      Runs  Avg wall  P95 wall  Avg CPU   Avg peak RSS  P95 peak RSS  Avg PDF size'
  puts '------------  ----  --------  --------  --------  ------------  ------------  ------------'

  successful.group_by { |result| result[:renderer] }.each do |renderer, rows|
    wall_times = rows.map { |row| row[:wall_time_ms] }
    cpu_times = rows.map { |row| row[:cpu_time_ms] }
    peak_rss = rows.map { |row| row[:peak_process_tree_rss_kb] }
    pdf_sizes = rows.map { |row| row[:pdf_size_bytes] }

    puts format(
      '%-12s  %4d  %7.1fms  %7.1fms  %7.1fms  %9.1fMB  %9.1fMB  %9.1fKB',
      renderer,
      rows.length,
      average(wall_times),
      percentile(wall_times, 95),
      average(cpu_times),
      average(peak_rss) / 1024.0,
      percentile(peak_rss, 95) / 1024.0,
      average(pdf_sizes) / 1024.0
    )
  end

  return if failed.empty?

  puts
  puts 'Failures:'
  failed.each do |result|
    puts "#{result[:renderer]} run #{result[:run]}: #{result[:error]}"
  end
end

runs = env_int('RUNS', 10)
warmups = env_int('WARMUPS', 2)
renderers = env_list('RENDERERS', %w[page_print pdfkit])
require_pdfkit if renderers.include?('pdfkit')
output_dir = File.expand_path(ENV.fetch('OUTPUT_DIR', DEFAULT_OUTPUT_DIR))
csv_path = File.join(output_dir, 'results.csv')
html = load_html
results = []

FileUtils.mkdir_p(output_dir)

puts "Ruby: #{RUBY_DESCRIPTION}"
puts "Rails: #{Rails.version}" if defined?(Rails)
puts "Renderers: #{renderers.join(', ')}"
puts "Runs: #{runs}, warmups: #{warmups}"
puts "Output: #{output_dir}"

renderers.each do |renderer|
  1.upto(warmups) do |run|
    result = measure(renderer, run, html, output_dir, warmup: true)
    results << result
    warn "#{renderer} warmup #{run} failed: #{result[:error]}" unless result[:success]
  end

  1.upto(runs) do |run|
    result = measure(renderer, run, html, output_dir)
    results << result
    puts format('%-12s run %3d/%d  %8.1fms  %8.1fms CPU  %8.1fKB', renderer, run, runs, result[:wall_time_ms], result[:cpu_time_ms], result[:pdf_size_bytes] / 1024.0)
  end
end

write_csv(csv_path, results)

print_summary(results)
puts
puts "CSV: #{csv_path}"
