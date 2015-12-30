require 'spec_helper'

describe PxRealtimeBluetooth::PtySpawner do
  it "a class" do
    expect(PxRealtimeBluetooth::PtySpawner.class).to eq(Class)
  end

  it "will break the output of bluetooth data into chunks to be parsed" do
    filepath = File.expand_path('../fixtures/btmon.stdout', __FILE__)
    command = "cat #{filepath} && sleep 1"
    queue = Queue.new
    spawner = PxRealtimeBluetooth::PtySpawner.new(command, queue)

    expect(queue.empty?).to eq(false)
  end
end
