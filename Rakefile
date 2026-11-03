# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

desc "Run adapter benchmarks and print a comparison report"
task :"performance:compare" do
  $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
  require "lutaml/store"
  require "tmpdir"
  require "fileutils"

  ops = 2000
  data = Array.new(100) { |i| { "id" => i, "name" => "item-#{i}" } }

  measure = lambda do |label, &operation|
    GC.start
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    operation.call
    format("%<label>-34s %<us>9.1fus/op", label: label,
                                          us: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000 / ops)
  end

  results = []
  Dir.mktmpdir do |dir|
    memory = Lutaml::Store::Adapter::Memory.new
    results << measure.call("memory set") { ops.times { |i| memory.set("k#{i}", data[i % 100]) } }
    results << measure.call("memory get") { ops.times { |i| memory.get("k#{i % 500}") } }

    fs = Lutaml::Store::Adapter::FileSystem.new(path: File.join(dir, "fs"))
    results << measure.call("filesystem set") { ops.times { |i| fs.set("k#{i}", data[i % 100]) } }
    results << measure.call("filesystem set (unchanged)") { ops.times { |i| fs.set("k#{i}", data[i % 100]) } }
    results << measure.call("filesystem get") { ops.times { |i| fs.get("k#{i % 500}") } }
    fs.close
    FileUtils.rm_rf(File.join(dir, "fs"))

    begin
      require "sqlite3"
      sqlite = Lutaml::Store::Adapter::Sqlite.new(path: File.join(dir, "db.sqlite3"))
      results << measure.call("sqlite set") { ops.times { |i| sqlite.set("k#{i}", data[i % 100]) } }
      results << measure.call("sqlite get") { ops.times { |i| sqlite.get("k#{i % 500}") } }
      sqlite.close
    rescue LoadError
      results << "sqlite3 gem unavailable, sqlite benchmarks skipped"
    end
  end

  puts results
end
