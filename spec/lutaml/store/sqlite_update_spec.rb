# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Does NOT reference the Sqlite constant or require "sqlite3" at load time:
# that would break the autoload spec (see sqlite_scale_spec.rb).
RSpec.describe "Lutaml::Store::Adapter::Sqlite#update and #each_key" do
  around do |example|
    Dir.mktmpdir("lutaml-store-sqlite") do |dir|
      @path = File.join(dir, "store.db")
      example.run
    end
  end

  it "yields each key" do
    adapter = Lutaml::Store::Adapter.resolve(:sqlite, path: @path)
    adapter.set("a", "1")

    expect(adapter.each_key.to_a).to eq(["a"])
  end

  it "makes update atomic across threads" do
    adapter = Lutaml::Store::Adapter.resolve(:sqlite, path: @path)
    adapter.set("n", { "count" => 0 })
    Array.new(4) do
      Thread.new { 50.times { adapter.update("n") { |v| { "count" => v["count"] + 1 } } } }
    end.each(&:join)

    expect(adapter.get("n")).to eq({ "count" => 200 })
  end

  it "makes update atomic across processes", if: Process.respond_to?(:fork) do
    Lutaml::Store::Adapter.resolve(:sqlite, path: @path).set("n", { "count" => 0 })
    pids = Array.new(4) do
      fork do
        store = Lutaml::Store::Adapter.resolve(:sqlite, path: @path)
        100.times { store.update("n") { |v| { "count" => v["count"] + 1 } } }
        exit!(0)
      end
    end
    statuses = pids.map { |pid| Process.wait2(pid).last }

    expect(statuses).to all(be_success)
    expect(Lutaml::Store::Adapter.resolve(:sqlite, path: @path).get("n")).to eq({ "count" => 400 })
  end
end
