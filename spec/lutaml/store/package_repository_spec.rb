# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

# The canonical fixtures of the relaton-cloud-store work hub. They may live
# beside the workspace (TODO.relaton-cloud-store/fixtures) or be pointed at
# explicitly; the suite is explicit about where they come from either way.
FIXTURE_ROOT = ENV["RELATON_CLOUD_FIXTURES"] ||
               File.expand_path("../../../../TODO.relaton-cloud-store/fixtures", __dir__)

RSpec.describe Lutaml::Store::Manifest do
  it "parses the conformance fixture" do
    skip "conformance fixtures not found at #{FIXTURE_ROOT}" unless File.directory?(FIXTURE_ROOT)

    manifest = described_class.parse(File.read(File.join(FIXTURE_ROOT, "manifest.json")))
    expect(manifest.version).to eq(1)
    expect(manifest.count).to eq(manifest.entries.size)
    expect(manifest.keys).to contain_exactly("RFC 7231", "draft-ietf-quic-transport",
                                             "ISO 19115-1:2014")
    expect(manifest.entry_for("RFC 7231").digest).to start_with("sha256:")
  end

  it "round-trips through YAML" do
    manifest = described_class.build(
      [described_class::Entry.new(key: "k", digest: "sha256:beef")],
      generated: Time.at(0).utc
    )
    expect(described_class.parse(manifest.to_yaml, format: :yaml).keys).to eq(["k"])
  end
end

RSpec.describe Lutaml::Store::Mirror do
  let(:fixtures) { FIXTURE_ROOT }
  let(:origin) { Lutaml::Store::Source.for(:directory, path: fixtures) }
  let(:into) { Dir.mktmpdir }

  it "pulls a source into the canonical package layout" do
    skip "conformance fixtures not found at #{fixtures}" unless File.directory?(fixtures)

    local = described_class.pull(origin, into: into, collection: "ietf")

    expect(File).to exist(File.join(into, "ietf", "manifest.json"))
    expect(local.keys).to eq(origin.keys)
    expect(local.read("RFC 7231")).to eq(origin.read("RFC 7231"))
  end

  it "is incremental: a second pull rewrites nothing when digests match" do
    skip "conformance fixtures not found at #{fixtures}" unless File.directory?(fixtures)

    first = described_class.pull(origin, into: into)
    entry_path = File.join(into, first.entry_for("RFC 7231").location)
    mtime = File.mtime(entry_path)
    described_class.pull(origin, into: into)
    expect(File.mtime(entry_path)).to eq(mtime)
  end

  it "rejects a source whose bytes break the declared digest" do
    manifest_body = JSON.generate(version: 1, count: 1,
                                  entries: [{ key: "k", digest: "sha256:dead" }])
    routes = {
      "collections/c/manifest" => { status_code: 200, headers: {}, body: manifest_body },
      "collections/c/entries/k" => { status_code: 200, headers: {}, body: "tampered" }
    }
    bad_origin = Lutaml::Store::Source.for(
      :rest, base_url: "https://x.test", collection: "c",
      transport: lambda do |uri, _h|
        routes.fetch(uri.path.sub(%r{\A/}, "")) { { status_code: 404, headers: {}, body: "" } }
      end
    )
    expect { described_class.pull(bad_origin, into: into) }
      .to raise_error(described_class::IntegrityError, /digest mismatch/)
  end
end

RSpec.describe Lutaml::Store::Format do
  it "guesses the format of self-describing content" do
    expect(described_class.guess("<?xml version='1.0'?><bibdata/>")).to eq(:xml)
    expect(described_class.guess("  {\"id\": 1}")).to eq(:json)
    expect(described_class.guess("---\nid: RFC7231\n")).to eq(:yaml)
  end
end

RSpec.describe Lutaml::Store::Mirror do
  it "packs a pulled package into a zip that Source::Zip reads in place" do
    skip "conformance fixtures not found at #{FIXTURE_ROOT}" unless File.directory?(FIXTURE_ROOT)

    into = Dir.mktmpdir
    local = described_class.pull(
      Lutaml::Store::Source.for(:directory, path: FIXTURE_ROOT), into: into, collection: "ietf"
    )
    zip_path = File.join(into, "ietf.zip")
    described_class.pack(local.package_root, to: zip_path)

    zipped = Lutaml::Store::Source.for(:zip, path: zip_path)
    expect(zipped.keys).to eq(local.keys)
    expect(zipped.read("RFC 7231")).to include("RFC7231")
  end
end

RSpec.describe Lutaml::Store::Repository do
  let(:fixtures) { FIXTURE_ROOT }

  it "serves a local package and a cloud source through one read API" do
    skip "conformance fixtures not found at #{fixtures}" unless File.directory?(fixtures)

    local = described_class.for_package(fixtures)
    expect(local.read("RFC 7231")).to include("RFC7231")
    expect(local.exist?("RFC 7231")).to be(true)
    expect(local.exist?("RFC 9999")).to be(false)
  end

  it "caches a cloud source into an explicit local package (read-through)" do
    skip "conformance fixtures not found at #{fixtures}" unless File.directory?(fixtures)

    origin = Lutaml::Store::Source.for(:directory, path: fixtures)
    cache_dir = File.join(Dir.mktmpdir, "cache")
    cache = Lutaml::Store::Source.for(:directory, path: cache_dir)
    repo = described_class.new(source: origin, cache: cache)

    expect(repo.read("RFC 7231")).to include("RFC7231")
    # the cache now holds the entry — subsequent reads are served from it
    expect(cache.read("RFC 7231")).to include("RFC7231")

    offline = described_class.new(source: origin, cache: cache, mode: :offline)
    expect(offline.read("RFC 7231")).to include("RFC7231")
  end

  it "refuses offline mode without a cache — explicitly, never by guessing" do
    expect { described_class.new(source: Lutaml::Store::Source.for(:directory, path: fixtures),
                                 mode: :offline) }
      .to raise_error(Lutaml::Store::ConfigurationError, /offline mode requires a cache/)
  end

  it "pulls a whole source into a GCR-style package and reopens it" do
    skip "conformance fixtures not found at #{fixtures}" unless File.directory?(fixtures)

    cloud = described_class.new(source: Lutaml::Store::Source.for(:directory, path: fixtures))
    local = cloud.pull!(into: Dir.mktmpdir, collection: "ietf")
    expect(local.keys).to eq(cloud.keys)
  end
end
