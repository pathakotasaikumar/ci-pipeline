$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))

require 'thread_helper'

RSpec.describe ThreadHelper do
  before(:context) do
  end

  context '.wait_for_threads' do
    it 'waits for threads' do
      thread_waits = [0.05, 0.1, 0.15]
      thread_items = []

      thread_waits.each do |time|
        thread_items << {
          'action' => "action-#{time}",
          'thread' => Thread.new {
                        sleep(time)
                      }
        }
      end

      result = ThreadHelper.wait_for_threads(thread_items, 0.35)

      expect(result).to be_a_kind_of(Array)
      expect(result.length).to be(2)

      expect(result[0].length).to  be(thread_waits.length)
      expect(result[1].length).to  be(0)

      expect(thread_items.length).to eq(0)
    end

    it 'handles exceptions' do
      thread_waits = [0.05, 0.1, 0.15]
      thread_items = []

      thread_waits.each do |time|
        thread_items << {
          'action' => "action-#{time}",
          'thread' => Thread.new {
                        sleep(time)

                        if time >= 0.15
                          raise "custom err in thread with work time #{time}"
                        end

                        if time >= 0.1
                          raise ActionError.new("Action err in thread with work time #{time}")
                        end
                      }
        }
      end

      result = ThreadHelper.wait_for_threads(thread_items, 0.35)

      expect(result).to be_a_kind_of(Array)
      expect(result.length).to be(2)

      expect(result[0].length).to  be(thread_waits.length - 2)
      expect(result[1].length).to  be(2)

      expect(thread_items.length).to eq(0)
    end
  end

  context '.join_any' do
    it 'validates input' do
      # array, empty array
      expect {
        ThreadHelper.join_any(nil, 1)
      }.to raise_exception(/Expecting Array for parameter threads/)

      expect {
        ThreadHelper.join_any([], 1)
      }.not_to raise_exception()

      # everything is Thread in the array
      expect {
        ThreadHelper.join_any([1, 2, 3], 1)
      }.to raise_exception(/Expecting an Array of Thread/)

      expect {
        ThreadHelper.join_any([1, Thread.new {}, 3], 1)
      }.to raise_exception(/Expecting an Array of Thread/)

      expect {
        ThreadHelper.join_any([
                                Thread.new {},
                                Thread.new {}
                              ], 0.05)
      }.not_to raise_exception
    end
  end
end
