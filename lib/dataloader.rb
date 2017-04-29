require 'thread'

require 'concurrent'
require 'promise'

class Promise
  def wait
    Dataloader.wait

    # Original implementation
    while source
      saved_source = source
      saved_source.wait
      break if saved_source.equal?(source)
    end
  end
end

class BatchPromise < Promise
  def initialize(dataloader)
    @dataloader = dataloader
    @trigger = Promise.new
    @dispatch = @trigger.then { callback }
    @queue = Concurrent::Array.new
    Thread.current[:pending_batches].unshift(self)
  end

  def then(on_fulfill = nil, on_reject = nil, &block)
    @dispatch.then(on_fulfill, on_reject, &block)
  end

  def dispatch
    @trigger.fulfill
    self
  end

  def dispatched?
    !@trigger.pending?
  end

  def queue(key)
    if dispatched?
      raise StandardError, "Cannot queue elements after batch is dispatched. Queued key: #{key}"
    end

    @queue.push(key)

    @dispatch.then do |values|
      unless values.key?(key)
        raise StandardError, "Promise didn't resolve a key: #{key}\nResolved keys: #{values.keys.join(' ')}"
      end

      values[key]
    end
  end

  def callback
    result = @dataloader.batch_load.call(@queue)
    if result.is_a?(Promise)
      result.then do |values|
        handle_result(@queue, values)
      end
    else
      Promise.resolve(handle_result(@queue, result))
    end
  end

  def handle_result(keys, values)
    unless values.is_a?(Array) || values.is_a?(Hash)
      raise TypeError, 'Dataloader must be constructed with a block which accepts ' \
        'Array<Object> and returns Array<Object> or Hash<Object, Object>. ' \
        "Block returned instead: #{values}."
    end

    if keys.size != values.size
      raise TypeError, 'Dataloader must be instantiated with function that returns Array or Hash ' \
        'of the same size as provided to it Array of keys' \
        "\n\nProvided keys:\n#{keys}" \
        "\n\nReturned values:\n#{values}"
    end

    values = Hash[keys.zip(values)] if values.is_a?(Array)

    values
  end
end

class Dataloader
  VERSION = "0.0.0"

  attr_reader :batch_load

  def initialize(options = {}, &batch_load)
    unless block_given?
      raise TypeError, 'Dataloader must be constructed with a block which accepts ' \
        'Array<Object> and returns Array<Object> or Hash<Object, Object>'
    end

    @options = options
    @batch_load = batch_load

    @promises = Concurrent::Map.new

    Thread.current[:pending_batches] ||= []
  end

  def self.wait
    while !Thread.current[:pending_batches].empty?
      pending = Thread.current[:pending_batches]
      Thread.current[:pending_batches] = []
      pending.each(&:dispatch)
    end
  end

  def compute_if_absent(key)
    cache_key = @options.key?(:key) ? @options.key.call(key) : key

    @promises.compute_if_absent(cache_key) do
      yield
    end
  end

  def batch_promise
    if @batch_promise.nil? || @batch_promise.dispatched?
      @batch_promise = BatchPromise.new(self)
    end

    @batch_promise
  end

  def load(key)
    if key.nil?
      raise TypeError, "The loader.load() must be called with a key, but got: #{key}"
    end

    compute_if_absent(key) do
      batch_promise.queue(key)
    end
  end

  def load_many(keys)
    unless keys.is_a?(Array)
      raise TypeError, "The loader.load_many() must be called with a Array<Object>, but got: #{key}"
    end

    Promise.all(keys.map(&method(:load)))
  end
end
