# frozen_string_literal: true

module Lutaml
  module Store
    class CacheInspector
      # ANSI color codes
      COLORS = {
        red: "\e[31m",
        green: "\e[32m",
        yellow: "\e[33m",
        blue: "\e[34m",
        magenta: "\e[35m",
        cyan: "\e[36m",
        white: "\e[37m",
        bright_red: "\e[91m",
        bright_green: "\e[92m",
        bright_yellow: "\e[93m",
        bright_blue: "\e[94m",
        bright_magenta: "\e[95m",
        bright_cyan: "\e[96m",
        bright_white: "\e[97m",
        reset: "\e[0m",
        bold: "\e[1m",
        dim: "\e[2m"
      }.freeze

      # Emojis for different cache states
      EMOJIS = {
        cache_hit: "🎯",
        cache_miss: "❌",
        cache_store: "💾",
        fresh: "✨",
        stale: "⏰",
        expired: "💀",
        http_ok: "✅",
        http_error: "🚨",
        performance: "⚡",
        storage: "📦",
        stats: "📊",
        config: "⚙️",
        entry: "📄",
        headers: "🏷️",
        time: "🕐",
        size: "📏",
        url: "🌐",
        method: "🔧",
        status: "📡",
        etag: "🏷️",
        expires: "⏳",
        vary: "🔀",
        conditional: "🤔",
        success: "🎉",
        warning: "⚠️",
        error: "💥",
        info: "ℹ️"
      }.freeze

      def self.colorize(text, color)
        return text unless COLORS[color]

        "#{COLORS[color]}#{text}#{COLORS[:reset]}"
      end

      def self.emoji(type)
        EMOJIS[type] || "📋"
      end

      def self.format_size(bytes)
        return "0 B" if bytes.nil? || bytes == 0

        units = %w[B KB MB GB TB]
        size = bytes.to_f
        unit_index = 0

        while size >= 1024 && unit_index < units.length - 1
          size /= 1024
          unit_index += 1
        end

        "#{size.round(2)} #{units[unit_index]}"
      end

      def self.format_time_ago(time)
        return "Unknown" unless time

        diff = Time.now - time
        case diff
        when 0..59
          "#{diff.round}s ago"
        when 60..3599
          "#{(diff / 60).round}m ago"
        when 3600..86_399
          "#{(diff / 3600).round}h ago"
        else
          "#{(diff / 86_400).round}d ago"
        end
      end

      def self.format_duration(seconds)
        return "0ms" if seconds.nil? || seconds == 0

        if seconds < 1
          "#{(seconds * 1000).round(2)}ms"
        elsif seconds < 60
          "#{seconds.round(2)}s"
        else
          "#{(seconds / 60).round(1)}m"
        end
      end

      def self.print_cache_hit(url, time_saved_ms)
        puts colorize("#{emoji(:cache_hit)} CACHE HIT", :bright_green) +
             " #{colorize(url, :cyan)} " +
             colorize("(saved #{time_saved_ms.round(2)}ms)", :dim)
      end

      def self.print_cache_miss(url, time_ms)
        puts colorize("#{emoji(:cache_miss)} CACHE MISS", :bright_red) +
             " #{colorize(url, :cyan)} " +
             colorize("(#{time_ms.round(2)}ms)", :dim)
      end

      def self.print_cache_store(url, size_bytes)
        puts colorize("#{emoji(:cache_store)} STORED", :bright_blue) +
             " #{colorize(url, :cyan)} " +
             colorize("(#{format_size(size_bytes)})", :dim)
      end

      def self.print_stats(stats)
        puts
        puts colorize("#{emoji(:stats)} Cache Statistics", :bold)
        puts "=" * 50

        # Basic stats
        puts "#{emoji(:storage)} Adapter: #{colorize(stats[:adapter_type], :cyan)}"
        puts "#{emoji(:entry)} Total entries: #{colorize(stats[:total_entries], :yellow)}"
        puts "#{emoji(:cache_hit)} Cache hits: #{colorize(stats[:cache_hits], :green)}"
        puts "#{emoji(:cache_miss)} Cache misses: #{colorize(stats[:cache_misses], :red)}"
        puts "#{emoji(:conditional)} Conditional requests: #{colorize(stats[:conditional_requests], :blue)}"
        puts "#{emoji(:cache_store)} Entries stored: #{colorize(stats[:entries_stored], :magenta)}"

        # Hit ratio with color coding
        hit_ratio = stats[:hit_ratio] || 0
        ratio_color = case hit_ratio
                      when 0..30 then :red
                      when 31..70 then :yellow
                      else :green
                      end
        puts "#{emoji(:performance)} Hit ratio: #{colorize("#{hit_ratio.round(1)}%", ratio_color)}"

        # Total requests
        puts "#{emoji(:stats)} Total requests: #{colorize(stats[:total_requests], :white)}"
      end

      def self.print_entries(entries)
        return puts colorize("#{emoji(:warning)} No cache entries found", :yellow) if entries.empty?

        puts
        puts colorize("#{emoji(:entry)} Cache Entries (#{entries.size} total)", :bold)
        puts "=" * 80

        entries.each_with_index do |entry, index|
          print_entry(entry, index + 1)
          puts
        end
      end

      def self.print_entry(entry, index)
        # Entry header
        status_emoji = entry.status_code == 200 ? emoji(:http_ok) : emoji(:http_error)
        freshness_emoji = if entry.fresh?
                            emoji(:fresh)
                          else
                            (entry.stale? ? emoji(:stale) : emoji(:expired))
                          end

        puts colorize("#{emoji(:entry)} Entry #{index}: #{status_emoji} #{freshness_emoji}", :bold)

        # URL and method
        puts "  #{emoji(:url)} URL: #{colorize(entry.url, :cyan)}"
        puts "  #{emoji(:method)} Method: #{colorize(entry.method, :blue)}"
        puts "  #{emoji(:status)} Status: #{colorize(entry.status_code, :yellow)}"

        # Timing information
        puts "  #{emoji(:time)} Cached: #{colorize(format_time_ago(entry.cached_at), :dim)}"
        if entry.expires_at
          expires_in = entry.expires_at - Time.now
          expires_color = expires_in > 0 ? :green : :red
          puts "  #{emoji(:expires)} Expires: #{colorize(format_duration(expires_in), expires_color)}"
        end

        # Size information
        body_size = entry.response_body&.length || 0
        puts "  #{emoji(:size)} Size: #{colorize(format_size(body_size), :magenta)}"

        # HTTP headers
        puts "  #{emoji(:etag)} ETag: #{colorize(entry.etag, :dim)}" if entry.etag

        puts "  #{emoji(:time)} Last-Modified: #{colorize(entry.last_modified, :dim)}" if entry.last_modified

        # Cache control
        if entry.cache_control && !entry.cache_control.empty?
          cc_parts = entry.cache_control.map { |k, v| v.is_a?(TrueClass) ? k : "#{k}=#{v}" }
          puts "  #{emoji(:config)} Cache-Control: #{colorize(cc_parts.join(", "), :dim)}"
        end

        # Vary headers
        if entry.vary_headers && !entry.vary_headers.empty?
          puts "  #{emoji(:vary)} Vary: #{colorize(entry.vary_headers.join(", "), :dim)}"
        end

        # Response preview
        return unless entry.response_body && !entry.response_body.empty?

        preview = entry.response_body[0..100]
        preview += "..." if entry.response_body.length > 100
        puts "  #{emoji(:info)} Preview: #{colorize(preview.inspect, :dim)}"
      end

      def self.print_performance_comparison(first_time, second_time, label = "Performance")
        return unless first_time && second_time && first_time > 0

        improvement = ((first_time - second_time) / first_time * 100)
        speedup = first_time / second_time

        color = case improvement
                when 0..20 then :yellow
                when 21..50 then :green
                else :bright_green
                end

        puts "#{emoji(:performance)} #{label}: #{colorize("#{improvement.round(1)}% faster", color)} " +
             colorize("(#{speedup.round(1)}x speedup)", :dim)
      end

      def self.print_section_header(title, emoji_type = :info)
        puts
        puts colorize("#{emoji(emoji_type)} #{title}", :bold)
        puts colorize("=" * (title.length + 4), :dim)
      end

      def self.print_success(message)
        puts colorize("#{emoji(:success)} #{message}", :bright_green)
      end

      def self.print_warning(message)
        puts colorize("#{emoji(:warning)} #{message}", :bright_yellow)
      end

      def self.print_error(message)
        puts colorize("#{emoji(:error)} #{message}", :bright_red)
      end

      def self.print_info(message)
        puts colorize("#{emoji(:info)} #{message}", :cyan)
      end
    end
  end
end
