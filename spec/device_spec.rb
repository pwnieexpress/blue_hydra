require 'spec_helper'

# the actual bluetooth devices dawg
describe BlueHydra::Device do
  it "has useful attributes" do
    device = BlueHydra::Device.new

    %w{
      id
      address
      oui
      peer_address
      peer_address_type
      peer_address_oui
      role
      lmp_version
      manufacturer
      features
      uuid
      channels
      name
      firmware
    }.each do |attr|
      expect(device.respond_to?(attr)).to eq(true)
    end
  end
end
