# frozen_string_literal: true

require "digest"

module Lutaml
  module Store
    class Integrity
      class IntegrityError < StandardError; end
      class CorruptionError < IntegrityError; end
      class ChecksumMismatchError < IntegrityError; end

      def self.calculate_checksum(data, algorithm = "sha256")
        # Convert data to string if it's not already
        string_data = data.is_a?(String) ? data : data.to_s

        case algorithm.to_s.downcase
        when "md5"
          Digest::MD5.hexdigest(string_data)
        when "sha1"
          Digest::SHA1.hexdigest(string_data)
        when "sha256"
          Digest::SHA256.hexdigest(string_data)
        when "sha512"
          Digest::SHA512.hexdigest(string_data)
        else
          raise ArgumentError, "Unsupported checksum algorithm: #{algorithm}"
        end
      end

      def self.verify_checksum(data, expected_checksum, algorithm = "sha256")
        actual_checksum = calculate_checksum(data, algorithm)
        unless actual_checksum == expected_checksum
          raise ChecksumMismatchError,
                "Checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}"
        end
        true
      end

      def self.create_integrity_metadata(data, algorithm = "sha256")
        string_data = data.is_a?(String) ? data : data.to_s
        {
          checksum: calculate_checksum(data, algorithm),
          algorithm: algorithm,
          size: string_data.bytesize,
          created_at: Time.now.utc.iso8601,
          version: "1.0"
        }
      end

      def self.verify_integrity_metadata(data, metadata)
        string_data = data.is_a?(String) ? data : data.to_s

        # Verify size
        if metadata[:size] && string_data.bytesize != metadata[:size]
          raise CorruptionError,
                "Size mismatch: expected #{metadata[:size]}, got #{string_data.bytesize}"
        end

        # Verify checksum
        verify_checksum(data, metadata[:checksum], metadata[:algorithm]) if metadata[:checksum] && metadata[:algorithm]

        true
      end

      def self.repair_data(corrupted_data, backup_data = nil)
        # Basic repair attempt - in a real implementation, this could be more sophisticated
        return backup_data if backup_data && valid_data?(backup_data)

        # Try to clean up common corruption patterns
        cleaned_data = corrupted_data.dup

        # Remove null bytes that might have been introduced
        cleaned_data.gsub!("\x00", "")

        # Try to fix truncated JSON/YAML
        if cleaned_data.strip.start_with?("{") && !cleaned_data.strip.end_with?("}")
          cleaned_data += "}"
        elsif cleaned_data.strip.start_with?("[") && !cleaned_data.strip.end_with?("]")
          cleaned_data += "]"
        end

        cleaned_data
      end

      def self.valid_data?(data)
        return false if data.nil? || data.empty?
        return false if data.include?("\x00") # Contains null bytes

        # Basic validation - data should be valid UTF-8 or binary
        begin
          data.encode("UTF-8")
          true
        rescue Encoding::UndefinedConversionError
          # Might be binary data, which is also valid
          true
        rescue StandardError
          false
        end
      end
    end
  end
end
