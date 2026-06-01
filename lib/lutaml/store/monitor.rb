# frozen_string_literal: true

module Lutaml
  module Store
    class Monitor
      def initialize
        @stats = {
          operations: Hash.new(0),
          errors: Hash.new(0),
          access_times: {},
          total_access_count: 0
        }
        @mutex = Mutex.new
        @start_time = Time.now
      end

      # Record an operation
      # @param operation [Symbol] the operation type (:get, :set, :delete, :clear, etc.)
      # @param duration [Float] operation duration in seconds
      # @param success [Boolean] whether the operation succeeded
      def record_operation(operation, duration: nil, success: true)
        @mutex.synchronize do
          @stats[:operations][operation] += 1
          @stats[:total_access_count] += 1

          @stats[:errors][operation] += 1 unless success

          if duration
            @stats[:access_times][operation] ||= []
            @stats[:access_times][operation] << duration

            # Keep only last 1000 measurements to prevent memory bloat
            @stats[:access_times][operation].shift if @stats[:access_times][operation].size > 1000
          end
        end
      end

      # Record an error
      # @param operation [Symbol] the operation that failed
      # @param error [Exception] the error that occurred
      def record_error(operation, _error)
        @mutex.synchronize do
          @stats[:errors][operation] += 1
          @stats[:errors][:total] += 1
        end
      end

      # Get current statistics
      # @return [Hash] current monitoring statistics
      def stats
        @mutex.synchronize do
          {
            uptime: Time.now - @start_time,
            total_operations: @stats[:total_access_count],
            operations: @stats[:operations].dup,
            errors: @stats[:errors].dup,
            performance: calculate_performance_stats,
            error_rate: calculate_error_rate
          }
        end
      end

      # Get statistics for a specific operation
      # @param operation [Symbol] the operation to get stats for
      # @return [Hash] operation-specific statistics
      def operation_stats(operation)
        @mutex.synchronize do
          {
            count: @stats[:operations][operation],
            errors: @stats[:errors][operation],
            error_rate: calculate_operation_error_rate(operation),
            performance: calculate_operation_performance(operation)
          }
        end
      end

      # Reset all statistics
      def reset
        @mutex.synchronize do
          @stats[:operations].clear
          @stats[:errors].clear
          @stats[:access_times].clear
          @stats[:total_access_count] = 0
          @start_time = Time.now
        end
      end

      # Get a summary report
      # @return [String] formatted statistics report
      def report
        current_stats = stats

        <<~REPORT
          Lutaml::Store Monitor Report
          ============================

          Uptime: #{format_duration(current_stats[:uptime])}
          Total Operations: #{current_stats[:total_operations]}
          Overall Error Rate: #{(current_stats[:error_rate] * 100).round(2)}%

          Operations:
          #{format_operations(current_stats[:operations])}

          Errors:
          #{format_errors(current_stats[:errors])}

          Performance:
          #{format_performance(current_stats[:performance])}
        REPORT
      end

      private

      def calculate_performance_stats
        performance = {}

        @stats[:access_times].each do |operation, times|
          next if times.empty?

          performance[operation] = {
            avg: times.sum / times.size,
            min: times.min,
            max: times.max,
            count: times.size
          }
        end

        performance
      end

      def calculate_error_rate
        total_ops = @stats[:total_access_count]
        total_errors = @stats[:errors].values.sum

        return 0.0 if total_ops.zero?

        total_errors.to_f / total_ops
      end

      def calculate_operation_error_rate(operation)
        total_ops = @stats[:operations][operation]
        errors = @stats[:errors][operation]

        return 0.0 if total_ops.zero?

        errors.to_f / total_ops
      end

      def calculate_operation_performance(operation)
        times = @stats[:access_times][operation]
        return nil unless times && !times.empty?

        {
          avg: times.sum / times.size,
          min: times.min,
          max: times.max,
          count: times.size
        }
      end

      def format_duration(seconds)
        if seconds < 60
          "#{seconds.round(1)}s"
        elsif seconds < 3600
          "#{(seconds / 60).round(1)}m"
        else
          "#{(seconds / 3600).round(1)}h"
        end
      end

      def format_operations(operations)
        operations.map { |op, count| "  #{op}: #{count}" }.join("\n")
      end

      def format_errors(errors)
        return "  None" if errors.empty?

        errors.map { |op, count| "  #{op}: #{count}" }.join("\n")
      end

      def format_performance(performance)
        return "  No timing data available" if performance.empty?

        performance.map do |op, stats|
          "  #{op}: avg=#{(stats[:avg] * 1000).round(2)}ms, " \
          "min=#{(stats[:min] * 1000).round(2)}ms, " \
          "max=#{(stats[:max] * 1000).round(2)}ms"
        end.join("\n")
      end
    end
  end
end
