describe Dataloader do
  it "can resolve single value" do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    one = loader.load(1)

    expect(one.sync).to eq("awesome 1")
  end

  it "can resolve two values one separately" do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    one = loader.load(1)
    two = loader.load(2)

    expect(one.sync).to eq("awesome 1")
    expect(two.sync).to eq("awesome 2")
  end

  it "can resolve multiple values" do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    promise = loader.load_many([1, 2])

    one, two = promise.sync

    expect(one).to eq("awesome 1")
    expect(two).to eq("awesome 2")
  end

  it "can resolve multiple values" do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    promise = loader.load_many([1, 2])

    one, two = promise.sync

    expect(one).to eq("awesome 1")
    expect(two).to eq("awesome 2")
  end

  it "runs loader just one time, even for multiple values" do
    loader = Dataloader.new do |ids|
      ids.map { |_id| ids }
    end

    one = loader.load(1)
    two = loader.load(2)

    expect(one.sync).to eq([1, 2])
    expect(two.sync).to eq([1, 2])
  end

  it "runs loader just one time, even for mixed access values" do
    loader = Dataloader.new do |ids|
      ids.map { |_id| ids }
    end

    first = loader.load_many([1, 2])
    loader.load(3)

    expect(first.sync[0]).to eq([1, 2, 3])
    expect(first.sync[1]).to eq([1, 2, 3])
  end

  it "can return a hash instead of an array" do
    loader = Dataloader.new do |ids|
      Hash[ids.zip(ids.map { |id| id + 10 })]
    end

    first = loader.load_many([1, 2])
    second = loader.load(3)

    expect(first.sync[0]).to eq(11)
    expect(first.sync[1]).to eq(12)
    expect(second.sync).to eq(13)
  end

  it "does not run if no need to" do
    calls = 0
    loader = Dataloader.new do |ids|
      calls += 1
      Hash[ids.zip(ids.map { |_id| ids })]
    end

    loader.load_many([1, 2])
    loader.load(3)

    expect(calls).to eq(0)
  end

  it "works even if loader resolves to a promise executed out of order" do
    promise = Promise.new

    loader = Dataloader.new do |ids|
      ids.map do |id|
        promise.then do |value|
          value + id + 40
        end
      end
    end

    plus_fourty = loader.load(2)
    promise.fulfill(100)

    expect(plus_fourty.sync).to eq(142)
  end

  it "works if promise is passed as an argument to dataloader" do
    promise = Promise.new

    loader = Dataloader.new do |promises|
      promises.map do |p|
        p.then do |value|
          value + 40
        end
      end
    end

    plus_fourty = loader.load(promise)
    promise.fulfill(100)

    expect(plus_fourty.sync).to eq(140)
  end

  it "can depend on other loaders" do
    data_loader = Dataloader.new do |ids|
      ids.map { |_id| ids }
    end

    data_transformer = Dataloader.new do |ids|
      data_loader.load_many(ids).then do |records|
        records.map(&:count)
      end
    end

    three = data_loader.load(3)
    one = data_transformer.load(1)
    two = data_transformer.load(2)

    expect(one.sync).to eq(3)
    expect(two.sync).to eq(3)
    expect(three.sync).to eq([3, 1, 2])
  end

  it "does not run what it does not need to when chaining" do
    data_loader = Dataloader.new do |ids|
      ids.map { |_id| ids }
    end

    data_transformer = Dataloader.new do |ids|
      data_loader.load_many(ids).then do |records|
        records.map(&:count)
      end
    end

    one = data_transformer.load(1)
    two = data_transformer.load(2)
    three = data_loader.load(3)

    expect(three.sync).to eq([3])
    expect(one.sync).to eq(2)
    expect(two.sync).to eq(2)
  end

  it "supports loading out of order when chaining" do
    data_loader = Dataloader.new do |ids|
      ids.map { |_id| ids }
    end

    data_transformer = Dataloader.new do |ids|
      data_loader.load_many(ids).then do |records|
        records.map(&:count)
      end
    end

    three = data_loader.load(3)
    one = data_transformer.load(1)
    two = data_transformer.load(2)

    expect(three.sync).to eq([3, 1, 2])
    expect(one.sync).to eq(3)
    expect(two.sync).to eq(3)
  end

  it "caches values for each key" do
    calls = 0

    data_loader = Dataloader.new do |ids|
      calls += 1
      ids.map { |id| id }
    end

    one = data_loader.load(1)
    two = data_loader.load(2)

    expect(one.sync).to be(1)
    expect(two.sync).to be(2)

    one2 = data_loader.load(1)
    two2 = data_loader.load(2)

    expect(one2.sync).to be(1)
    expect(two2.sync).to be(2)

    expect(calls).to be(1)
  end

  it "uses cache for load_many as well (per-item)" do
    calls = 0
    data_loader = Dataloader.new do |ids|
      calls += 1
      ids.map { |_id| ids }
    end

    2.times do
      one = data_loader.load_many([1, 2])
      two = data_loader.load_many([2, 3])

      expect(one.sync[0]).to eq([1, 2, 3])
      expect(one.sync[1]).to eq([1, 2, 3])
      expect(two.sync[0]).to eq([1, 2, 3])
      expect(two.sync[1]).to eq([1, 2, 3])
    end

    expect(calls).to eq(1)
  end

  it "can resolve in complex cases" do
    loads = []

    loader = Dataloader.new do |ids|
      loads.push(["loader", ids])
      ids.map { |id| { name: "bar #{id}" } }
    end

    loader2 = Dataloader.new do |ids|
      loads.push(["loader2", ids])

      loader.load_many(ids).then do |records|
        Hash[ids.zip(records.map { |r| r[:name] })]
      end
    end

    one = loader.load(0)
    two = loader.load_many([1, 2])
    three = loader.load_many([2, 3])
    four = loader2.load_many([2, 3, 5])

    loader3 = Dataloader.new do |ids|
      loads.push(["loader3", ids])

      loader2.load_many(ids).then do |names|
        Hash[ids.zip(names.map { |name| "foo #{name}" })]
      end
    end

    five = loader3.load_many([2, 3, 5, 7])

    expect(five.sync).to eq(["foo bar 2", "foo bar 3", "foo bar 5", "foo bar 7"])
    expect(four.sync).to eq(["bar 2", "bar 3", "bar 5"])
    expect(three.sync).to eq([{ name: "bar 2" }, { name: "bar 3" }])
    expect(two.sync).to eq([{ name: "bar 1" }, { name: "bar 2" }])
    expect(one.sync).to eq(name: "bar 0")

    expect(loads).to eq([
                          ["loader3", [2, 3, 5, 7]],
                          ["loader2", [2, 3, 5, 7]],
                          ["loader", [0, 1, 2, 3, 5, 7]]
                        ])
  end

  it 'can be passed a primed cache' do
    cache = Concurrent::Map.new
    cache[0] = 42

    data_loader = Dataloader.new(cache: cache) do |ids|
      ids.map { |id| id }
    end

    expect(data_loader.load(0).sync).to eq(42)
  end

  it 'can be passed a primed cache with promises' do
    cache = Concurrent::Map.new
    cache[0] = Promise.new.fulfill(42)

    data_loader = Dataloader.new(cache: cache) do |ids|
      ids.map { |id| id }
    end

    expect(data_loader.load(0).sync).to eq(42)
  end

  it 'can be passed custom cache' do
    class Cache
      def compute_if_absent(key)
        42
      end
    end

    data_loader = Dataloader.new(cache: Cache.new) do |ids|
      ids.map { |id| id }
    end

    expect(data_loader.load(0).sync).to eq(42)
  end

  it 'can disable the cache' do
    data_loader = Dataloader.new(cache: nil) do |ids|
      ids.map { |id| ids }
    end

    one = data_loader.load(0)
    two = data_loader.load(0)

    expect(one.sync).to eq([0,0])
  end

  it 'can reset the cache' do
    data_loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    one = data_loader.load(0).sync

    data_loader.cache = Concurrent::Map.new
    data_loader.cache[0] = 42

    one_again = data_loader.load(0)

    expect(one_again.sync).to eq(42)
  end

  it 'raises an TypeError if keys passed to load_many are not array' do
    data_loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    expect {
      data_loader.load_many(42)
    }.to raise_error(TypeError, "#load_many must be called with an Array, but got: Integer")
  end

  it 'raises an TypeError if keys passed to load is nil' do
    data_loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    expect {
      data_loader.load(nil)
    }.to raise_error(TypeError, "#load must be called with a key, but got: nil")
  end
end
