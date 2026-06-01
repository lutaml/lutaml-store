# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

module IntegrationTestModels
  class TestDocument < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :title, :string
    attribute :content, :string
    attribute :created_at, :string

    key_value do
      map :id, to: :id
      map :title, to: :title
      map :content, to: :content
      map :created_at, to: :created_at
    end
  end

  class TestAuthor < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :email, :string
    attribute :bio, :string

    key_value do
      map :name, to: :name
      map :email, to: :email
      map :bio, to: :bio
    end
  end

  class TestBook < Lutaml::Model::Serializable
    attribute :isbn, :string
    attribute :title, :string
    attribute :author, :string
    attribute :published_year, :integer
    attribute :genre, :string

    key_value do
      map :isbn, to: :isbn
      map :title, to: :title
      map :author, to: :author
      map :published_year, to: :published_year
      map :genre, to: :genre
    end
  end
end

RSpec.describe "Lutaml::Store with Lutaml::Model::Serializable integration" do
  let(:doc_model) { { model: IntegrationTestModels::TestDocument, key: :id, dir: "documents" } }
  let(:author_model) { { model: IntegrationTestModels::TestAuthor, key: :name, dir: "authors" } }
  let(:book_model) { { model: IntegrationTestModels::TestBook, key: :isbn, dir: "books" } }

  describe "single model CRUD" do
    let(:store) { Lutaml::Store.new(adapter: :memory, models: [doc_model]) }
    let(:document) do
      IntegrationTestModels::TestDocument.new(
        id: "doc1", title: "Test Document",
        content: "This is a test", created_at: "2024-01-01"
      )
    end

    it "saves and fetches a Lutaml::Model::Serializable instance" do
      store.save(document)

      retrieved = store.fetch(model: IntegrationTestModels::TestDocument, id: "doc1")
      expect(retrieved).to be_a(IntegrationTestModels::TestDocument)
      expect(retrieved.id).to eq("doc1")
      expect(retrieved.title).to eq("Test Document")
      expect(retrieved.content).to eq("This is a test")
      expect(retrieved.created_at).to eq("2024-01-01")
    end

    it "returns nil for non-existent key" do
      expect(store.fetch(model: IntegrationTestModels::TestDocument, id: "missing")).to be_nil
    end

    it "updates a model with hash attributes" do
      store.save(document)

      updated = store.update(
        model: IntegrationTestModels::TestDocument,
        id: "doc1",
        attributes: { title: "Updated Title" }
      )
      expect(updated.title).to eq("Updated Title")
      expect(updated.content).to eq("This is a test")
    end

    it "updates a model with block" do
      store.save(document)

      updated = store.update(model: IntegrationTestModels::TestDocument, id: "doc1") do |model|
        model.content = "New content"
        model
      end
      expect(updated.content).to eq("New content")
    end

    it "deletes a model" do
      store.save(document)
      expect(store.exists?(model: IntegrationTestModels::TestDocument, id: "doc1")).to be true

      result = store.destroy(model: IntegrationTestModels::TestDocument, id: "doc1")
      expect(result).to be true
      expect(store.fetch(model: IntegrationTestModels::TestDocument, id: "doc1")).to be_nil
    end

    it "reports count and exists" do
      expect(store.count(model: IntegrationTestModels::TestDocument)).to eq(0)

      store.save(document)
      expect(store.count(model: IntegrationTestModels::TestDocument)).to eq(1)
      expect(store.exists?(model: IntegrationTestModels::TestDocument, id: "doc1")).to be true
    end
  end

  describe "model type validation" do
    let(:store) { Lutaml::Store.new(adapter: :memory, models: [doc_model]) }

    it "raises when saving an unregistered model" do
      author = IntegrationTestModels::TestAuthor.new(name: "John Doe", email: "john@example.com")

      expect { store.save(author) }.to raise_error(Lutaml::Store::ModelNotRegisteredError)
    end
  end

  describe "collection operations" do
    let(:store) { Lutaml::Store.new(adapter: :memory, models: [author_model]) }
    let(:authors) do
      [
        IntegrationTestModels::TestAuthor.new(name: "Alice Johnson", email: "alice@example.com", bio: "Fiction writer"),
        IntegrationTestModels::TestAuthor.new(name: "Bob Wilson", email: "bob@example.com", bio: "Technical writer"),
        IntegrationTestModels::TestAuthor.new(name: "Carol Davis", email: "carol@example.com", bio: "Science writer")
      ]
    end

    it "stores multiple models and retrieves all" do
      authors.each { |a| store.save(a) }

      all_authors = store.all(model: IntegrationTestModels::TestAuthor)
      expect(all_authors.size).to eq(3)
      expect(all_authors.map(&:name).sort).to eq(["Alice Johnson", "Bob Wilson", "Carol Davis"])
    end

    it "queries with where" do
      authors.each { |a| store.save(a) }

      fiction = store.where(model: IntegrationTestModels::TestAuthor, bio: "Fiction writer")
      expect(fiction.size).to eq(1)
      expect(fiction.first.name).to eq("Alice Johnson")
    end

    it "updates a model and persists the change" do
      authors.each { |a| store.save(a) }

      store.update(model: IntegrationTestModels::TestAuthor, name: "Alice Johnson") do |model|
        model.bio = "Updated bio: Fiction and mystery writer"
        model
      end

      retrieved = store.fetch(model: IntegrationTestModels::TestAuthor, name: "Alice Johnson")
      expect(retrieved.bio).to eq("Updated bio: Fiction and mystery writer")
    end
  end

  describe "multi-model store" do
    let(:store) { Lutaml::Store.new(adapter: :memory, models: [doc_model, author_model, book_model]) }

    it "stores and retrieves different model types independently" do
      document = IntegrationTestModels::TestDocument.new(id: "doc1", title: "Test Doc")
      author = IntegrationTestModels::TestAuthor.new(name: "John Doe", email: "john@example.com")
      book = IntegrationTestModels::TestBook.new(isbn: "978-123", title: "Test Book", author: "John Doe",
                                                 published_year: 2024, genre: "Fiction")

      store.save(document)
      store.save(author)
      store.save(book)

      expect(store.count(model: IntegrationTestModels::TestDocument)).to eq(1)
      expect(store.count(model: IntegrationTestModels::TestAuthor)).to eq(1)
      expect(store.count(model: IntegrationTestModels::TestBook)).to eq(1)

      fetched_doc = store.fetch(model: IntegrationTestModels::TestDocument, id: "doc1")
      fetched_author = store.fetch(model: IntegrationTestModels::TestAuthor, name: "John Doe")
      fetched_book = store.fetch(model: IntegrationTestModels::TestBook, isbn: "978-123")

      expect(fetched_doc).to be_a(IntegrationTestModels::TestDocument)
      expect(fetched_author).to be_a(IntegrationTestModels::TestAuthor)
      expect(fetched_book).to be_a(IntegrationTestModels::TestBook)
    end

    it "isolates where queries by model type" do
      store.save(IntegrationTestModels::TestDocument.new(id: "d1", title: "Ruby Guide"))
      store.save(IntegrationTestModels::TestBook.new(isbn: "b1", title: "Ruby Guide", author: "Author"))

      docs = store.where(model: IntegrationTestModels::TestDocument, title: "Ruby Guide")
      books = store.where(model: IntegrationTestModels::TestBook, title: "Ruby Guide")

      expect(docs.size).to eq(1)
      expect(docs.first).to be_a(IntegrationTestModels::TestDocument)
      expect(books.size).to eq(1)
      expect(books.first).to be_a(IntegrationTestModels::TestBook)
    end
  end

  describe "file I/O round-trip" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(tmpdir) }

    let(:store) { Lutaml::Store.new(adapter: :memory, models: [book_model]) }
    let(:books) do
      [
        IntegrationTestModels::TestBook.new(isbn: "978-0123456789", title: "Ruby Programming", author: "Jane Smith",
                                            published_year: 2023, genre: "Programming"),
        IntegrationTestModels::TestBook.new(isbn: "978-9876543210", title: "Go Programming", author: "Bob Jones",
                                            published_year: 2024, genre: "Programming")
      ]
    end

    it "round-trips through YAML separate layout" do
      store.save_all(books, path: tmpdir, format: :yaml, layout: :separate)

      fresh_store = Lutaml::Store.new(adapter: :memory, models: [book_model])
      loaded = fresh_store.load_all(IntegrationTestModels::TestBook, path: tmpdir, format: :yaml, layout: :separate)

      expect(loaded.size).to eq(2)
      expect(loaded.map(&:title).sort).to eq(["Go Programming", "Ruby Programming"])
    end

    it "round-trips through JSON separate layout" do
      store.save_all(books, path: tmpdir, format: :json, layout: :separate)

      fresh_store = Lutaml::Store.new(adapter: :memory, models: [book_model])
      loaded = fresh_store.load_all(IntegrationTestModels::TestBook, path: tmpdir, format: :json, layout: :separate)

      expect(loaded.size).to eq(2)
      expect(loaded.map(&:author).sort).to eq(["Bob Jones", "Jane Smith"])
    end
  end

  describe "import_all workflow" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(tmpdir) }

    let(:store) { Lutaml::Store.new(adapter: :memory, models: [doc_model]) }
    let(:documents) do
      [
        IntegrationTestModels::TestDocument.new(id: "doc1", title: "First Document", content: "Content 1"),
        IntegrationTestModels::TestDocument.new(id: "doc2", title: "Second Document", content: "Content 2")
      ]
    end

    it "loads from directory and makes models queryable" do
      store.save_all(documents, path: tmpdir, format: :yaml, layout: :separate)

      fresh_store = Lutaml::Store.new(adapter: :memory, models: [doc_model])
      loaded = fresh_store.import_all(IntegrationTestModels::TestDocument, path: tmpdir, format: :yaml,
                                                                           layout: :separate)

      expect(loaded.size).to eq(2)

      # Queryable via fetch
      doc1 = fresh_store.fetch(model: IntegrationTestModels::TestDocument, id: "doc1")
      expect(doc1).not_to be_nil
      expect(doc1.title).to eq("First Document")

      # Queryable via where
      second = fresh_store.where(model: IntegrationTestModels::TestDocument, title: "Second Document")
      expect(second.size).to eq(1)
      expect(second.first.content).to eq("Content 2")

      # Queryable via count
      expect(fresh_store.count(model: IntegrationTestModels::TestDocument)).to eq(2)
    end
  end

  describe "statistics" do
    let(:store) { Lutaml::Store.new(adapter: :memory, models: [doc_model]) }

    it "reports registered models and counts" do
      store.save(IntegrationTestModels::TestDocument.new(id: "doc1", title: "Test"))

      stats = store.stats
      expect(stats[:models_registered]).to eq(1)
      expect(stats[:total_models]).to eq(1)
      expect(stats[:registered_models]).to include("IntegrationTestModels::TestDocument")
    end
  end
end
