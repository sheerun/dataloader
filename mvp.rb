require 'promise'
require 'concurrent'
require 'awesome_print'
require 'byebug'
require 'thread'
require 'thwait'

class Promise
  def wait
    pending = Thread.current[:pending_batches]
    Thread.current[:pending_batches] = []
    pending.each(&:dispatch)
  end
end

class BatchPromise < Promise
  def initialize(batch_load, cache)
    @trigger = Promise.new
    @dispatch = @trigger.then { callback }
    @dispatched = false
    @queue = Concurrent::Array.new
    @batch_load = batch_load
    @cache = cache
    @after_dispatch = Promise.new
    Thread.current[:pending_batches].unshift(self)
  end

  def then(on_fulfill = nil, on_reject = nil, &block)
    @dispatch.then(on_fulfill, on_reject, &block)
  end

  def dispatch
    @dispatched = true
    @trigger.fulfill
    self
  end

  def dispatched?
    @dispatched
  end

  attr_reader :after_dispatch

  def queue(key)
    if @dispatched
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
    @running = true
    keys = @queue - @cache.keys
    result = @batch_load.call(keys)
    @after_dispatch.fulfill
    if result.is_a?(Promise)
      result.then do |values|
        handle_result(keys, values)
      end
    else
      Promise.resolve(handle_result(keys, result))
    end
  end

  def handle_result(keys, values)
    unless values.is_a?(Array) || values.is_a?(Hash)
      raise TypeError, 'DataLoader must be constructed with a block which accepts ' \
        'Array<key> and returns Array<value> or Hash<key, value>. ' \
        "Function returned instead: #{values}."
    end

    if keys.size != values.size
      raise TypeError, 'DataLoader must be instantiated with function that returns Array or Hash ' \
        'of the same size as provided to it Array of keys' \
        "\n\nProvided keys:\n#{keys}" \
        "\n\nReturned values:\n#{values}"
    end

    values = Hash[keys.zip(values)] if values.is_a?(Array)

    values
  end
end

class DataLoader
  def initialize(options = {}, &batch_load)
    unless block_given?
      raise TypeError, 'DataLoader must be constructed with a block which accepts ' \
        'Array<key> and returns Array<value> or Hash<key, value>'
    end

    @options = options
    @batch_load = batch_load

    @promises = Concurrent::Map.new
    @values = Concurrent::Map.new

    Thread.current[:pending_batches] = []
  end

  def self.dispatch
    Thread.current[:pending_batches].each(&:dispatch)
  end

  def log(*args)
    puts "[#{@options[:name]}] #{args.join(' ')}"
  end

  def load(key)
    if key.nil?
      raise TypeError, "The loader.load() must be called with a key, but got: #{key}"
    end

    cache_key_fn = @options.fetch(:key, ->(key) { key })

    cache_key = if cache_key_fn.respond_to?(:call)
                  cache_key_fn.call(key)
                else
                  key[cache_key_fn]
                end

    @promises.compute_if_absent(cache_key) do
      batch = batch_promise
      batch.queue(key)
    end
  end

  def batch_promise
    if @batch_promise.nil? || @batch_promise.dispatched?
      new_promise = create_batch_promise
      if @batch_promise
        Thread.start do
          sleep 0.05
          new_promise.dispatch
        end
      end
      @batch_promise = new_promise
    end

    @batch_promise
  end

  def create_batch_promise
    BatchPromise.new(@batch_load, @values)
  end

  def load_many(keys)
    unless keys.is_a?(Array)
      raise TypeError, "The loader.load_many() must be called with a Array<key>, but got: #{key}"
    end

    Promise.all(keys.map(&method(:load)))
  end

  def dispatch
    @batch_promise.dispatch if @batch_promise && !@batch_promise.dispatched?
  end
end

loader = DataLoader.new do |ids|
  puts "Loading records: #{ids.join(' ')}"
  Hash[ids.zip(ids.map { |id| { id: id, name: "Something #{id}" } })]
end

loader2 = DataLoader.new(name: 'names') do |ids|
  puts "Loading names: #{ids.join(' ')}"
  loader.load_many(ids).then do |records|
    Hash[ids.zip(records.map { |r| r[:name] })]
  end
end

loader3 = DataLoader.new(name: 'awesome') do |ids|
  puts "Loading awesome names: #{ids.join(' ')}"
  loader2.load_many(ids).then do |names|
    Hash[ids.zip(names.map { |name| "Awesome #{name}" })]
  end
end

one = loader.load(0)
two = loader.load_many([1, 2])
three = loader.load_many([2, 3])
four = loader2.load_many([2, 3, 5])
five = loader3.load_many([2, 3, 5, 7])

DataLoader.dispatch

puts five.sync
puts four.sync
puts three.sync
puts two.sync
puts one.sync
