require "concurrent"
require "promise"

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

class Batch
  def initialize(dataloader)
    # Used for storing cache of promises and batch load method
    @dataloader = dataloader
    # Batch can be dispatched only once (it loads all queued promises)
    @dispatched = false
    # This is where result of executing batch is stored
    @result = Promise.new
    # This is where items to batch load are stored
    @queue = Concurrent::Array.new
    # We store pending batches to load per-thread
    Thread.current[:pending_batches].unshift(self)
  end

  def dispatch
    @dispatched = true

    result = @dataloader.load_batch.call(@queue)

    if result.is_a?(Promise)
      result.then do |values|
        @result.fulfill(handle_result(@queue, values))
      end
    else
      @result.fulfill(handle_result(@queue, result))
    end
  end

  def dispatched?
    @dispatched
  end

  def queue(key)
    if @dispatched
      raise StandardError, "Cannot queue elements after batch is dispatched. Queued key: #{key}"
    end

    @queue.push(key)

    @result.then do |values|
      unless values.key?(key)
        raise StandardError, "Promise didn't resolve a key: #{key}\nResolved keys: #{values.keys.join(' ')}"
      end

      values[key]
    end
  end

  protected

  def handle_result(keys, values)
    unless values.is_a?(Array) || values.is_a?(Hash)
      raise TypeError, "Dataloader must be constructed with a block which accepts " \
        "Array<Object> and returns Array<Object> or Hash<Object, Object>. " \
        "Block returned instead: #{values}."
    end

    if keys.size != values.size
      raise TypeError, "Dataloader must be instantiated with function that returns Array or Hash " \
        "of the same size as provided to it Array of keys" \
        "\n\nProvided keys:\n#{keys}" \
        "\n\nReturned values:\n#{values}"
    end

    values = Hash[keys.zip(values)] if values.is_a?(Array)

    values
  end
end

class Dataloader
  VERSION = "1.0.0".freeze

  attr_reader :load_batch

  def initialize(options = {}, &load_batch)
    unless block_given?
      raise TypeError, "Dataloader must be constructed with a block which accepts " \
        "Array<Object> and returns Array<Object> or Hash<Object, Object>"
    end

    @options = options
    @load_batch = load_batch
    @cache = Concurrent::Map.new

    Thread.current[:pending_batches] ||= []
  end

  def self.wait
    until Thread.current[:pending_batches].empty?
      pending = Thread.current[:pending_batches]
      Thread.current[:pending_batches] = []
      pending.each(&:dispatch)
    end
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

  protected

  def compute_if_absent(key)
    cache_key = @options.key?(:key) ? @options.key.call(key) : key

    @cache.compute_if_absent(cache_key) do
      yield
    end
  end

  def batch_promise
    if @batch_promise.nil? || @batch_promise.dispatched?
      @batch_promise = Batch.new(self)
    end

    @batch_promise
  end
end
