require 'spec_helper'

describe BlueHydra::Runner do
  it "takes a command" do
    filepath = File.expand_path('../fixtures/btmon.stdout', __FILE__)
    command = "cat #{filepath} && sleep 1"
    runner = BlueHydra::Runner.new
    runner.start(command)
    sleep 5

    created_device = BlueHydra::Device.all(address: 'B3:3F:CA:F3:DE:AD').first

    expect(created_device.lmp_version).to eq("Bluetooth 4.1 (0x07) - Subversion 16653 (0x410d)")
    expect(JSON.parse(created_device.classic_features).first).to eq("3 slot packets")
    expect(created_device.last_seen.class).to eq(Fixnum)
  end
end
