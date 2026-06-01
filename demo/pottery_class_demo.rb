# frozen_string_literal: true

require "lutaml/model"
require_relative "lib/lutaml/store"

class Studio < Lutaml::Model::Serializable
  attribute :studio_key, :string
  attribute :name, :string
  attribute :location, :string
  attribute :_class, :string, default: -> { "Studio" }, polymorphic_class: true
end

# CeramicStudio is a specialization of Studio
class CeramicStudio < Studio
  attribute :clay_type, :string
  # Override the _class attribute to indicate this is a CeramicStudio
  attribute :_class, :string, default: -> { "CeramicStudio" }
end

class PotteryClass < Lutaml::Model::Serializable
  # the :studio attribute should accept Studio and CeramicStudio
  attribute :studio, Studio, polymorphic: true
  attribute :class_id, :string
  attribute :description, :string
end

puts "=== Creating pottery classes ==="
p = [
  PotteryClass.new(
    class_id: "pottery_class",
    studio: Studio.new(studio_key: "pottery_studio", name: "Pottery studio"),
    description: "A class for pottery making"
  ),
  PotteryClass.new(
    class_id: "clay_class",
    studio: Studio.new(studio_key: "clay_place", name: "Clay place"),
    description: "A class for clay modeling"
  ),
  PotteryClass.new(
    class_id: "artisan_class",
    studio: Studio.new(studio_key: "artisan_studio", name: "Artisan studio"),
    description: "A class for artisan pottery"
  )
]

puts "=== Creating store ==="
# Create a simple in-memory store
store = Lutaml::Store.new(
  # This creates an in-memory store
  adapter: :memory,
  # This registers the models that will be stored in the store with their unique
  # keys.
  # The key is used to identify the model in the store and is used to fetch,
  # update, or delete the model.
  # If an inner model is not registered, it will only be persisted as a part of
  # the parent model, but not as a separate entity.
  # If an inner model that is registered gets updated independently via its
  # unique key, the parent model will not be updated in terms of reference to
  # the inner model but the realization of the parent model will reflect the
  # changes because it is a composite model.
  models: [
    {
      model: PotteryClass,
      key: :class_id
    },
    {
      model: Studio,
      key: :studio_key,
      polymorphic_class_key: :_class
    },
    {
      model: CeramicStudio,
      key: :studio_key,
      polymorphic_class_key: :_class
    }
  ]
)

puts "=== Saving pottery classes ==="
store.save(p)

puts "=== Fetching pottery class ==="
p1 = store.fetch(model: PotteryClass, class_id: "pottery_class")
puts "p1.studio: #{p1.studio.inspect}"
# => #<Studio:0x00007f8c8b0a4b80 @name="Pottery studio", @location=nil>
puts "p1.studio.name: #{p1.studio.name}"

puts "=== Updating pottery class description ==="
# Updating the pottery class to a different description
store.update(
  model: PotteryClass,
  class_id: "clay_class",
  attributes: {
    description: "A class for advanced clay modeling"
  }
)

puts "=== Fetching updated pottery class ==="
# Fetching the updated pottery class
p2 = store.fetch(model: PotteryClass, class_id: "clay_class")
puts "p2.description: #{p2.description}"
# => "A class for advanced clay modeling"

puts "=== Updating studio location with dot notation ==="
# Updating the studio to a different location
store.update(
  model: PotteryClass,
  class_id: "clay_class",
  attributes: {
    "studio.location" => "Far enough downtown"
  }
)

puts "=== Fetching pottery class with updated studio ==="
# Fetching the updated pottery class
p2 = store.fetch(model: PotteryClass, class_id: "clay_class")
puts "p2.studio.location: #{p2.studio.location}"
# => "Far enough downtown"

puts "=== Creating and saving CeramicStudio ==="
# Replacing the Studio with a CeramicStudio
ceramic_studio = CeramicStudio.new(
  studio_key: "artisan_studio",
  name: "Angelic pottery studio",
  clay_type: "Porcelain"
)
store.save(ceramic_studio)

puts "=== Fetching artisan class (should have CeramicStudio) ==="
# Fetching the updated artisan class
p3 = store.fetch(model: PotteryClass, class_id: "artisan_class")
puts "p3.studio.name: #{p3.studio.name}"
# => "Angelic pottery studio"
puts "p3.studio.class: #{p3.studio.class}"
# => "CeramicStudio"
puts "p3.studio.clay_type: #{p3.studio.clay_type}"
# => "Porcelain"

puts "=== Updating pottery class with new CeramicStudio ==="
# Updating the studio to a CeramicStudio instance
store.update(
  model: PotteryClass,
  class_id: "pottery_class",
  attributes: {
    studio: CeramicStudio.new(
      studio_key: "pottery_studio",
      name: "Ceramic studio",
      clay_type: "Stoneware"
    )
  }
)

puts "=== Fetching final pottery class ==="
# Fetching the updated pottery class
p1 = store.fetch(model: PotteryClass, class_id: "pottery_class")
puts "p1.studio: #{p1.studio.inspect}"
# => #<CeramicStudio:0x00007f8c8b0a4b80 @name="Ceramic studio", @clay_type="Stoneware">

puts "p1.studio.class: #{p1.studio.class}"
# => "CeramicStudio"
puts "p1.studio.clay_type: #{p1.studio.clay_type}"
# => "Stoneware"

puts "=== All tests completed successfully! ==="
