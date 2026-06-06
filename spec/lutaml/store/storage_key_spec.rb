# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::StorageKey do
  describe ".parse" do
    it "splits at the first single colon" do
      key = described_class.parse("MyClass:abc123")
      expect(key.class_name).to eq("MyClass")
      expect(key.key_value).to eq("abc123")
    end

    it "skips double colons in class names" do
      key = described_class.parse("MyModule::MyClass:abc123")
      expect(key.class_name).to eq("MyModule::MyClass")
      expect(key.key_value).to eq("abc123")
    end

    it "handles key values containing colons" do
      key = described_class.parse("MyModule::MyClass:http://example.com")
      expect(key.class_name).to eq("MyModule::MyClass")
      expect(key.key_value).to eq("http://example.com")
    end

    it "returns empty class_name when no single colon" do
      key = described_class.parse("MyModule::MyClass")
      expect(key.class_name).to eq("")
      expect(key.key_value).to eq("MyModule::MyClass")
    end
  end

  describe "#to_s" do
    it "joins class_name and key_value with colon" do
      key = described_class.new("MyClass", "abc123")
      expect(key.to_s).to eq("MyClass:abc123")
    end
  end

  describe "round-trip" do
    it "parses and serializes back to the same string" do
      original = "MyModule::MyClass:http://example.com/path"
      key = described_class.parse(original)
      expect(key.to_s).to eq(original)
    end
  end

  describe "equality" do
    it "considers keys with same string representation equal" do
      key1 = described_class.new("MyClass", "abc")
      key2 = described_class.new("MyClass", "abc")
      expect(key1).to eq(key2)
    end
  end
end
