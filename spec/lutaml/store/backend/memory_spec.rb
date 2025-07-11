# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Adapter::Memory do
  let(:adapter) { described_class.new }

  describe "#get and #set" do
    it "stores and retrieves values" do
      adapter.set("key1", "value1")
      expect(adapter.get("key1")).to eq("value1")
    end

    it "returns nil for non-existent keys" do
      expect(adapter.get("nonexistent")).to be_nil
    end
  end

  describe "#delete" do
    it "deletes existing keys" do
      adapter.set("key1", "value1")
      expect(adapter.delete("key1")).to be true
      expect(adapter.get("key1")).to be_nil
    end

    it "returns false for non-existent keys" do
      expect(adapter.delete("nonexistent")).to be false
    end
  end

  describe "#exists?" do
    it "returns true for existing keys" do
      adapter.set("key1", "value1")
      expect(adapter.exists?("key1")).to be true
    end

    it "returns false for non-existent keys" do
      expect(adapter.exists?("nonexistent")).to be false
    end
  end

  describe "#all" do
    it "returns all key-value pairs" do
      adapter.set("key1", "value1")
      adapter.set("key2", "value2")

      result = adapter.all
      expect(result).to eq("key1" => "value1", "key2" => "value2")
    end
  end

  describe "#clear" do
    it "removes all data" do
      adapter.set("key1", "value1")
      adapter.set("key2", "value2")

      adapter.clear
      expect(adapter.size).to eq(0)
      expect(adapter.all).to be_empty
    end
  end

  describe "#size" do
    it "returns the number of stored items" do
      expect(adapter.size).to eq(0)

      adapter.set("key1", "value1")
      expect(adapter.size).to eq(1)

      adapter.set("key2", "value2")
      expect(adapter.size).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = []

      10.times do |i|
        threads << Thread.new do
          adapter.set("key#{i}", "value#{i}")
          adapter.get("key#{i}")
        end
      end

      threads.each(&:join)
      expect(adapter.size).to eq(10)
    end
  end
end
