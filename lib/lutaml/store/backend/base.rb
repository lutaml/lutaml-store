# frozen_string_literal: true

module Lutaml
  module Store
    module Backend
      class Base
        # Initialize the backend with configuration options
        # @param options [Hash] backend-specific configuration options
        def initialize(options = {})
          @options = options
        end

        # Retrieve a value by key
        # @param key [String] the key to retrieve
        # @return [String, nil] the value or nil if not found
        def get(key)
          raise NotImplementedError, "#{self.class} must implement #get"
        end

        # Store a value with a key
        # @param key [String] the key to store
        # @param value [String] the value to store
        # @return [void]
        def set(key, value)
          raise NotImplementedError, "#{self.class} must implement #set"
        end

        # Delete a value by key
        # @param key [String] the key to delete
        # @return [Boolean] true if the key existed and was deleted
        def delete(key)
          raise NotImplementedError, "#{self.class} must implement #delete"
        end

        # Check if a key exists
        # @param key [String] the key to check
        # @return [Boolean] true if the key exists
        def exists?(key)
          raise NotImplementedError, "#{self.class} must implement #exists?"
        end

        # Get all key-value pairs
        # @return [Hash] all stored key-value pairs
        def all
          raise NotImplementedError, "#{self.class} must implement #all"
        end

        # Clear all stored data
        # @return [void]
        def clear
          raise NotImplementedError, "#{self.class} must implement #clear"
        end

        # Get the number of stored items
        # @return [Integer] the number of items
        def size
          raise NotImplementedError, "#{self.class} must implement #size"
        end

        # Get all keys
        # @return [Array<String>] all stored keys
        def keys
          all.keys
        end

        # Get all values
        # @return [Array<String>] all stored values
        def values
          all.values
        end

        protected

        attr_reader :options
      end
    end
  end
end
