describe Dataloader do
  it 'can resolve single value' do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    one = loader.load(1)

    expect(one.sync).to eq("awesome 1")
  end

  it 'can resolve two values one separately' do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    one = loader.load(1)
    two = loader.load(2)

    expect(one.sync).to eq("awesome 1")
    expect(two.sync).to eq("awesome 2")
  end

  it 'can resolve multiple values' do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    promise = loader.load_many([1, 2])

    one, two = promise.sync

    expect(one).to eq("awesome 1")
    expect(two).to eq("awesome 2")
  end

  it 'can resolve multiple values' do
    loader = Dataloader.new do |ids|
      ids.map { |id| "awesome #{id}" }
    end

    promise = loader.load_many([1, 2])

    one, two = promise.sync

    expect(one).to eq("awesome 1")
    expect(two).to eq("awesome 2")
  end

  it 'runs loader just one time, even for multiple values' do
    loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    one = loader.load(1)
    two = loader.load(2)

    expect(one.sync).to eq([1,2])
    expect(two.sync).to eq([1,2])
  end

  it 'runs loader just one time, even for mixed access values' do
    loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    first = loader.load_many([1,2])
    loader.load(3)

    expect(first.sync[0]).to eq([1,2,3])
    expect(first.sync[1]).to eq([1,2,3])
  end

  it 'can return a hash instead of an array' do
    loader = Dataloader.new do |ids|
      Hash[ids.zip(ids.map { |id| id + 10  })]
    end

    first = loader.load_many([1,2])
    second = loader.load(3)

    expect(first.sync[0]).to eq(11)
    expect(first.sync[1]).to eq(12)
    expect(second.sync).to eq(13)
  end

  it 'does not run if no need to' do
    calls = 0
    loader = Dataloader.new do |ids|
      calls = calls + 1
      Hash[ids.zip(ids.map { |id| ids })]
    end

    loader.load_many([1,2])
    loader.load(3)

    expect(calls).to eq(0)
  end

  it 'works even if loader resolves to a promise executed out of order' do
    promise = Promise.new

    loader = Dataloader.new do |ids|
      ids.map { |id|
        promise.then do |value|
          value + id + 40
        end
      }
    end

    plus_fourty = loader.load(2)
    promise.fulfill(100)

    expect(plus_fourty.sync).to eq(142)
  end

  it 'works if promise is passed as an argument to dataloader' do
    promise = Promise.new

    loader = Dataloader.new do |promises|
      promises.map { |promise|
        promise.then do |value|
          value + 40
        end
      }
    end

    plus_fourty = loader.load(promise)
    promise.fulfill(100)

    expect(plus_fourty.sync).to eq(140)
  end

  it 'can depend on other loaders' do
    data_loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    data_transformer = Dataloader.new do |ids|
      data_loader.load_many(ids).then do |records|
        records.map { |r| r.count }
      end
    end

    three = data_loader.load(3)
    one = data_transformer.load(1)
    two = data_transformer.load(2)


    expect(one.sync).to eq(3)
    expect(two.sync).to eq(3)
    expect(three.sync).to eq([3,1,2])
  end

  it 'does not run what it does not need to when chaining' do
    data_loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    data_transformer = Dataloader.new do |ids|
      data_loader.load_many(ids).then do |records|
        records.map { |r| r.count }
      end
    end

    one = data_transformer.load(1)
    two = data_transformer.load(2)
    three = data_loader.load(3)

    expect(three.sync).to eq([3])
    expect(one.sync).to eq(2)
    expect(two.sync).to eq(2)
  end

  it 'supports loading out of order when chaining' do
    data_loader = Dataloader.new do |ids|
      ids.map { |id| ids }
    end

    data_transformer = Dataloader.new do |ids|
      data_loader.load_many(ids).then do |records|
        records.map { |r| r.count }
      end
    end

    three = data_loader.load(3)
    one = data_transformer.load(1)
    two = data_transformer.load(2)

    expect(three.sync).to eq([3, 1, 2])
    expect(one.sync).to eq(3)
    expect(two.sync).to eq(3)
  end

  it 'can resolves promises as usual' do
    loader = Dataloader.new do |ids|
      puts "Loading records: #{ids.join(' ')}"
      Hash[ids.zip(ids.map { |id| { id: id, name: "Something #{id}" } })]
    end

    loader2 = Dataloader.new(name: 'names') do |ids|
      puts "Loading names: #{ids.join(' ')}"
      loader.load_many(ids).then do |records|
        Hash[ids.zip(records.map { |r| r[:name] })]
      end
    end

    one = loader.load(0)
    two = loader.load_many([1, 2])
    three = loader.load_many([2, 3])
    four = loader2.load_many([2, 3, 5])

    loader3 = Dataloader.new(name: 'awesome') do |ids|
      puts "Loading awesome names: #{ids.join(' ')}"
      loader2.load_many(ids).then do |names|
        Hash[ids.zip(names.map { |name| "Awesome #{name}" })]
      end
    end

    five = loader3.load_many([2, 3, 5, 7])

    Dataloader.wait

    puts five.sync
    puts four.sync
    puts three.sync
    puts two.sync
    puts one.sync

    expect(true).to be(true)
  end
end
