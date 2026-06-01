# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Store::Compression do
  describe ".compress and .decompress" do
    let(:test_data) { "Hello, World! This is a test string for compression." }

    context "with gzip compression" do
      it "compresses and decompresses data correctly" do
        compressed = described_class.compress(test_data, "gzip")
        expect(compressed).not_to eq(test_data)
        # NOTE: For small strings, compression might actually increase size due to headers
        # The important thing is that decompression works correctly

        decompressed = described_class.decompress(compressed, "gzip")
        expect(decompressed).to eq(test_data)
      end

      it "supports different compression levels" do
        compressed_1 = described_class.compress(test_data, "gzip", 1)
        compressed_9 = described_class.compress(test_data, "gzip", 9)

        expect(compressed_1.length).to be >= compressed_9.length
        expect(described_class.decompress(compressed_1, "gzip")).to eq(test_data)
        expect(described_class.decompress(compressed_9, "gzip")).to eq(test_data)
      end
    end

    context "with deflate compression" do
      it "compresses and decompresses data correctly" do
        compressed = described_class.compress(test_data, "deflate")
        expect(compressed).not_to eq(test_data)

        decompressed = described_class.decompress(compressed, "deflate")
        expect(decompressed).to eq(test_data)
      end
    end

    context "with unsupported algorithm" do
      it "raises an error for unsupported compression algorithm" do
        expect do
          described_class.compress(test_data, "unsupported")
        end.to raise_error(ArgumentError, /Unsupported compression algorithm/)
      end

      it "raises an error for unsupported decompression algorithm" do
        expect do
          described_class.decompress(test_data, "unsupported")
        end.to raise_error(ArgumentError, /Unsupported compression algorithm/)
      end
    end
  end

  describe ".detect_algorithm" do
    let(:test_data) { "Hello, World!" }

    it "detects gzip compression" do
      compressed = described_class.compress(test_data, "gzip")
      expect(described_class.detect_algorithm(compressed)).to eq("gzip")
    end

    it "detects deflate compression" do
      compressed = described_class.compress(test_data, "deflate")
      expect(described_class.detect_algorithm(compressed)).to eq("deflate")
    end

    it "returns nil for uncompressed data" do
      expect(described_class.detect_algorithm(test_data)).to be_nil
    end
  end

  describe "SUPPORTED_ALGORITHMS" do
    it "includes expected algorithms" do
      expect(described_class::SUPPORTED_ALGORITHMS).to include("gzip", "deflate", "bzip2", "lz4", "zstd")
    end
  end
end
