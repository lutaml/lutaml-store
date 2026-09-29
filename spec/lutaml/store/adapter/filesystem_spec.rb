# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"

RSpec.describe Lutaml::Store::Adapter::FileSystem do
  around do |example|
    Dir.mktmpdir("lutaml-store-fs") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:root) { File.join(@dir, "store") }
  let(:adapter) { described_class.new(path: root) }

  def data_files
    Dir.glob(File.join(root, "**", "*.data"))
  end

  describe "key encoding" do
    it "keeps keys that differ only in unsafe characters apart" do
      adapter.set("ISO/19115", "a")
      adapter.set("ISO:19115", "b")

      expect(adapter.get("ISO/19115")).to eq("a")
      expect(adapter.get("ISO:19115")).to eq("b")
      expect(adapter.keys).to contain_exactly("ISO/19115", "ISO:19115")
    end

    it "keeps a percent sign distinct from its encoded form" do
      adapter.set("a%2Fb", "percent")
      adapter.set("a/b", "slash")

      expect(adapter.get("a%2Fb")).to eq("percent")
      expect(adapter.keys).to contain_exactly("a%2Fb", "a/b")
    end

    it "stores a key without unsafe characters under its plain name" do
      adapter.set("plain_key-1.0", "v")

      expect(data_files.map { |f| File.basename(f) }).to eq(["plain_key-1.0.data"])
    end

    it "round-trips keys too long for a file name" do
      long_key = "ISO/#{"x" * 300}"
      adapter.set(long_key, "long")

      expect(adapter.get(long_key)).to eq("long")
      expect(adapter.keys).to eq([long_key])
      expect(adapter.all).to eq(long_key => "long")
      expect(adapter.delete(long_key)).to eq("long")
      expect(adapter.keys).to be_empty
    end

    it "keeps dot keys inside the root and lists them" do
      odd_keys = ["", ".", "..", "..x", ".hidden", "a"]
      odd_keys.each { |key| adapter.set(key, "v#{key}") }

      expect(Dir.children(@dir)).to eq(["store"])
      expect(adapter.keys).to match_array(odd_keys)
      odd_keys.each { |key| expect(adapter.get(key)).to eq("v#{key}") }
      expect(adapter.clear).to eq(odd_keys.size)
      expect(adapter.keys).to be_empty
    end

    it "reads and migrates a value stored under a 0.3.0 file name" do
      legacy = File.join(root, "IS", "ISO_19115.data")
      FileUtils.mkdir_p(File.dirname(legacy))
      File.write(legacy, "old")

      expect(adapter.get("ISO/19115")).to eq("old")
      adapter.set("ISO/19115", "new")
      expect(File.exist?(legacy)).to be(false)
      expect(adapter.keys).to eq(["ISO/19115"])
    end

    it "returns the original keys from each_key" do
      adapter.set("ISO 8601:2019", "x")

      expect(adapter.each_key.to_a).to eq(["ISO 8601:2019"])
    end

    it "keeps the metadata path apart from a key that contains the extension" do
      adapter.set("a.data.b", "v")

      expect(adapter.get("a.data.b")).to eq("v")
      expect(Dir.glob(File.join(root, "**", "*.meta")).size).to eq(1)
    end
  end

  describe "value serialization" do
    it "reads back a Hash from a new adapter instance" do
      adapter.set("rec", { "key" => "a", "n" => 1, "tags" => ["x"] })

      fresh = described_class.new(path: root)
      expect(fresh.get("rec")).to eq({ "key" => "a", "n" => 1, "tags" => ["x"] })
    end

    it "writes JSON, not Hash#inspect" do
      adapter.set("rec", { "key" => "a" })

      expect(File.read(data_files.first)).to eq('{"key":"a"}')
    end

    it "keeps a String that looks like JSON as a String" do
      adapter.set("s", '{"a":1}')

      expect(described_class.new(path: root).get("s")).to eq('{"a":1}')
    end

    it "round-trips a Hash with integrity checks disabled" do
      plain = described_class.new(path: root, integrity_checks: false)
      plain.set("rec", { "a" => 1 })

      expect(described_class.new(path: root, integrity_checks: false).get("rec")).to eq({ "a" => 1 })
    end
  end

  describe "#update" do
    it "passes the old value to the block and stores the result" do
      adapter.set("n", "1")

      expect(adapter.update("n") { |old| (old.to_i + 1).to_s }).to eq("2")
      expect(adapter.get("n")).to eq("2")
    end

    it "passes nil for a missing key" do
      adapter.update("new") { |old| old.nil? ? "created" : "wrong" }

      expect(adapter.get("new")).to eq("created")
    end
  end

  describe "thread safety" do
    it "accepts concurrent writes to one key from many threads" do
      errors = Queue.new
      threads = Array.new(8) do |t|
        Thread.new do
          200.times do |i|
            adapter.set("k", "#{t}-#{i}")
          rescue StandardError => e
            errors << e
          end
        end
      end
      threads.each(&:join)

      expect(errors.size).to eq(0)
      expect(adapter.get("k")).to match(/\A\d-199\z/)
    end

    it "never pairs new data with old metadata on reads" do
      stop = false
      errors = Queue.new
      writer = Thread.new do
        500.times { |i| adapter.set("k", "value-#{i}" * (i % 7 + 1)) }
        stop = true
      end
      readers = Array.new(3) do
        Thread.new do
          until stop
            begin
              adapter.get("k")
            rescue StandardError => e
              errors << e
            end
          end
        end
      end
      [writer, *readers].each(&:join)

      expect(errors.size).to eq(0)
    end

    it "lets another fiber of the lock holder re-enter the lock" do
      adapter.set("a", "1")
      reader = Enumerator.new { |y| y << adapter.get("a") }

      result = Timeout.timeout(5) { adapter.update("b") { reader.next } }
      expect(result).to eq("1")
    end

    it "makes update atomic across threads" do
      adapter.set("n", "0")
      Array.new(8) { Thread.new { 50.times { adapter.update("n") { |v| (v.to_i + 1).to_s } } } }.each(&:join)

      expect(adapter.get("n")).to eq("400")
    end
  end

  describe "process safety", if: Process.respond_to?(:fork) do
    it "makes update atomic across processes" do
      adapter.set("n", "0")
      pids = Array.new(4) do
        fork do
          store = described_class.new(path: root)
          100.times { store.update("n") { |v| (v.to_i + 1).to_s } }
          exit!(0)
        end
      end
      statuses = pids.map { |pid| Process.wait2(pid).last }

      expect(statuses).to all(be_success)
      expect(described_class.new(path: root).get("n")).to eq("400")
    end

    it "does not pass a held lock to a forked child" do
      adapter.set("n", "0")
      adapter.transaction do
        pid = fork do
          # The parent still holds the lock, so this must wait for it.
          described_class.new(path: root).update("n") { |v| (v.to_i + 1).to_s }
          exit!(0)
        end
        sleep 0.3
        expect(adapter.get("n")).to eq("0")
        adapter.set("n", "10")
        @child = pid
      end
      Process.wait(@child)

      expect(adapter.get("n")).to eq("11")
    end
  end
end
