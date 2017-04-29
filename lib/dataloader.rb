require "concurrent"
require "promise"

# :stopdoc:

class Promise  
  alias_method :wait_old, :wait

  def wait
    Dataloader.wait
    wait_old
  end
end

# :startdoc:

class Dataloader
  VERSION = "1.0.0".freeze

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

      result = @dataloader.batch_load.call(@queue)

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

  private_constant :Batch

  attr_reader :batch_load

  # Creates new dataloader
  #
  # @option options [Proc] :key A function to produce a cache key for a given load key. Defaults to proc { |key| key }. Useful to provide when objects are keys and two similarly shaped objects should be considered equivalent.
  # @yieldparam [Array] array is batched ids to load
  # @yieldreturn [Promise] a promise of loaded value with batch_load block
  def initialize(options = {}, &batch_load)
    unless block_given?
      raise TypeError, "Dataloader must be constructed with a block which accepts " \
        "Array<Object> and returns Array<Object> or Hash<Object, Object>"
    end

    @key = options.fetch(:key, lambda { |key| key })
    @batch_load = batch_load
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

  # Loads a key, returning a [Promise](https://github.com/lgierth/promise.rb) for the value represented by that key.
  # 
  # You can resolve this promise when you actually need the value with `promise.sync`.
  # 
  # All calls to `#load` are batched until the first `#sync` is encountered. Then is starts batching again, et caetera.
  #
  # @param key [Object] key to load using `batch_load` proc
  # @return [Promise<Object>] A Promise of computed value
  # @example Load promises of two users and resolve them:
  #   user_loader = Dataloader.new do |ids|
  #     User.find(*ids)
  #   end
  #
  #   user1_promise = user_loader.load(1)
  #   user2_promise = user_loader.load(2)
  #
  #   user1 = user1_promise.sync
  #   user2 = user2_promise.sync
  def load(key)
    if key.nil?
      raise TypeError, "The loader.load() must be called with a key, but got: #{key}"
    end

    compute_if_absent(key) do
      batch_promise.queue(key)
    end
  end

  # 
  #
  # Loads multiple keys, promising an array of values:
  # 
  # ```ruby
  # promise = loader.load_many(['a', 'b'])
  # object_a, object_b = promise.sync
  # ```
  # 
  # This is equivalent to the more verbose:
  # 
  # ```ruby
  # promise = Promise.all([loader.load('a'), loader.load('b')])
  # object_a, object_b = promise.sync
  # ```
  #
  # @param keys [Array<Object>] list of keys to load using `batch_load` proc
  # @return [Promise<Object>] A Promise of computed values
  # @example Load promises of two users and resolve them:
  #   user_loader = Dataloader.new do |ids|
  #     User.find(*ids)
  #   end
  #
  #   users_promise = user_loader.load_many([1, 2])
  #
  #   user1, user2 = users_promise.sync
  def load_many(keys)
    unless keys.is_a?(Array)
      raise TypeError, "The loader.load_many() must be called with a Array<Object>, but got: #{key}"
    end

    Promise.all(keys.map(&method(:load)))
  end

  protected

  def compute_if_absent(key)
    @cache.compute_if_absent(@key.call(key)) do
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
