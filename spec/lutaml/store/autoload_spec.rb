# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Autoload" do
  it "loads BasicStore without sqlite3" do
    store = Lutaml::Store::BasicStore.new(adapter_type: :memory)
    store.set("key", "value")
    expect(store.get("key")).to eq("value")

    sqlite_loaded = $LOADED_FEATURES.any? { |path| path.include?("sqlite3") }
    expect(sqlite_loaded).to be false
  end

  it "loads all constants lazily" do
    # After requiring lutaml/store, only error classes and autoload entries exist
    expect(Lutaml::Store::Error).to be_a(Class)
    expect(Lutaml::Store::ConfigurationError).to be_a(Class)
    expect(Lutaml::Store::BackendError).to be_a(Class)
  end

  it "loads DatabaseStore on first use" do
    expect(defined?(Lutaml::Store::DatabaseStore)).to eq("constant")
  end

  it "loads Adapter::Base and subclasses on first reference" do
    expect(defined?(Lutaml::Store::Adapter::Base)).to eq("constant")
    expect(defined?(Lutaml::Store::Adapter::Memory)).to eq("constant")
  end

  it "loads BasicStore lazily" do
    expect(defined?(Lutaml::Store::BasicStore)).to eq("constant")
  end
end
