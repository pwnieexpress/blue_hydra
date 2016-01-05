require 'spec_helper'

describe BlueHydra::Parser do

  it "can calculate the indentation of a given line" do
    p = BlueHydra::Parser.new

    lines = [
      'test line',
      ' test line',
      '  test line',
      '   test line',
      '    test line',
      '     test line'
    ]

    lines.each_with_index do |ln, i|
      expect(p.line_depth(ln)).to eq(i)
    end
  end

  it "groups arrays of strings by whitespace depth" do
    p = BlueHydra::Parser.new
    x, y, z = "x", " y", "  z"

    a = [ x, x ]
    b = [ x, y ]
    c = [ x, x, y, y, z, x, y]

    ra = p.group_by_depth(a)
    rb = p.group_by_depth(b)
    rc = p.group_by_depth(c)
    expect(ra).to eq([[x],[x]])
    expect(rb).to eq([[x,y]])
    expect(rc).to eq([[x], [x, y, y, z], [x, y]])
  end


  it "converts a chunk of info about a device into a hash of attributes" do
    filepath = File.expand_path('../fixtures/btmon.stdout', __FILE__)
    command = "cat #{filepath} && sleep 1"
    queue1  = Queue.new
    queue2  = Queue.new
    spawner = BlueHydra::PtySpawner.new(command, queue1)
    chunker = BlueHydra::Chunker.new(queue1, queue2)


    t = Thread.new do
      chunker.chunk_it_up
    end

    chunks = []

    sleep 2 # let the chunker chunk

    until queue2.empty?
      chunks << queue2.pop
    end

    parsers = chunks.map do |c|
      p = BlueHydra::Parser.new(c)
      p.parse
      p
    end

    # # LOGIC TO PRINT THIS SHIT OUT
    # # LOGIC TO PRINT THIS SHIT OUT
    # # LOGIC TO PRINT THIS SHIT OUT
    # require 'json'
    # attrs = parsers.map(&:attributes)
    # devices = attrs.each_with_object({}) do |attrs, devices|
    #   address = attrs[:address].first
    #   devices[address] ||= {}
    #   attrs.each do |key, vals|
    #     devices[address][key] ||= []
    #     devices[address][key] += vals
    #     devices[address][key] = devices[address][key].uniq
    #   end
    # end

    # devices.each do |mac, attrs|
    #   File.write(
    #     "./devices/#{mac.gsub(':', '-')}_device_info.json", JSON.pretty_generate(attrs)
    #   )
    # end
    # # END SHITTY PRINT LOGIC
    # # END SHITTY PRINT LOGIC
    # # END SHITTY PRINT LOGIC

    addrs = parsers.map do |p|
      p.attributes[:address]
    end

    addrs_per_device = addrs.map(&:uniq).map(&:count).uniq
    expect(addrs_per_device).to eq([1]) # 1 addr per device :)
  end
end
