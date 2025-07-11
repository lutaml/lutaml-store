# Lutaml::Store

A flexible, high-performance key-value store library for Ruby with multiple backend support, caching, monitoring, and event system.

## Features

- **Multiple Backends**: Memory, FileSystem, and SQLite storage options
- **Intelligent Caching**: LRU cache with TTL support for improved performance
- **Event System**: Synchronous and asynchronous event handling
- **Monitoring**: Built-in performance and error tracking
- **Thread-Safe**: All operations are thread-safe across all backends
- **Configuration**: YAML-based configuration with validation
- **Extensible**: Easy to add new backends and features

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lutaml-store'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install lutaml-store

For SQLite backend support, also add:

```ruby
gem 'sqlite3'
```

## Quick Start

```ruby
require 'lutaml/store'

# Create a simple in-memory store
store = Lutaml::Store::Store.new

# Store and retrieve data
store.set("user:1", "John Doe")
puts store.get("user:1") # => "John Doe"

# Check existence
puts store.exists?("user:1") # => true

# Delete data
store.delete("user:1")
puts store.get("user:1") # => nil
```

## Backends

### Memory Backend (Default)

Fast in-memory storage, perfect for caching and temporary data:

```ruby
store = Lutaml::Store::Store.new({
  "backend" => {
    "type" => "memory"
  }
})
```

### FileSystem Backend

Persistent file-based storage with directory organization:

```ruby
store = Lutaml::Store::Store.new({
  "backend" => {
    "type" => "filesystem",
    "options" => {
      "path" => "/path/to/storage",
      "extension" => "dat"
    }
  }
})
```

### SQLite Backend

Database storage with ACID compliance:

```ruby
store = Lutaml::Store::Store.new({
  "backend" => {
    "type" => "sqlite",
    "options" => {
      "path" => "/path/to/database.db"
    }
  }
})
```

## Configuration

### YAML Configuration

Create a configuration file:

```yaml
# config/store.yml
lutaml_store:
  backend:
    type: filesystem
    options:
      path: ./data/store
      extension: json
  cache:
    enabled: true
    max_size: 1000
    ttl: 3600  # 1 hour in seconds
  monitoring:
    enabled: true
  events:
    async: false
```

Load from file:

```ruby
store = Lutaml::Store::Store.from_file("config/store.yml")
```

### Programmatic Configuration

```ruby
config = {
  "backend" => {
    "type" => "memory"
  },
  "cache" => {
    "enabled" => true,
    "max_size" => 500,
    "ttl" => 1800
  },
  "monitoring" => {
    "enabled" => true
  },
  "events" => {
    "async" => true
  }
}

store = Lutaml::Store::Store.new(config)
```

## Caching

Enable intelligent caching to improve read performance:

```ruby
store = Lutaml::Store::Store.new({
  "cache" => {
    "enabled" => true,
    "max_size" => 1000,  # Maximum items in cache
    "ttl" => 3600        # Time-to-live in seconds
  }
})

# Cache statistics
puts store.cache_stats
# => { size: 10, max_size: 1000, ttl: 3600, keys: [...] }
```

## Events

Listen to store operations:

```ruby
# Register event listeners
store.on(:set) do |event_data|
  puts "Key #{event_data[:key]} was set to #{event_data[:value]}"
end

store.on(:get) do |event_data|
  source = event_data[:source] # :cache or :backend
  puts "Key #{event_data[:key]} retrieved from #{source}"
end

store.on(:delete) do |event_data|
  puts "Key #{event_data[:key]} was deleted" if event_data[:deleted]
end

# Operations will trigger events
store.set("user:1", "John")
store.get("user:1")
store.delete("user:1")
```

## Monitoring

Track performance and errors:

```ruby
store = Lutaml::Store::Store.new({
  "monitoring" => { "enabled" => true }
})

# Perform operations
store.set("key1", "value1")
store.get("key1")

# Get statistics
stats = store.stats
puts stats
# => {
#   uptime: 120.5,
#   total_operations: 2,
#   operations: { set: 1, get: 1 },
#   errors: {},
#   performance: { set: { avg: 0.001, min: 0.001, max: 0.001 } },
#   error_rate: 0.0
# }
```

## API Reference

### Core Operations

```ruby
# Store a value
store.set(key, value)

# Retrieve a value
value = store.get(key)

# Check if key exists
exists = store.exists?(key)

# Delete a key
deleted = store.delete(key)

# Get all key-value pairs
all_data = store.all

# Clear all data
store.clear

# Get number of items
count = store.size

# Get all keys
keys = store.keys

# Get all values
values = store.values
```

### Event Management

```ruby
# Register listener
store.on(:event_name, callable)
store.on(:event_name) { |data| ... }

# Remove listener
store.off(:event_name, listener)

# Supported events: :get, :set, :delete, :clear
```

### Resource Management

```ruby
# Close store and clean up resources
store.close
```

## Thread Safety

All operations are thread-safe across all backends:

```ruby
store = Lutaml::Store::Store.new

# Safe to use from multiple threads
threads = 10.times.map do |i|
  Thread.new do
    store.set("key#{i}", "value#{i}")
    store.get("key#{i}")
  end
end

threads.each(&:join)
```

## Performance Considerations

1. **Memory Backend**: Fastest for temporary data and caching
2. **FileSystem Backend**: Good balance of performance and persistence
3. **SQLite Backend**: Best for ACID compliance and complex queries
4. **Caching**: Significantly improves read performance for frequently accessed data
5. **Async Events**: Use for high-throughput scenarios to avoid blocking operations

## Error Handling

The library defines specific error types:

```ruby
begin
  store = Lutaml::Store::Store.new({
    "backend" => { "type" => "invalid" }
  })
rescue Lutaml::Store::ConfigurationError => e
  puts "Configuration error: #{e.message}"
rescue Lutaml::Store::BackendError => e
  puts "Backend error: #{e.message}"
end
```

## Development

After checking out the repo, run:

```bash
bin/setup      # Install dependencies
bundle exec rspec  # Run tests
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lutaml/lutaml-store.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
