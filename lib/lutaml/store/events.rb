# frozen_string_literal: true

module Lutaml
  module Store
    class Events
      def initialize(async: false)
        @listeners = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
        @async = async
        @queue = async ? Queue.new : nil
        @worker_thread = async ? start_worker_thread : nil
      end

      def on(event, callable = nil, &block)
        listener = callable || block
        raise ArgumentError, "No listener provided" unless listener
        raise ArgumentError, "Event must be a Symbol" unless event.is_a?(Symbol)

        @mutex.synchronize do
          @listeners[event] << listener
        end
      end

      def off(event, listener)
        @mutex.synchronize do
          @listeners[event].delete(listener)
        end
      end

      def emit(event, data = {})
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

      def clear_listeners(event = nil)
        @mutex.synchronize do
          if event
            @listeners[event].clear
          else
            @listeners.clear
          end
        end
      end

      def listener_count(event)
        @mutex.synchronize { @listeners[event].size }
      end

      def stop
        return unless @async && @worker_thread

        @queue << :stop
        @worker_thread.join
        @worker_thread = nil
      end

      private

      def notify_listeners(listeners, event_data)
        listeners.each do |listener|
          listener.call(event_data)
        rescue StandardError => e
          warn "Event listener error: #{e.message}"
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
