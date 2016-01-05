require 'spec_helper'

# the actual bluetooth devices dawg
describe BlueHydra::Device do
  it "has useful attributes" do
    device = BlueHydra::Device.new

    expect(device.respond_to?(:id)).to eq(true)
    expect(device.respond_to?(:address)).to eq(true)
  end
end
