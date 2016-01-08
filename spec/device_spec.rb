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

  it "serializes some attributes" do
    device = BlueHydra::Device.new
    classic_class = [
      [
        "0x7a020c",
        "Networking (LAN, Ad hoc)",
        "Capturing (Scanner, Microphone)",
        "Object Transfer (v-Inbox, v-Folder)",
        "Audio (Speaker, Microphone, Headset)",
        "Telephony (Cordless telephony, Modem, Headset)"
      ]
    ]

    classic_16_bit_service_uuids = [
      "PnP Information (0x1200)",
      "Handsfree Audio Gateway (0x111f)",
      "Phonebook Access Server (0x112f)",
      "Audio Source (0x110a)",
      "A/V Remote Control Target (0x110c)",
      "NAP (0x1116)",
      "Message Access Server (0x1132)"
    ]

    le_16_bit_service_uuids = ["Unknown (0xfeed)"]

    device.classic_class = classic_class
    device.classic_16_bit_service_uuids = classic_16_bit_service_uuids
    device.le_16_bit_service_uuids = le_16_bit_service_uuids

    expect(device.classic_class.first).to eq("Networking (LAN, Ad hoc)")
    expect(device.classic_16_bit_service_uuids.first).to eq("PnP Information")
    expect(device.le_16_bit_service_uuids.first).to eq("Unknown")
  end
end
