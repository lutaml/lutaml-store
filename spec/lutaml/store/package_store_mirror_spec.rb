# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "support/simple_test_model"

RSpec.describe "mirror hydration at load" do
  let(:definition) do
    Lutaml::Store::PackageDefinition.new(name: :mirrors) do |pkg|
      pkg.model(model: SimpleTestModel, dir: "items",
                layout: :separate, key: :id, default_format: :yaml)
    end
  end

  let(:dir) do
    dir = Dir.mktmpdir("lutaml-store-mirror")
    FileUtils.mkdir_p(File.join(dir, "items"))
    File.write(File.join(dir, "items", "a.yaml"), "---\nid: a\nname: Alpha\n")
    File.write(File.join(dir, "items", "b.yaml"), "---\nid: b\nname: Beta\n")
    dir
  end

  after { FileUtils.remove_entry(dir) }

  let(:store) { Lutaml::Store::PackageStore.load(definition, dir) }
  let(:adapter) { store.db.store.adapter }

  it "registers the parsed models without a backend write" do
    expect(adapter.mirror_count).to eq(2)
    expect(adapter.backend.size).to be_zero
  end

  it "serves models_for from the mirrors" do
    expect(store.models_for(SimpleTestModel).map(&:name)).to contain_exactly("Alpha", "Beta")
    expect(store.model_count(SimpleTestModel)).to eq(2)
  end

  it "serves fetch_model and model_exists? from the mirrors" do
    expect(store.fetch_model(SimpleTestModel, "b").name).to eq("Beta")
    expect(store.model_exists?(SimpleTestModel, "a")).to be true
    expect(store.model_exists?(SimpleTestModel, "missing")).to be false
  end

  it "leaves the source files byte-identical after load and reads" do
    before = Dir[File.join(dir, "items", "*.yaml")].map { |f| [f, File.binread(f)] }
    store.models_for(SimpleTestModel).to_a

    after = Dir[File.join(dir, "items", "*.yaml")].map { |f| [f, File.binread(f)] }
    expect(after).to eq(before)
  end

  it "filters mirrors through predicates" do
    expect(store.db.where(model: SimpleTestModel, name: "Beta").map(&:id))
      .to contain_exactly("b")
  end

  it "sorts mirror records by field" do
    expect(store.db.all(model: SimpleTestModel).order(:id).map(&:id))
      .to eq(%w[a b])
    expect(store.db.all(model: SimpleTestModel).order(id: :desc).map(&:id))
      .to eq(%w[b a])
  end

  it "hands the key back to the backend when a mirror is updated" do
    updated = store.fetch_model(SimpleTestModel, "a")
    updated.name = "Alpha II"
    store.db.save(updated)

    expect(adapter.mirror_count).to eq(1)
    expect(store.fetch_model(SimpleTestModel, "a").name).to eq("Alpha II")
    expect(File.read(File.join(dir, "items", "a.yaml"))).not_to include("Alpha II")
  end

  it "writes the package back through save" do
    out = File.join(dir, "..", "mirror-out-#{Process.pid}")
    FileUtils.remove_entry(out) if Dir.exist?(out)

    store.save(out)

    expect(File.read(File.join(out, "items", "b.yaml"))).to include("Beta")
    FileUtils.remove_entry(out)
  end
end
