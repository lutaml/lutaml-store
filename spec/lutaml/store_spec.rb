# frozen_string_literal: true

RSpec.describe Lutaml::Store do
  it "has a version number" do
    expect(Lutaml::Store::VERSION).not_to be nil
  end

  it "provides access to Store and ModelStore classes" do
    expect(Lutaml::Store::Store).to be_a(Class)
    expect(Lutaml::Store::ModelStore).to be_a(Class)
    expect(Lutaml::Store::Serializer).to be_a(Class)
  end
end
