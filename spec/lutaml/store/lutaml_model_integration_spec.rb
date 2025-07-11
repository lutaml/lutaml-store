# frozen_string_literal: true

require "spec_helper"

# Create fake Lutaml::Model::Serializable classes for testing
module Lutaml
  module Model
    class Serializable
      attr_reader :attributes

      def initialize(attributes = {})
        @attributes = attributes.dup
        # Define accessor methods for each attribute without using singleton methods
        @attributes.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
      end

      # Define method_missing to handle attribute access
      def method_missing(method_name, *args, &block)
        method_str = method_name.to_s
        if method_str.end_with?('=')
          # Setter method
          attr_name = method_str.chomp('=').to_sym
          if @attributes.key?(attr_name)
            value = args.first
            @attributes[attr_name] = value
            instance_variable_set("@#{attr_name}", value)
            return value
          end
        elsif @attributes.key?(method_name)
          # Getter method
          return @attributes[method_name]
        end
        super
      end

      def respond_to_missing?(method_name, include_private = false)
        method_str = method_name.to_s
        if method_str.end_with?('=')
          attr_name = method_str.chomp('=').to_sym
          @attributes.key?(attr_name)
        else
          @attributes.key?(method_name)
        end || super
      end

      def to_h
        @attributes.dup
      end

      def to_json(*args)
        JSON.generate(to_h)
      end

      def to_yaml
        YAML.dump(to_h)
      end

      def to_xml
        # Simple XML representation for testing
        root = self.class.name.split('::').last.downcase
        content = @attributes.map { |k, v| "  <#{k}>#{v}</#{k}>" }.join("\n")
        "<#{root}>\n#{content}\n</#{root}>"
      end

      def self.from_hash(hash)
        # Convert string keys to symbols for consistency
        symbolized_hash = {}
        hash.each do |key, value|
          symbolized_hash[key.to_sym] = value
        end
        new(symbolized_hash)
      end

      def self.from_json(json_string)
        hash = JSON.parse(json_string)
        from_hash(hash)
      end

      def self.from_yaml(yaml_string)
        hash = YAML.safe_load(yaml_string)
        from_hash(hash)
      end

      def self.from_xml(xml_string)
        # Simple XML parsing for testing - in reality this would be more complex
        # Extract attributes from simple XML format
        attributes = {}
        xml_string.scan(/<(\w+)>([^<]+)<\/\1>/) do |key, value|
          attributes[key.to_sym] = value
        end
        from_hash(attributes)
      end

      def ==(other)
        other.is_a?(self.class) && @attributes == other.attributes
      end

      # Add marshal support
      def marshal_dump
        [@attributes, self.class]
      end

      def marshal_load(data)
        @attributes, klass = data
        @attributes.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
      end
    end
  end
end

# Test models using Lutaml::Model::Serializable
class TestDocument < Lutaml::Model::Serializable
  def initialize(attributes = {})
    super({
      id: nil,
      title: nil,
      content: nil,
      created_at: nil
    }.merge(attributes))
  end
end

class TestAuthor < Lutaml::Model::Serializable
  def initialize(attributes = {})
    super({
      name: nil,
      email: nil,
      bio: nil
    }.merge(attributes))
  end
end

class TestBook < Lutaml::Model::Serializable
  def initialize(attributes = {})
    super({
      isbn: nil,
      title: nil,
      author: nil,
      published_year: nil,
      genre: nil
    }.merge(attributes))
  end
end

RSpec.describe "Lutaml::Store with Lutaml::Model::Serializable integration" do
  let(:config) { { "backend" => { "type" => "memory" } } }

  describe "with TestDocument model" do
    let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestDocument, format: :marshal) }
    let(:document) { TestDocument.new(id: "doc1", title: "Test Document", content: "This is a test", created_at: "2024-01-01") }

    it "stores and retrieves Lutaml::Model::Serializable instances" do
      store.store_model("doc1", document)
      retrieved = store.get_model("doc1")

      expect(retrieved).to be_a(TestDocument)
      expect(retrieved.id).to eq("doc1")
      expect(retrieved.title).to eq("Test Document")
      expect(retrieved.content).to eq("This is a test")
      expect(retrieved.created_at).to eq("2024-01-01")
    end

    it "validates model type" do
      author = TestAuthor.new(name: "John Doe", email: "john@example.com")

      expect {
        store.store_model("invalid", author)
      }.to raise_error(ArgumentError, /Expected TestDocument/)
    end
  end

  describe "with different serialization formats" do
    let(:book) { TestBook.new(isbn: "978-0123456789", title: "Ruby Programming", author: "Jane Smith", published_year: 2023, genre: "Programming") }

    context "with JSON format" do
      let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestBook, format: :json) }

      it "serializes and deserializes using JSON" do
        store.store_model("book1", book)
        retrieved = store.get_model("book1")

        expect(retrieved).to be_a(TestBook)
        expect(retrieved.isbn).to eq("978-0123456789")
        expect(retrieved.title).to eq("Ruby Programming")
        expect(retrieved.author).to eq("Jane Smith")
      end
    end

    context "with YAML format" do
      let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestBook, format: :yaml) }

      it "serializes and deserializes using YAML" do
        store.store_model("book1", book)
        retrieved = store.get_model("book1")

        expect(retrieved).to be_a(TestBook)
        expect(retrieved.isbn).to eq("978-0123456789")
        expect(retrieved.title).to eq("Ruby Programming")
        expect(retrieved.author).to eq("Jane Smith")
      end
    end

    context "with hash format" do
      let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestBook, format: :hash) }

      it "serializes and deserializes using hash" do
        store.store_model("book1", book)
        retrieved = store.get_model("book1")

        expect(retrieved).to be_a(TestBook)
        expect(retrieved.isbn).to eq("978-0123456789")
        expect(retrieved.title).to eq("Ruby Programming")
        expect(retrieved.author).to eq("Jane Smith")
      end
    end
  end

  describe "collection operations with Lutaml::Model instances" do
    let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestAuthor, format: :json) }
    let(:authors) do
      [
        TestAuthor.new(name: "Alice Johnson", email: "alice@example.com", bio: "Fiction writer"),
        TestAuthor.new(name: "Bob Wilson", email: "bob@example.com", bio: "Technical writer"),
        TestAuthor.new(name: "Carol Davis", email: "carol@example.com", bio: "Science writer")
      ]
    end

    it "stores multiple models with default key generator" do
      store.store_models(authors)

      expect(store.model_count).to eq(3)
      expect(store.model_keys).to include("testauthor_0", "testauthor_1", "testauthor_2")

      first_author = store.get_model("testauthor_0")
      expect(first_author).to be_a(TestAuthor)
      expect(first_author.name).to eq("Alice Johnson")
    end

    it "stores multiple models with custom key generator" do
      key_gen = ->(model, _) { "author_#{model.name.downcase.gsub(' ', '_')}" }
      store.store_models(authors, key_gen)

      alice = store.get_model("author_alice_johnson")
      expect(alice).to be_a(TestAuthor)
      expect(alice.name).to eq("Alice Johnson")
      expect(alice.email).to eq("alice@example.com")
    end

    it "finds models by criteria" do
      store.store_models(authors)

      fiction_writers = store.find_models { |key, model| model.bio.include?("Fiction") }
      expect(fiction_writers.size).to eq(1)
      expect(fiction_writers.values.first.name).to eq("Alice Johnson")
    end

    it "updates models" do
      store.store_models(authors)

      updated = store.update_model("testauthor_0") do |model|
        model.bio = "Updated bio: Fiction and mystery writer"
        model
      end

      expect(updated.bio).to eq("Updated bio: Fiction and mystery writer")

      retrieved = store.get_model("testauthor_0")
      expect(retrieved.bio).to eq("Updated bio: Fiction and mystery writer")
    end
  end

  describe "export and import operations" do
    let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestDocument, format: :marshal) }
    let(:documents) do
      [
        TestDocument.new(id: "doc1", title: "First Document", content: "Content 1"),
        TestDocument.new(id: "doc2", title: "Second Document", content: "Content 2")
      ]
    end

    before do
      documents.each_with_index do |doc, index|
        store.store_model("doc#{index + 1}", doc)
      end
    end

    it "exports models to JSON format" do
      exported = {}
      store.export_models(:json) do |key, serialized|
        exported[key] = serialized
      end

      expect(exported.size).to eq(2)
      expect(exported["doc1"]).to be_a(String)

      parsed = JSON.parse(exported["doc1"])
      # With polymorphic support, data is wrapped with type information
      if parsed.key?("_data")
        expect(parsed["_type"]).to eq("TestDocument")
        expect(parsed["_data"]["title"]).to eq("First Document")
      else
        # Fallback for non-polymorphic serialization
        expect(parsed["title"]).to eq("First Document")
      end
    end

    it "imports models from JSON format" do
      # Export to JSON first
      exported = {}
      store.export_models(:json) { |key, data| exported[key] = data }

      # Clear and import back
      store.clear_models
      expect(store.model_count).to eq(0)

      store.import_models(exported, :json)
      expect(store.model_count).to eq(2)

      doc1 = store.get_model("doc1")
      expect(doc1).to be_a(TestDocument)
      expect(doc1.title).to eq("First Document")
      expect(doc1.content).to eq("Content 1")
    end
  end

  describe "polymorphic model support" do
    let(:store) { Lutaml::Store::ModelStore.new(config, format: :json) }

    it "stores different model types without model_class restriction" do
      document = TestDocument.new(id: "doc1", title: "Test Doc")
      author = TestAuthor.new(name: "John Doe", email: "john@example.com")
      book = TestBook.new(isbn: "123", title: "Test Book")

      store.store_model("item1", document)
      store.store_model("item2", author)
      store.store_model("item3", book)

      expect(store.model_count).to eq(3)

      retrieved_doc = store.get_model("item1")
      retrieved_author = store.get_model("item2")
      retrieved_book = store.get_model("item3")

      expect(retrieved_doc).to be_a(TestDocument)
      expect(retrieved_author).to be_a(TestAuthor)
      expect(retrieved_book).to be_a(TestBook)
    end
  end

  describe "statistics with Lutaml::Model instances" do
    let(:store) { Lutaml::Store::ModelStore.new(config, model_class: TestDocument, format: :yaml) }

    it "provides model-specific statistics" do
      document = TestDocument.new(id: "doc1", title: "Test Document")
      store.store_model("doc1", document)

      stats = store.stats
      expect(stats[:model_class]).to eq("TestDocument")
      expect(stats[:format]).to eq(:yaml)
      expect(stats[:model_count]).to eq(1)
    end
  end
end
