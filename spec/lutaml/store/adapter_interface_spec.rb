# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Adapter::Base do
  subject(:adapter) { described_class.new }

  it "raises NotImplementedError for get" do
    expect { adapter.get("key") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for set" do
    expect { adapter.set("key", "value") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for delete" do
    expect { adapter.delete("key") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for exists?" do
    expect { adapter.exists?("key") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for keys" do
    expect { adapter.keys }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for all" do
    expect { adapter.all }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for clear" do
    expect { adapter.clear }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for size" do
    expect { adapter.size }.to raise_error(NotImplementedError)
  end

  it "provides default close that does not raise" do
    expect { adapter.close }.not_to raise_error
  end

  describe "default bulk operations" do
    let(:concrete_adapter) do
      Class.new(described_class) do
        def initialize
          super
          @data = {}
        end

        def get(key)
          @data[key]
        end

        def set(key, value)
          @data[key] = value
        end

        def delete(key)
          @data.delete(key)
        end
      end.new
    end

    it "bulk_get iterates over get" do
      concrete_adapter.set("a", 1)
      concrete_adapter.set("b", 2)
      expect(concrete_adapter.bulk_get(%w[a b c])).to eq("a" => 1, "b" => 2, "c" => nil)
    end

    it "bulk_set iterates over set" do
      concrete_adapter.bulk_set("a" => 1, "b" => 2)
      expect(concrete_adapter.get("a")).to eq(1)
      expect(concrete_adapter.get("b")).to eq(2)
    end

    it "bulk_delete iterates over delete" do
      concrete_adapter.set("a", 1)
      concrete_adapter.set("b", 2)
      result = concrete_adapter.bulk_delete(%w[a c])
      expect(result).to eq("a" => 1, "c" => nil)
    end
  end

  it "provides default stats" do
    expect(adapter.stats).to eq({ adapter: described_class.name })
  end
end
