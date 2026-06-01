# frozen_string_literal: true

require "zlib"
require "stringio"

module Lutaml
  module Store
    class Compression
      SUPPORTED_ALGORITHMS = %w[gzip deflate bzip2 lz4 zstd].freeze

      def self.compress(data, algorithm = "gzip", level = 6)
        case algorithm.to_s.downcase
        when "gzip"
          compress_gzip(data, level)
        when "deflate"
          compress_deflate(data, level)
        when "bzip2"
          compress_bzip2(data, level)
        when "lz4"
          compress_lz4(data)
        when "zstd"
          compress_zstd(data, level)
        else
          raise ArgumentError,
                "Unsupported compression algorithm: #{algorithm}. Supported: #{SUPPORTED_ALGORITHMS.join(", ")}"
        end
      end

      def self.decompress(data, algorithm = "gzip")
        case algorithm.to_s.downcase
        when "gzip"
          decompress_gzip(data)
        when "deflate"
          decompress_deflate(data)
        when "bzip2"
          decompress_bzip2(data)
        when "lz4"
          decompress_lz4(data)
        when "zstd"
          decompress_zstd(data)
        else
          raise ArgumentError,
                "Unsupported compression algorithm: #{algorithm}. Supported: #{SUPPORTED_ALGORITHMS.join(", ")}"
        end
      end

      def self.detect_algorithm(data)
        return nil unless data.is_a?(String)

        # Force binary encoding for magic number detection
        binary_data = data.dup.force_encoding("ASCII-8BIT")

        # Define magic numbers as binary strings
        gzip_magic = "\x1f\x8b".b
        deflate_magic = "\x78".b
        bzip2_magic = "BZ".b
        lz4_magic = "\x04\"M\x18".b
        zstd_magic = "\x28\xb5\x2f\xfd".b

        # Check magic numbers
        return "gzip" if binary_data.start_with?(gzip_magic)
        return "deflate" if binary_data.start_with?(deflate_magic)
        return "bzip2" if binary_data.start_with?(bzip2_magic)
        return "lz4" if binary_data.start_with?(lz4_magic)
        return "zstd" if binary_data.start_with?(zstd_magic)

        nil # No compression detected
      end

      def self.compress_gzip(data, level)
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io, level)
        gz.write(data)
        gz.close
        io.string
      end

      def self.decompress_gzip(data)
        io = StringIO.new(data)
        gz = Zlib::GzipReader.new(io)
        result = gz.read
        gz.close
        result
      end

      def self.compress_deflate(data, level)
        Zlib::Deflate.deflate(data, level)
      end

      def self.decompress_deflate(data)
        Zlib::Inflate.inflate(data)
      end

      def self.compress_bzip2(data, level)
        require "bzip2-ffi"
        Bzip2::FFI.compress(data, level)
      rescue LoadError
        raise ArgumentError, "bzip2-ffi gem is required for bzip2 compression"
      end

      def self.decompress_bzip2(data)
        require "bzip2-ffi"
        Bzip2::FFI.decompress(data)
      rescue LoadError
        raise ArgumentError, "bzip2-ffi gem is required for bzip2 compression"
      end

      def self.compress_lz4(data)
        require "lz4-ruby"
        LZ4.compress(data)
      rescue LoadError
        raise ArgumentError, "lz4-ruby gem is required for LZ4 compression"
      end

      def self.decompress_lz4(data)
        require "lz4-ruby"
        LZ4.decompress(data)
      rescue LoadError
        raise ArgumentError, "lz4-ruby gem is required for LZ4 compression"
      end

      def self.compress_zstd(data, level)
        require "zstd-ruby"
        Zstd.compress(data, level: level)
      rescue LoadError
        raise ArgumentError, "zstd-ruby gem is required for Zstd compression"
      end

      def self.decompress_zstd(data)
        require "zstd-ruby"
        Zstd.decompress(data)
      rescue LoadError
        raise ArgumentError, "zstd-ruby gem is required for Zstd compression"
      end
    end
  end
end
