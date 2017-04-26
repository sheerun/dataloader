describe Dataloader do
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
