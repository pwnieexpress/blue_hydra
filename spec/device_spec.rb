require 'spec_helper'

# the actual bluetooth devices dawg
describe BlueHydra::Device do
  it "has useful attributes" do
    device = BlueHydra::Device.new

    %w{
      id
      address
    }.each do |attr|
      expect(device.respond_to?(attr)).to eq(true)
    end
  end
end
