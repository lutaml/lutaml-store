# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Lutaml::Store::Source do
  describe ".for" do
    it "raises ConfigurationError for an unknown type" do
      expect { described_class.for(:oracle, path: "/x") }
        .to raise_error(Lutaml::Store::ConfigurationError, /unknown source type/)
    end

    it "raises ConfigurationError when a required option is missing" do
      expect { described_class.for(:directory) }
        .to raise_error(Lutaml::Store::ConfigurationError, /requires: :path/)
    end

    it "builds each registered type" do
      expect(described_class.for(:directory, path: Dir.mktmpdir)).to be_a(described_class::Directory)
      expect(described_class.for(:https, base_url: "https://example.test/x"))
        .to be_a(described_class::Https)
      expect(described_class.for(:rest, base_url: "https://example.test", collection: "ietf"))
        .to be_a(described_class::Rest)
    end
  end

  describe ".encode_key" do
    it "maps a storage key to one path segment" do
      expect(described_class.encode_key("RFC 3986")).to eq("RFC+3986")
      expect(described_class.encode_key("ISO 19115-1:2014")).to eq("ISO+19115-1%3A2014")
    end
  end
end

RSpec.describe Lutaml::Store::Source::Directory do
  let(:root) { Dir.mktmpdir }
  let(:source) { described_class.new(path: root) }

  before do
    FileUtils.mkdir_p(File.join(root, "entries"))
    File.write(File.join(root, "entries", "rfc7231.yaml"), "id: RFC7231\n")
    File.write(File.join(root, "manifest.json"),
               JSON.generate({ version: 1, count: 1,
                               entries: [{ key: "RFC 7231",
                                           location: "entries/rfc7231.yaml" }] }))
  end

  it "reads an entry by key" do
    expect(source.read("RFC 7231")).to eq("id: RFC7231\n")
  end

  it "raises NotFoundError for a definitive miss" do
    expect { source.read("RFC 9999") }.to raise_error(Lutaml::Store::NotFoundError)
  end

  it "enumerates keys from the manifest" do
    expect(source.keys).to eq(["RFC 7231"])
  end

  it "returns typed records with a consumer-declared model" do
    record = Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
    end
    expect(source.get("RFC 7231", record).id).to eq("RFC7231")
  end
end

RSpec.describe Lutaml::Store::Source::Zip do
  let(:zip_path) { File.join(Dir.mktmpdir, "pkg.zip") }

  let(:source) { described_class.new(path: zip_path) }

  before do
    require "zip"
    FileUtils.mkdir_p(File.dirname(zip_path))
    Zip::File.open(zip_path, create: true) do |zip|
      zip.get_output_stream("manifest.json") do |f|
        f.write(JSON.generate({ version: 1, count: 1,
                                entries: [{ key: "RFC 7231",
                                            location: "entries/rfc7231.yaml" }] }))
      end
      zip.get_output_stream("entries/rfc7231.yaml") { |f| f.write("id: RFC7231\n") }
    end
  end

  it "reads entries in place from the package" do
    expect(source.read("RFC 7231")).to eq("id: RFC7231\n")
    expect(source.keys).to eq(["RFC 7231"])
  end

  it "raises ConfigurationError for a missing package file" do
    expect { described_class.new(path: "/nonexistent/pkg.zip") }
      .to raise_error(Lutaml::Store::ConfigurationError)
  end
end

RSpec.describe Lutaml::Store::Source::Https do
  let(:base) { "https://records.example.test/repos/ietf" }
  let(:transport) { instance_double(Proc) }

  def transport_of(routes)
    lambda do |uri, _headers|
      path = uri.path.sub(%r{\A/repos/ietf/?}, "")
      route = routes[path] || routes[uri.to_s]
      route || { status_code: 404, headers: {}, body: "" }
    end
  end

  it "fetches a percent-encoded key path under the base URL" do
    routes = { "RFC+3986.yaml" =>
      { status_code: 200, headers: {}, body: "id: RFC3986\n" } }
    src = described_class.new(base_url: base, transport: transport_of(routes))

    expect(src.read("RFC 3986.yaml")).to eq("id: RFC3986\n")
  end

  it "splits a definitive 404 from a transport failure" do
    src = described_class.new(base_url: base, transport: transport_of({}))
    expect { src.read("RFC 9999") }.to raise_error(Lutaml::Store::NotFoundError)
  end

  it "wraps network failures in BackendError" do
    boom = ->(_uri, _h) { raise SocketError, "no route" }
    src = described_class.new(base_url: base, transport: boom)
    expect { src.read("RFC 3986") }.to raise_error(Lutaml::Store::BackendError, /no route/)
  end

  it "follows redirects up to the configured budget" do
    calls = 0
    hop = lambda do |uri, _h|
      calls += 1
      if uri.to_s.end_with?("a")
        { status_code: 302, headers: { "location" => "#{base}/b" }, body: "" }
      else
        { status_code: 200, headers: {}, body: "landed" }
      end
    end
    src = described_class.new(base_url: base, transport: hop)
    expect(src.read("a")).to eq("landed")
    expect(calls).to eq(2)
  end
end

RSpec.describe Lutaml::Store::Source::Rest do
  let(:base) { "https://cloud.example.test" }

  def rest(routes)
    described_class.new(base_url: base, collection: "ietf", transport: lambda do |uri, _h|
      path = uri.path.sub(%r{\A/}, "")
      routes.fetch(path) { { status_code: 404, headers: {}, body: "" } }
    end)
  end

  it "reads entries through the contract paths" do
    routes = {
      "collections/ietf/entries/RFC+7231" =>
        { status_code: 200, headers: {}, body: "id: RFC7231\n" }
    }
    expect(rest(routes).read("RFC 7231")).to eq("id: RFC7231\n")
  end

  it "parses the collection manifest" do
    routes = {
      "collections/ietf/manifest" => {
        status_code: 200, headers: {},
        body: JSON.generate({ version: 1, count: 1,
                              entries: [{ key: "RFC 7231",
                                          digest: "sha256:abc" }] })
      }
    }
    src = rest(routes)
    expect(src.keys).to eq(["RFC 7231"])
    expect(src.manifest.entry_for("RFC 7231").digest).to eq("sha256:abc")
  end

  it "maps a 404 to NotFoundError, other statuses to BackendError" do
    expect { rest({}).read("RFC 7231") }.to raise_error(Lutaml::Store::NotFoundError)

    boom = { "collections/ietf/entries/RFC+7231" =>
      { status_code: 503, headers: {}, body: "" } }
    expect { rest(boom).read("RFC 7231") }.to raise_error(Lutaml::Store::BackendError)
  end

  it "lists collections" do
    routes = {
      "collections" => {
        status_code: 200, headers: {},
        body: JSON.generate({ collections: [{ name: "ietf", count: 2 }] })
      }
    }
    expect(rest(routes).collections).to eq([{ "name" => "ietf", "count" => 2 }])
  end
end
