# frozen_string_literal: true

# Minimal model with yamls DSL for testing Format::Yamls.
# Structure mirrors ConceptDocument: header + collection of parts.
class YamlsTestHeader < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :name, :string

  yaml do
    map "id", to: :id
    map "name", to: :name
  end
end

class YamlsTestPart < Lutaml::Model::Serializable
  attribute :label, :string
  attribute :value, :string

  yaml do
    map "label", to: :label
    map "value", to: :value
  end
end

class YamlsTestModel < Lutaml::Model::Serializable
  attribute :header, YamlsTestHeader
  attribute :parts, YamlsTestPart, collection: true

  yamls do
    sequence do
      map_document 0, to: :header, type: YamlsTestHeader
      map_document 1.., to: :parts, type: YamlsTestPart, collection: true
    end
  end
end
