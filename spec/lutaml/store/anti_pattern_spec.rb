# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Anti-pattern regression prevention" do
  let(:lib_dir) { File.expand_path("../../lib/lutaml/store", __dir__) }

  def ruby_files
    Dir.glob(File.join(lib_dir, "**", "*.rb"))
  end

  def file_contents
    ruby_files.to_h { |f| [f, File.read(f)] }
  end

  describe "no respond_to? in lib code" do
    it "contains zero respond_to? calls" do
      offenders = file_contents.filter_map do |path, content|
        matches = content.scan(/^.*respond_to\?.*$/)
        next if matches.empty?
        next if matches.all? { |line| line.strip.start_with?("#") }

        rel = path.sub(%r{.*lib/}, "")
        count = matches.count { |line| !line.strip.start_with?("#") }
        "#{rel}: #{count} occurrence(s)"
      end

      expect(offenders).to be_empty,
                           "Found respond_to? in lib code:\n#{offenders.join("\n")}"
    end
  end

  describe "no instance_variable_get/set in lib code" do
    it "contains zero instance_variable_get calls" do
      offenders = file_contents.filter_map do |path, content|
        matches = content.scan(/^.*instance_variable_get.*$/)
        next if matches.empty?
        next if matches.all? { |line| line.strip.start_with?("#") }

        rel = path.sub(%r{.*lib/}, "")
        "#{rel}: #{matches.size} occurrence(s)"
      end

      expect(offenders).to be_empty,
                           "Found instance_variable_get in lib code:\n#{offenders.join("\n")}"
    end

    it "contains zero instance_variable_set calls" do
      offenders = file_contents.filter_map do |path, content|
        matches = content.scan(/^.*instance_variable_set.*$/)
        next if matches.empty?
        next if matches.all? { |line| line.strip.start_with?("#") }

        rel = path.sub(%r{.*lib/}, "")
        "#{rel}: #{matches.size} occurrence(s)"
      end

      expect(offenders).to be_empty,
                           "Found instance_variable_set in lib code:\n#{offenders.join("\n")}"
    end
  end

  describe "no send on private methods in lib code" do
    it "contains zero .send( calls" do
      offenders = file_contents.filter_map do |path, content|
        matches = content.scan(/^.*\.send\(.*$/)
        next if matches.empty?
        next if matches.all? { |line| line.strip.start_with?("#") }

        rel = path.sub(%r{.*lib/}, "")
        "#{rel}: #{matches.size} occurrence(s)"
      end

      expect(offenders).to be_empty,
                           "Found .send( in lib code:\n#{offenders.join("\n")}"
    end
  end
end
