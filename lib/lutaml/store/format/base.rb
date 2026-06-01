# frozen_string_literal: true

module Lutaml
  module Store
    module Format
      class Base
        def extension
          raise NotImplementedError
        end

        def glob_pattern
          raise NotImplementedError
        end

        def serialize(model)
          raise NotImplementedError
        end

        def deserialize(data, model_class)
          raise NotImplementedError
        end

        def serialize_many(models)
          models.map { |m| serialize(m) }.join
        end

        def deserialize_many(_data, _model_class)
          raise NotImplementedError, "#{self.class} does not support multi-document deserialization"
        end
      end
    end
  end
end
