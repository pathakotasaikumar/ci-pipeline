module ThreadHelper
  extend self
  # Wait for all threads to complete
  def wait_for_threads(thread_items, poll_time = 10.0)
    successful = []
    failed = []

    # Wait for all consumables to finish running
    while thread_items.any?
      join_any(thread_items.map { |thread_item| thread_item['thread'] }, poll_time)

      thread_items.each do |thread_item|
        thread = thread_item['thread']

        if thread.status == false
          thread_item['status'] = :success
          thread_item['exception'] = nil
          thread_item['outputs'] = thread.value
          thread_item.delete('thread')
          successful << thread_item
        elsif thread.status.nil?
          begin
            thread.join
          rescue ActionError => e
            Log.error "#{e}\n" + e.backtrace.join("\n")
            thread_item['status'] = :failed
            thread_item['exception'] = e
            thread_item['outputs'] = e.partial_outputs
          rescue => e
            Log.error "#{e}\n" + e.backtrace.join("\n")
            thread_item['status'] = :failed
            thread_item['exception'] = e
            thread_item['outputs'] = {}
          end
          thread_item.delete('thread')
          failed << thread_item
        end
      end

      # Delete handled threads from the list of thread items
      thread_items.delete_if { |thread_item| !thread_item.has_key? 'thread' }
    end

    return successful, failed
  end

  # Block until at least one of the threads in the list has completed execution
  def join_any(threads, poll_time = 10.0)
    # Validate parameters
    raise "Expecting Array for parameter threads, received #{threads.class.inspect}" unless threads.is_a? Array
    raise "Expecting an Array of Thread objects for parameter threads" unless threads.all? { |thread| thread.is_a? Thread }
    raise "Expecting Numeric for poll_time threads, received #{poll_time.class.inspect}" unless poll_time.is_a? Numeric

    # Exit immediately if no threads provided
    return if threads.empty?

    # Block while none of the threads have completed
    while threads.all?(&:status)
      sleep(poll_time)
    end
  end
end
