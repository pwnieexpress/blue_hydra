require 'spec_helper'

describe BlueHydra::PtySpawner do
  it "a class" do
    expect(BlueHydra::PtySpawner.class).to eq(Class)
  end

  it "will break the output of bluetooth data into chunks to be parsed" do
    filepath = File.expand_path('../fixtures/btmon.stdout', __FILE__)
    command = "cat #{filepath} && sleep 1"
    queue = Queue.new
    spawner = BlueHydra::PtySpawner.new(command, queue)

    expect(queue.empty?).to eq(false)
  end
end
