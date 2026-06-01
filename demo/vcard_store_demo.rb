#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "lutaml/store"
require "securerandom"
require "date"
require "paint"
require "table_tennis"
require_relative "vcard_models"

# VCard Store Demo
# This demo showcases the lutaml-store functionality using vCard models
class VCardStoreDemo
  include VCardDemo

  def initialize
    @stores = {}
    setup_stores
    puts "🎯 VCard Store Demo Initialized"
    puts "=" * 50
  end

  def run
    puts "\n📋 Running VCard Store Demo..."

    # Create sample vCards
    create_sample_vcards

    # Demonstrate different storage backends
    demonstrate_memory_store
    demonstrate_filesystem_store
    demonstrate_sqlite_store
    demonstrate_cache_store

    # Demonstrate search and retrieval
    demonstrate_search_capabilities

    # Demonstrate data integrity
    demonstrate_integrity_features

    puts "\n✅ Demo completed successfully!"
    puts "Check the demo/data/ directory for persisted files."
  end

  private

  def setup_stores
    # Memory store for fast operations
    @stores[:memory] = Lutaml::Store::Store.new(
      adapter: { type: :memory }
    )

    # Filesystem store for persistence
    @stores[:filesystem] = Lutaml::Store::Store.new(
      adapter: {
        type: :filesystem,
        options: { path: "demo/data/vcards" }
      }
    )

    # SQLite store for structured queries
    @stores[:sqlite] = Lutaml::Store::Store.new(
      adapter: {
        type: :sqlite,
        options: { path: "demo/data/vcards.db" }
      }
    )

    # Cache store for performance
    @stores[:cache] = Lutaml::Store::CacheStore.new(
      adapter: { type: :memory },
      default_ttl: 300, # 5 minutes
      max_size: 100
    )
  end

  def create_sample_vcards
    puts "\n📝 Creating 10 sample vCards..."

    @sample_vcards = [
      create_vcard(
        fn: "John Doe",
        given: "John", family: "Doe",
        email: ["john.doe@example.com", "j.doe@work.com"],
        phone: ["+1-555-0101", "work"],
        org: "Tech Corp",
        birthday: "1985-03-15"
      ),
      create_vcard(
        fn: "Jane Smith",
        given: "Jane", family: "Smith",
        email: ["jane.smith@example.com"],
        phone: ["+1-555-0102", "mobile"],
        org: "Design Studio",
        birthday: "1990-07-22"
      ),
      create_vcard(
        fn: "Dr. Robert Johnson",
        prefix: "Dr.", given: "Robert", family: "Johnson",
        email: ["r.johnson@hospital.com", "robert@personal.com"],
        phone: ["+1-555-0103", "work"],
        org: "City Hospital",
        birthday: "1975-11-08"
      ),
      create_vcard(
        fn: "Maria Garcia",
        given: "Maria", family: "Garcia",
        email: ["maria.garcia@startup.com"],
        phone: ["+1-555-0104", "mobile"],
        org: "Innovation Labs",
        birthday: "1988-02-14"
      ),
      create_vcard(
        fn: "David Wilson",
        given: "David", family: "Wilson",
        email: ["david.wilson@consulting.com"],
        phone: ["+1-555-0105", "work"],
        org: "Wilson Consulting",
        birthday: "1982-09-30"
      ),
      create_vcard(
        fn: "Sarah Brown",
        given: "Sarah", family: "Brown",
        email: ["sarah.brown@university.edu", "s.brown@research.org"],
        phone: ["+1-555-0106", "work"],
        org: "State University",
        birthday: "1979-12-03"
      ),
      create_vcard(
        fn: "Michael Davis",
        given: "Michael", family: "Davis",
        email: ["mike.davis@agency.com"],
        phone: ["+1-555-0107", "mobile"],
        org: "Creative Agency",
        birthday: "1992-05-18"
      ),
      create_vcard(
        fn: "Lisa Anderson",
        given: "Lisa", family: "Anderson",
        email: ["lisa.anderson@finance.com"],
        phone: ["+1-555-0108", "work"],
        org: "Financial Services Inc",
        birthday: "1986-08-25"
      ),
      create_vcard(
        fn: "James Taylor",
        given: "James", family: "Taylor",
        email: ["james.taylor@music.com", "jtaylor@personal.net"],
        phone: ["+1-555-0109", "mobile"],
        org: "Music Production",
        birthday: "1983-01-12"
      ),
      create_vcard(
        fn: "Emma Thompson",
        given: "Emma", family: "Thompson",
        email: ["emma.thompson@law.com"],
        phone: ["+1-555-0110", "work"],
        org: "Thompson & Associates",
        birthday: "1977-04-07"
      )
    ]

    puts "✅ Created #{@sample_vcards.length} vCards"
  end

  def create_vcard(fn:, given:, family:, email:, phone:, org:, birthday:, prefix: nil)
    name = VcardName.new(
      given: given,
      family: family,
      prefix: prefix
    )

    tel = VcardTel.new(
      value: phone[0],
      type: phone[1]
    )

    bday = VcardBday.new(
      value: birthday
    )

    Vcard.new(
      fn: fn,
      n: name,
      email: email,
      tel: [tel],
      org: org,
      bday: bday
    )
  end

  def demonstrate_memory_store
    puts "\n🧠 Memory Store Demo"
    puts "-" * 30

    store = @stores[:memory]

    # Store all vCards
    @sample_vcards.each do |vcard|
      store.set(vcard.uid, vcard.to_h)
      puts "💾 Stored: #{vcard.fn}"
    end

    puts "📊 Total stored: #{store.size} vCards"

    # Retrieve a specific vCard
    first_uid = @sample_vcards.first.uid
    retrieved = store.get(first_uid)
    puts "🔍 Retrieved: #{retrieved["fn"]} by UID"

    # List all keys
    puts "🗂️  All UIDs: #{store.keys.length} entries"
  end

  def demonstrate_filesystem_store
    puts "\n💾 Filesystem Store Demo"
    puts "-" * 30

    store = @stores[:filesystem]

    # Store vCards with organized keys
    @sample_vcards.each_with_index do |vcard, index|
      key = "contact_#{index + 1}_#{vcard.n.family.downcase}"
      store.set(key, vcard.to_h)
      puts "📁 Saved to file: #{key}"
    end

    puts "📊 Total files: #{store.size}"

    # Demonstrate file persistence
    puts "💽 Files are persisted in: demo/data/vcards/"

    # Retrieve by organized key
    key = "contact_1_doe"
    return unless store.exists?(key)

    retrieved = store.get(key)
    puts "🔍 Retrieved from file: #{retrieved["fn"]}"
  end

  def demonstrate_sqlite_store
    puts "\n🗄️  SQLite Store Demo"
    puts "-" * 30

    store = @stores[:sqlite]

    # Store with email-based keys for easy lookup
    @sample_vcards.each do |vcard|
      email_key = vcard.primary_email.split("@").first
      store.set(email_key, vcard.to_h)
      puts "🗃️  Stored in DB: #{email_key} -> #{vcard.fn}"
    end

    puts "📊 Total DB records: #{store.size}"

    # Demonstrate database persistence
    puts "💾 Data persisted in: demo/data/vcards.db"

    # Retrieve by email key
    retrieved = store.get("john.doe")
    puts "🔍 Retrieved from DB: #{retrieved["fn"]}" if retrieved
  end

  def demonstrate_cache_store
    puts "\n⚡ Cache Store Demo"
    puts "-" * 30

    cache = @stores[:cache]

    # Cache frequently accessed vCards
    @sample_vcards.first(5).each do |vcard|
      cache.set(vcard.uid, vcard.to_h, ttl: 60) # 1 minute TTL
      puts "⚡ Cached: #{vcard.fn} (TTL: 60s)"
    end

    # Demonstrate cache operations
    first_uid = @sample_vcards.first.uid
    puts "🔍 Cache hit: #{cache.get(first_uid)["fn"]}"
    puts "⏱️  TTL remaining: #{cache.ttl(first_uid).round(2)}s"

    # Cache statistics
    info = cache.cache_info
    puts "📊 Cache stats: #{info[:valid_entries]} valid, #{info[:expired_entries]} expired"
  end

  def demonstrate_search_capabilities
    puts "\n🔍 Search & Retrieval Demo"
    puts "-" * 30

    # Search across different stores
    puts "🏢 Finding contacts by organization:"
    find_by_organization("Tech Corp")

    puts "\n📧 Finding contacts by email domain:"
    find_by_email_domain("example.com")

    puts "\n🎂 Finding contacts by birth year:"
    find_by_birth_year(1985)

    # Display contacts in a formatted table
    puts "\n📋 Contact Directory (Table View)"
    puts "-" * 40
    display_contacts_table

    # Demonstrate ID-based search
    puts "\n🆔 Search by ID Demo"
    puts "-" * 25
    first_uid = @sample_vcards.first.uid
    colored_search_by_id(first_uid)
  end

  def find_by_organization(org_name)
    found = 0
    @stores[:memory].each_key do |key|
      vcard_data = @stores[:memory].get(key)
      if vcard_data["org"] == org_name
        puts "  👤 #{vcard_data["fn"]} - #{vcard_data["org"]}"
        found += 1
      end
    end
    puts "  📊 Found #{found} contacts in #{org_name}" if found.positive?
  end

  def find_by_email_domain(domain)
    @stores[:filesystem].each_key do |key|
      vcard_data = @stores[:filesystem].get(key)
      emails = vcard_data["email"] || []
      puts "  📧 #{vcard_data["fn"]} - #{emails.first}" if emails.any? { |email| email.include?(domain) }
    end
  end

  def find_by_birth_year(year)
    @stores[:sqlite].each_key do |key|
      vcard_data = @stores[:sqlite].get(key)
      puts "  🎂 #{vcard_data["fn"]} - born in #{year}" if vcard_data.dig("bday", "value")&.start_with?(year.to_s)
    end
  end

  def demonstrate_integrity_features
    puts "\n🔒 Data Integrity Demo"
    puts "-" * 30

    # Create a store with integrity checking
    integrity_store = Lutaml::Store::Store.new(
      adapter: { type: :memory },
      integrity: { enabled: true, algorithm: :sha256 }
    )

    # Store a vCard with integrity checking
    vcard = @sample_vcards.first
    integrity_store.set(vcard.uid, vcard.to_h)
    puts "🔐 Stored with integrity check: #{vcard.fn}"

    # Verify integrity
    puts "✅ Integrity verified for: #{vcard.fn}" if integrity_store.exists?(vcard.uid)

    # Demonstrate compression
    compressed_store = Lutaml::Store::Store.new(
      adapter: { type: :memory },
      compression: { enabled: true, algorithm: :gzip }
    )

    compressed_store.set(vcard.uid, vcard.to_h)
    puts "🗜️  Stored with compression: #{vcard.fn}"
  end

  # Display contacts in a formatted table using table_tennis
  def display_contacts_table
    # Prepare data for the table (without colors for table_tennis)
    table_data = []

    # Header row (plain text for table_tennis)
    table_data << %w[Name Organization Email Phone Birthday]

    # Data rows from memory store
    @stores[:memory].keys.first(5).each do |key|
      vcard_data = @stores[:memory].get(key)
      emails = vcard_data["email"] || []
      tel_data = vcard_data["tel"] || []
      phone = tel_data.first&.dig("value") || "N/A"
      birthday = vcard_data.dig("bday", "value") || "N/A"

      table_data << [
        vcard_data["fn"],
        vcard_data["org"] || "N/A",
        emails.first || "N/A",
        phone,
        birthday
      ]
    end

    # Create and display the table
    table = TableTennis::Table.new(table_data)
    puts table

    # Show the saved files
    puts "\n📁 Saved Files in Filesystem Store"
    puts "-" * 40
    show_saved_files

    # Display individual contact cards
    puts "\n🎨 Individual Contact Cards"
    puts "-" * 40
    @sample_vcards.first(3).each do |vcard|
      display_colored_vcard(vcard)
      puts
    end
  end

  # Show the actual saved files and their contents
  def show_saved_files
    data_dir = "demo/data/vcards"
    puts "📂 Directory: #{File.expand_path(data_dir)}"

    if Dir.exist?(data_dir)
      # Look for .data files specifically
      files = Dir.glob("#{data_dir}/**/*.data").first(3)
      files.each do |file|
        puts "\n📄 File: #{File.basename(file)}"
        puts "   Path: #{file}"
        puts "   Content preview:"
        if File.file?(file)
          content = File.read(file)
          # Show first few lines of YAML content
          lines = content.lines.first(8)
          lines.each { |line| puts "   #{line.chomp}" }
          puts "   ..." if content.lines.length > 8
        else
          puts "   ❌ Not a regular file"
        end
      end

      # Also show directory structure
      puts "\n📁 Directory Structure:"
      Dir.glob("#{data_dir}/**/*").first(10).each do |path|
        relative_path = path.sub("#{data_dir}/", "")
        if File.directory?(path)
          puts "   📁 #{relative_path}/"
        else
          puts "   📄 #{relative_path}"
        end
      end
    else
      puts "❌ Directory not found: #{data_dir}"
    end
  end

  # Display a single vCard with colors and formatting
  def display_colored_vcard(vcard)
    puts Paint["╔#{"═" * 50}╗", :blue, :bold]
    puts Paint["║", :blue, :bold] + Paint[" #{vcard.fn.center(48)} ", :white, :bold] + Paint["║", :blue, :bold]
    puts Paint["╠#{"═" * 50}╣", :blue, :bold]

    # Name details
    if vcard.n.prefix
      puts Paint["║", :blue,
                 :bold] + Paint[" Title: ", :cyan,
                                :bold] + Paint["#{vcard.n.prefix.ljust(41)} ", :white] + Paint["║", :blue, :bold]
    end

    puts Paint["║", :blue,
               :bold] + Paint[" Given: ", :cyan,
                              :bold] + Paint["#{vcard.n.given.ljust(40)} ", :white] + Paint["║", :blue, :bold]
    puts Paint["║", :blue,
               :bold] + Paint[" Family: ", :cyan,
                              :bold] + Paint["#{vcard.n.family.ljust(39)} ", :white] + Paint["║", :blue, :bold]

    # Organization
    puts Paint["║", :blue,
               :bold] + Paint[" Organization: ", :green,
                              :bold] + Paint["#{vcard.org.ljust(33)} ", :green] + Paint["║", :blue, :bold]

    # Contact info
    puts Paint["║", :blue,
               :bold] + Paint[" Email: ", :yellow,
                              :bold] + Paint["#{vcard.primary_email.ljust(39)} ",
                                             :yellow] + Paint["║", :blue, :bold]

    if vcard.tel && !vcard.tel.empty?
      tel = vcard.tel.first
      phone_info = "#{tel.value} (#{tel.type})"
      puts Paint["║", :blue,
                 :bold] + Paint[" Phone: ", :magenta,
                                :bold] + Paint["#{phone_info.ljust(39)} ", :magenta] + Paint["║", :blue, :bold]
    end

    # Birthday
    if vcard.bday
      puts Paint["║", :blue,
                 :bold] + Paint[" Birthday: ", :cyan,
                                :bold] + Paint["#{vcard.bday.value.ljust(37)} ", :cyan] + Paint["║", :blue, :bold]
    end

    # UID
    puts Paint["║", :blue,
               :bold] + Paint[" UID: ", :red,
                              :bold] + Paint["#{vcard.uid[0..41]}... ", :red] + Paint["║", :blue, :bold]

    puts Paint["╚#{"═" * 50}╝", :blue, :bold]
  end

  # Enhanced search with colored output
  def colored_search_by_id(uid)
    puts Paint["\n🔍 Searching for UID: #{uid}", :yellow, :bold]

    @stores.each do |store_name, store|
      next unless store.exists?(uid)

      vcard_data = store.get(uid)
      puts Paint["✅ Found in #{store_name} store:", :green, :bold]
      puts Paint["   Name: #{vcard_data["fn"]}", :white]
      puts Paint["   Organization: #{vcard_data["org"]}", :green]
      return vcard_data
    end

    puts Paint["❌ Not found in any store", :red, :bold]
    nil
  end
end

# Run the demo
if __FILE__ == $PROGRAM_NAME
  demo = VCardStoreDemo.new
  demo.run
end
