# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Predicate do
  let(:hash_data) { { "status" => "published", "year" => 2023, "score" => 95, "name" => "ISO 9001" } }

  describe "auto-detection from build_from_hash" do
    it "creates Equal for scalar values" do
      preds = described_class.build_from_hash(status: "published")
      expect(preds).to contain_exactly(
        an_instance_of(described_class::Equal)
      )
    end

    it "creates Between for Range values" do
      preds = described_class.build_from_hash(year: 2020..2024)
      expect(preds).to contain_exactly(
        an_instance_of(described_class::Between)
      )
    end

    it "creates In for Array values" do
      preds = described_class.build_from_hash(status: %w[draft published])
      expect(preds).to contain_exactly(
        an_instance_of(described_class::In)
      )
    end
  end

  describe "Equal" do
    let(:pred) { described_class::Equal.new(:status, "published") }

    it "matches hash data" do
      expect(pred.match?(hash_data)).to be true
    end

    it "does not match different value" do
      expect(pred.match?({ "status" => "draft" })).to be false
    end

    it "matches model instance" do
      model = Struct.new(:status).new("published")
      expect(pred.match?(model)).to be true
    end

    describe "#negate" do
      it "returns NotEqual" do
        expect(pred.negate).to be_an_instance_of(described_class::NotEqual)
      end
    end
  end

  describe "NotEqual" do
    let(:pred) { described_class::NotEqual.new(:status, "published") }

    it "does not match equal value" do
      expect(pred.match?(hash_data)).to be false
    end

    it "matches different value" do
      expect(pred.match?({ "status" => "draft" })).to be true
    end

    describe "#negate" do
      it "returns Equal" do
        expect(pred.negate).to be_an_instance_of(described_class::Equal)
      end
    end
  end

  describe "GreaterThan" do
    let(:pred) { described_class::GreaterThan.new(:year, 2020) }

    it "matches greater value" do
      expect(pred.match?(hash_data)).to be true
    end

    it "does not match lesser value" do
      expect(pred.match?({ "year" => 2019 })).to be false
    end

    it "does not match nil" do
      expect(pred.match?({ "year" => nil })).to be false
    end

    describe "#negate" do
      it "returns LessThanOrEqual" do
        expect(pred.negate).to be_an_instance_of(described_class::LessThanOrEqual)
      end
    end
  end

  describe "LessThan" do
    let(:pred) { described_class::LessThan.new(:year, 2025) }

    it "matches lesser value" do
      expect(pred.match?(hash_data)).to be true
    end

    it "does not match greater value" do
      expect(pred.match?({ "year" => 2030 })).to be false
    end

    describe "#negate" do
      it "returns GreaterThanOrEqual" do
        expect(pred.negate).to be_an_instance_of(described_class::GreaterThanOrEqual)
      end
    end
  end

  describe "GreaterThanOrEqual" do
    let(:pred) { described_class::GreaterThanOrEqual.new(:year, 2023) }

    it "matches equal value" do
      expect(pred.match?(hash_data)).to be true
    end

    it "matches greater value" do
      expect(pred.match?({ "year" => 2024 })).to be true
    end

    it "does not match lesser value" do
      expect(pred.match?({ "year" => 2022 })).to be false
    end
  end

  describe "LessThanOrEqual" do
    let(:pred) { described_class::LessThanOrEqual.new(:year, 2023) }

    it "matches equal value" do
      expect(pred.match?(hash_data)).to be true
    end

    it "matches lesser value" do
      expect(pred.match?({ "year" => 2020 })).to be true
    end

    it "does not match greater value" do
      expect(pred.match?({ "year" => 2024 })).to be false
    end
  end

  describe "Between" do
    let(:pred) { described_class::Between.new(:year, 2020..2024) }

    it "matches value in range" do
      expect(pred.match?(hash_data)).to be true
    end

    it "matches range boundaries" do
      expect(pred.match?({ "year" => 2020 })).to be true
      expect(pred.match?({ "year" => 2024 })).to be true
    end

    it "does not match value outside range" do
      expect(pred.match?({ "year" => 2019 })).to be false
      expect(pred.match?({ "year" => 2025 })).to be false
    end

    describe "#negate" do
      it "returns NotBetween" do
        expect(pred.negate).to be_an_instance_of(described_class::NotBetween)
      end
    end
  end

  describe "In" do
    let(:pred) { described_class::In.new(:status, %w[draft published]) }

    it "matches included value" do
      expect(pred.match?(hash_data)).to be true
    end

    it "does not match excluded value" do
      expect(pred.match?({ "status" => "archived" })).to be false
    end

    describe "#negate" do
      it "returns NotIn" do
        expect(pred.negate).to be_an_instance_of(described_class::NotIn)
      end
    end
  end

  describe "Matches" do
    let(:pred) { described_class::Matches.new(:name, /ISO/) }

    it "matches regex pattern" do
      expect(pred.match?(hash_data)).to be true
    end

    it "does not match non-matching string" do
      expect(pred.match?({ "name" => "IEC 123" })).to be false
    end

    it "handles nil values" do
      expect(pred.match?({ "name" => nil })).to be false
    end

    describe "#negate" do
      it "returns NotMatches" do
        expect(pred.negate).to be_an_instance_of(described_class::NotMatches)
      end
    end
  end

  describe "Nil" do
    let(:pred) { described_class::Nil.new(:status) }

    it "matches nil value" do
      expect(pred.match?({ "status" => nil })).to be true
    end

    it "does not match non-nil value" do
      expect(pred.match?(hash_data)).to be false
    end

    describe "#negate" do
      it "returns NotNil" do
        expect(pred.negate).to be_an_instance_of(described_class::NotNil)
      end
    end
  end

  describe "NotNil" do
    let(:pred) { described_class::NotNil.new(:status) }

    it "matches non-nil value" do
      expect(pred.match?(hash_data)).to be true
    end

    it "does not match nil value" do
      expect(pred.match?({ "status" => nil })).to be false
    end
  end

  describe "factory methods" do
    it "creates correct predicate types" do
      expect(described_class.gt(:x, 1)).to be_an_instance_of(described_class::GreaterThan)
      expect(described_class.lt(:x, 1)).to be_an_instance_of(described_class::LessThan)
      expect(described_class.gte(:x, 1)).to be_an_instance_of(described_class::GreaterThanOrEqual)
      expect(described_class.lte(:x, 1)).to be_an_instance_of(described_class::LessThanOrEqual)
      expect(described_class.not(:x, 1)).to be_an_instance_of(described_class::NotEqual)
      expect(described_class.matches(:x, /y/)).to be_an_instance_of(described_class::Matches)
      expect(described_class.nil(:x)).to be_an_instance_of(described_class::Nil)
      expect(described_class.not_nil(:x)).to be_an_instance_of(described_class::NotNil)
    end
  end

  describe "dual evaluation" do
    it "works on both Hash and model instances" do
      model = Struct.new(:status, :year).new("published", 2023)

      expect(described_class::Equal.new(:status, "published").match?(hash_data)).to be true
      expect(described_class::Equal.new(:status, "published").match?(model)).to be true

      expect(described_class::GreaterThan.new(:year, 2020).match?(hash_data)).to be true
      expect(described_class::GreaterThan.new(:year, 2020).match?(model)).to be true
    end
  end
end
