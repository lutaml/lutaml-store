# frozen_string_literal: true

RSpec.describe Lutaml::Store do
  it "has a version number" do
    expect(Lutaml::Store::VERSION).not_to be nil
  end

  it "provides access to Store and DatabaseStore classes" do
    expect(Lutaml::Store::BasicStore).to be_a(Class)
    expect(Lutaml::Store::DatabaseStore).to be_a(Class)
  end

  it "returns a DatabaseStore from .new" do
    test_model = Struct.new(:id, :name)
    store = Lutaml::Store.new(
      adapter: :memory,
      models: [{ model: test_model, key: :id }]
    )
    expect(store).to be_a(Lutaml::Store::DatabaseStore)
  end
end
