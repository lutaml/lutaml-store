# frozen_string_literal: true

# Simple model with key_value DSL for testing package components
# without depending on glossarist or lutaml-jsonschema.
class SimpleTestModel < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :name, :string
  attribute :value, :string

  key_value do
    map "id", to: :id
    map "name", to: :name
    map "value", to: :value
  end
end
