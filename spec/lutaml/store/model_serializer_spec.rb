# frozen_string_literal: true

require "spec_helper"

module ModelSerializerTestModels
  class SerialBook < Lutaml::Model::Serializable
    attribute :isbn, :string
    attribute :title, :string
    attribute :author, :string
  end

  class SerialEbook < SerialBook
    attribute :format, :string
  end
end

RSpec.describe Lutaml::Store::ModelSerializer do
  subject(:serializer) { described_class.new }

  describe "#serialize" do
    it "serializes a model to a hash with class metadata" do
      book = ModelSerializerTestModels::SerialBook.new(isbn: "978-123", title: "Test Book", author: "Author")
      result = serializer.serialize(book)

      expect(result).to be_a(Hash)
      expect(result["_class"]).to eq("ModelSerializerTestModels::SerialBook")
      expect(result["isbn"]).to eq("978-123")
      expect(result["title"]).to eq("Test Book")
      expect(result["author"]).to eq("Author")
    end

    it "serializes a subclass with correct class name" do
      ebook = ModelSerializerTestModels::SerialEbook.new(isbn: "978-456", title: "Digital Book", format: "epub")
      result = serializer.serialize(ebook)

      expect(result["_class"]).to eq("ModelSerializerTestModels::SerialEbook")
      expect(result["format"]).to eq("epub")
    end
  end

  describe "#deserialize" do
    it "deserializes a hash to the correct model class" do
      data = {
        "_class" => "ModelSerializerTestModels::SerialBook",
        "isbn" => "978-123",
        "title" => "Test Book",
        "author" => "Author"
      }

      result = serializer.deserialize(data, ModelSerializerTestModels::SerialBook)

      expect(result).to be_a(ModelSerializerTestModels::SerialBook)
      expect(result.isbn).to eq("978-123")
      expect(result.title).to eq("Test Book")
    end

    it "deserializes to a subclass when class metadata indicates it" do
      data = {
        "_class" => "ModelSerializerTestModels::SerialEbook",
        "isbn" => "978-456",
        "title" => "Digital",
        "format" => "epub"
      }

      result = serializer.deserialize(data, ModelSerializerTestModels::SerialBook)

      expect(result).to be_a(ModelSerializerTestModels::SerialEbook)
      expect(result.format).to eq("epub")
    end

    it "rejects incompatible polymorphic types" do
      data = {
        "_class" => "ModelSerializerTestModels::SerialBook",
        "isbn" => "978-123"
      }

      expect do
        serializer.deserialize(data, ModelSerializerTestModels::SerialEbook)
      end.to raise_error(Lutaml::Store::PolymorphicUpdateError, /not compatible/)
    end

    it "raises on invalid data (missing _class)" do
      data = { "isbn" => "978-123" }

      expect do
        serializer.deserialize(data, ModelSerializerTestModels::SerialBook)
      end.to raise_error(Lutaml::Store::CompositeModelError, /Invalid serialized data/)
    end

    it "raises on invalid data (not a Hash)" do
      expect do
        serializer.deserialize("not a hash", ModelSerializerTestModels::SerialBook)
      end.to raise_error(Lutaml::Store::CompositeModelError, /Invalid serialized data/)
    end

    it "raises on unresolvable class name" do
      data = { "_class" => "NonExistentClass", "isbn" => "123" }

      expect do
        serializer.deserialize(data, ModelSerializerTestModels::SerialBook)
      end.to raise_error(Lutaml::Store::CompositeModelError, /Cannot resolve class/)
    end

    it "strips internal metadata keys from model data" do
      data = {
        "_class" => "ModelSerializerTestModels::SerialBook",
        "_composite_models" => { "studio" => { "storage_key" => "key1" } },
        "isbn" => "978-123",
        "title" => "Test"
      }

      result = serializer.deserialize(data, ModelSerializerTestModels::SerialBook)

      expect(result.isbn).to eq("978-123")
      expect(result.title).to eq("Test")
    end
  end

  describe "round-trip" do
    it "serializes and deserializes preserving all attributes" do
      book = ModelSerializerTestModels::SerialBook.new(isbn: "978-789", title: "Round Trip", author: "Traveler")
      serialized = serializer.serialize(book)
      deserialized = serializer.deserialize(serialized, ModelSerializerTestModels::SerialBook)

      expect(deserialized.isbn).to eq("978-789")
      expect(deserialized.title).to eq("Round Trip")
      expect(deserialized.author).to eq("Traveler")
    end

    it "preserves subclass identity through round-trip" do
      ebook = ModelSerializerTestModels::SerialEbook.new(isbn: "978-000", title: "E-Book", author: "Digital",
                                                         format: "mobi")
      serialized = serializer.serialize(ebook)
      deserialized = serializer.deserialize(serialized, ModelSerializerTestModels::SerialBook)

      expect(deserialized).to be_a(ModelSerializerTestModels::SerialEbook)
      expect(deserialized.format).to eq("mobi")
    end
  end
end
