# ![](http://i.imgur.com/i0afc40.png) Dataloader

[![Build Status](https://travis-ci.org/sheerun/dataloader.svg?branch=master)](https://travis-ci.org/sheerun/dataloader) [![codecov](https://codecov.io/gh/sheerun/dataloader/branch/master/graph/badge.svg)](https://codecov.io/gh/sheerun/dataloader)


Dataloader is a generic utility to be used as part of your application's data fetching layer to provide a simplified and consistent API to perform batching and caching within a request. It is heavily inspired by [Facebook's dataloader](https://github.com/facebook/dataloader).

## Installation

```ruby
gem "dataloader"
```

## Basic usage

```ruby
# It will be called only once with ids = [1, 2, 3]
loader = Dataloader.new do |ids|
  User.find(*ids)
end

# Schedule data to load
promise_one = loader.load(0)
promise_two = loader.load_many([1, 2])

# Get promises results
user0 = promise_one.sync
user1, user2 = promise_two.sync
```

## API

### `Dataloader`

`Dataloader` is a class for fetching data given unique keys such as the id column (or any other key).

Each `Dataloader` instance contains a unique memoized cache. Because of it, it is recommended to use one `Datalaoder` instane **per web request**. You can use more long-lived instances, but then you need to take care of manually cleaning the cache.

You shound't share the same dataloader instance across different threads. This behavior is currently undefined.

### `Dataloader.new(options = {}, &batch_load)`

Create a new `Dataloader` given a batch loading function and options.

* `batch_load`: A block which accepts an Array of keys, and returns  Array of values or Hash that maps from keys to values (or a [Promise](https://github.com/lgierth/promise.rb) that returns such value).
* `options`: An optional hash of options:
  * `:key` A function to produce a cache key for a given load key. Defaults to proc { |key| key }. Useful to provide when objects are keys and two similarly shaped objects should be considered equivalent.
  * `:cache` An instance of cache used for caching of promies (the only required API is `#compute_if_absent(key)`). Defaults to `Concurrent::Map.new`. Useful for preserving or pre-populating the cache. You can pass `nil` if you want to disable the cache.

### `#load(key)`

Loads a key, returning a [Promise](https://github.com/lgierth/promise.rb) for the value represented by that key.

* key [Object] An key value to load (can be any object)

You can resolve this promise when you actually need the value with `promise.sync`.

All calls to `#load` are batched until the first `#sync` is encountered. Then is starts batching again, et caetera.

### `#load_many(keys)`

* keys [Array<Object>] list of keys to load using `batch_load` proc

Loads multiple keys, promising an array of values:

```ruby
promise = loader.load_many(['a', 'b'])
object_a, object_b = promise.sync
```

This is equivalent to the more verbose:

```ruby
promise = Promise.all([loader.load('a'), loader.load('b')])
object_a, object_b = promise.sync
```

### `#cache`

Returns the internal cache that can be overridden with `:cache` option (see constructor)

## License

MIT
