require 'spec_helper'

describe BlueHydra::BtmonHandler do
  it "a class" do
    expect(BlueHydra::BtmonHandler.class).to eq(Class)
  end

  it "will break the output of bluetooth data into chunks to be parsed" do
    filepath = File.expand_path('../fixtures/btmon.stdout', __FILE__)
    command = "cat #{filepath} && sleep 1"
    queue = Queue.new

    begin
      handler = BlueHydra::BtmonHandler.new(command, queue)
    rescue BtmonExitedError
      # will be raised in file mode
    end

    expect(queue.empty?).to eq(false)
  end
end
