# frozen_string_literal: true

require "spec_helper"

# Enforces code quality rules from CLAUDE.md global instructions.
# These specs MUST pass — any failure means an anti-pattern was introduced.
RSpec.describe "Anti-pattern guard" do
  lib_dir = File.expand_path("../../../lib", __dir__)
  rb_files = Dir.glob(File.join(lib_dir, "**", "*.rb"))

  rb_files.each do |path|
    rel = path.sub("#{lib_dir}/", "")

    it "#{rel} does not use .send() to call private methods" do
      code = File.read(path).lines.reject { |l| l.strip.start_with?("#") }.join
      code = code.gsub(/#.*$/, "")
      uses = code.scan(/\.send\s*\(/)
      expect(uses).to be_empty, "#{rel} uses .send() — refactor to use a public API"
    end

    it "#{rel} does not use instance_variable_get or instance_variable_set" do
      code = File.read(path).lines.reject { |l| l.strip.start_with?("#") }.join
      code = code.gsub(/#.*$/, "")
      uses = code.scan(/instance_variable_(get|set)/)
      expect(uses).to be_empty, "#{rel} uses instance_variable_get/set — add a public accessor"
    end

    it "#{rel} does not use respond_to? for type checking" do
      code = File.read(path).lines.reject { |l| l.strip.start_with?("#") }.join
      code = code.gsub(/#.*$/, "")
      uses = code.scan(/respond_to\?\s*/)
      expect(uses).to be_empty, "#{rel} uses respond_to? — use is_a? or redesign the type hierarchy"
    end
  end
end
