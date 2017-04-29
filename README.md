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



## License

MIT
