# frozen_string_literal: true

require "thread"

module Lutaml
  module Store
    class Events
      SUPPORTED_EVENTS = %i[get set delete clear store_model get_model delete_model clear_models deserialization_error import_error].freeze

      def initialize(async: false)
        @listeners = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
        @async = async
        @queue = async ? Queue.new : nil
        @worker_thread = async ? start_worker_thread : nil
      end

      # Register an event listener
      # @param event [Symbol] the event to listen for (:get, :set, :delete, :clear)
      # @param callable [Proc, #call] the listener to call when event occurs
      def on(event, callable = nil, &block)
        listener = callable || block
        raise ArgumentError, "No listener provided" unless listener
        raise ArgumentError, "Invalid event: #{event}" unless SUPPORTED_EVENTS.include?(event)

        @mutex.synchronize do
          @listeners[event] << listener
        end
      end

      # Remove an event listener
      # @param event [Symbol] the event to remove listener from
      # @param listener [Proc, #call] the listener to remove
      def off(event, listener)
        @mutex.synchronize do
          @listeners[event].delete(listener)
        end
      end

      # Emit an event to all registered listeners
      # @param event [Symbol] the event to emit
      # @param data [Hash] event data to pass to listeners
      def emit(event, data = {})
        return unless SUPPORTED_EVENTS.include?(event)

        listeners = @mutex.synchronize { @listeners[event].dup }
        return if listeners.empty?

        event_data = {
          event: event,
          timestamp: Time.now,
          **data
        }

        if @async
          @queue << [listeners, event_data]
        else
          notify_listeners(listeners, event_data)
        end
      end

      # Remove all listeners for an event or all events
      # @param event [Symbol, nil] specific event to clear, or nil for all events
      def clear_listeners(event = nil)
        @mutex.synchronize do
          if event
            @listeners[event].clear
          else
            @listeners.clear
          end
        end
      end

      # Get count of listeners for an event
      # @param event [Symbol] the event to count listeners for
      # @return [Integer] number of listeners
      def listener_count(event)
        @mutex.synchronize { @listeners[event].size }
      end

      # Stop the async worker thread (if running)
      def stop
        return unless @async && @worker_thread

        @queue << :stop
        @worker_thread.join
        @worker_thread = nil
      end

      private

      def notify_listeners(listeners, event_data)
        listeners.each do |listener|
          begin
            listener.call(event_data)
          rescue => e
            # Log error but don't let one bad listener break others
            warn "Event listener error: #{e.message}"
          end
        end
      end

      def start_worker_thread
        Thread.new do
          loop do
            item = @queue.pop
            break if item == :stop

            listeners, event_data = item
            notify_listeners(listeners, event_data)
          end
        end
      end
    end
  end
end
