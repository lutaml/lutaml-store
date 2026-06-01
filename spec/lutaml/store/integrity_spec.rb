# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Integrity do
  describe ".calculate_checksum" do
    let(:test_data) { "Hello, World!" }

    it "calculates SHA256 checksum by default" do
      checksum = described_class.calculate_checksum(test_data)
      expect(checksum).to eq(Digest::SHA256.hexdigest(test_data))
    end

    it "calculates MD5 checksum" do
      checksum = described_class.calculate_checksum(test_data, "md5")
      expect(checksum).to eq(Digest::MD5.hexdigest(test_data))
    end

    it "calculates SHA1 checksum" do
      checksum = described_class.calculate_checksum(test_data, "sha1")
      expect(checksum).to eq(Digest::SHA1.hexdigest(test_data))
    end

    it "raises error for unsupported algorithm" do
      expect do
        described_class.calculate_checksum(test_data, "unsupported")
      end.to raise_error(ArgumentError, /Unsupported checksum algorithm/)
    end
  end

  describe ".verify_checksum" do
    let(:test_data) { "Hello, World!" }
    let(:correct_checksum) { Digest::SHA256.hexdigest(test_data) }
    let(:incorrect_checksum) { "incorrect" }

    it "returns true for correct checksum" do
      expect(described_class.verify_checksum(test_data, correct_checksum)).to be true
    end

    it "raises ChecksumMismatchError for incorrect checksum" do
      expect do
        described_class.verify_checksum(test_data, incorrect_checksum)
      end.to raise_error(Lutaml::Store::Integrity::ChecksumMismatchError)
    end
  end

  describe ".create_integrity_metadata" do
    let(:test_data) { "Hello, World!" }

    it "creates integrity metadata with checksum and size" do
      metadata = described_class.create_integrity_metadata(test_data)

      expect(metadata).to have_key(:checksum)
      expect(metadata).to have_key(:algorithm)
      expect(metadata).to have_key(:size)
      expect(metadata).to have_key(:created_at)
      expect(metadata).to have_key(:version)

      expect(metadata[:checksum]).to eq(Digest::SHA256.hexdigest(test_data))
      expect(metadata[:algorithm]).to eq("sha256")
      expect(metadata[:size]).to eq(test_data.bytesize)
      expect(metadata[:version]).to eq("1.0")
    end

    it "uses specified algorithm" do
      metadata = described_class.create_integrity_metadata(test_data, "md5")

      expect(metadata[:checksum]).to eq(Digest::MD5.hexdigest(test_data))
      expect(metadata[:algorithm]).to eq("md5")
    end
  end

  describe ".verify_integrity_metadata" do
    let(:test_data) { "Hello, World!" }
    let(:valid_metadata) do
      {
        checksum: Digest::SHA256.hexdigest(test_data),
        algorithm: "sha256",
        size: test_data.bytesize
      }
    end

    it "returns true for valid metadata" do
      expect(described_class.verify_integrity_metadata(test_data, valid_metadata)).to be true
    end

    it "raises CorruptionError for size mismatch" do
      invalid_metadata = valid_metadata.merge(size: 999)

      expect do
        described_class.verify_integrity_metadata(test_data, invalid_metadata)
      end.to raise_error(Lutaml::Store::Integrity::CorruptionError, /Size mismatch/)
    end

    it "raises ChecksumMismatchError for checksum mismatch" do
      invalid_metadata = valid_metadata.merge(checksum: "invalid")

      expect do
        described_class.verify_integrity_metadata(test_data, invalid_metadata)
      end.to raise_error(Lutaml::Store::Integrity::ChecksumMismatchError)
    end

    it "returns true when no integrity metadata is present" do
      expect(described_class.verify_integrity_metadata(test_data, {})).to be true
    end
  end

  describe ".repair_data" do
    let(:corrupted_data) { "Hello, Wor\x00ld!" }
    let(:backup_data) { "Hello, World!" }

    it "returns backup data if available and valid" do
      repaired = described_class.repair_data(corrupted_data, backup_data)
      expect(repaired).to eq(backup_data)
    end

    it "attempts to clean corrupted data" do
      repaired = described_class.repair_data(corrupted_data)
      expect(repaired).to eq("Hello, World!")
    end

    it "fixes truncated JSON" do
      corrupted_json = '{"key": "value"'
      repaired = described_class.repair_data(corrupted_json)
      expect(repaired).to eq('{"key": "value"}')
    end

    it "fixes truncated arrays" do
      corrupted_array = '["item1", "item2"'
      repaired = described_class.repair_data(corrupted_array)
      expect(repaired).to eq('["item1", "item2"]')
    end
  end

  describe ".valid_data?" do
    it "returns true for valid UTF-8 string" do
      expect(described_class.valid_data?("Hello, World!")).to be true
    end

    it "returns false for nil data" do
      expect(described_class.valid_data?(nil)).to be false
    end

    it "returns false for empty data" do
      expect(described_class.valid_data?("")).to be false
    end

    it "returns false for data with null bytes" do
      expect(described_class.valid_data?("Hello\x00World")).to be false
    end

    it "returns true for binary data" do
      binary_data = "\xFF\xFE\xFD".dup.force_encoding("ASCII-8BIT")
      expect(described_class.valid_data?(binary_data)).to be true
    end
  end
end
