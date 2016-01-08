require 'spec_helper'

# the actual bluetooth devices dawg
describe BlueHydra::Device do
  it "has useful attributes" do
    device = BlueHydra::Device.new

    %w{
      id
      address
      oui
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

    expect(JSON.parse(device.classic_class).first).to eq("Networking (LAN, Ad hoc)")
    expect(JSON.parse(device.classic_16_bit_service_uuids).first).to eq("PnP Information")
    expect(JSON.parse(device.le_16_bit_service_uuids).first).to eq("Unknown")
  end

  it "create or updates from a hash" do
    raw = {
      classic_num_responses: ["1"],
      address: ["00:00:00:00:00:00"],
      oui: ["(Apple)"],
      classic_page_scan_repetition_mode: ["R1 (0x01)"],
      classic_page_period_mode: ["P2 (0x02)"],
      classic_major_class: ["Phone (cellular, cordless, payphone, modem)"],
      classic_minor_class: ["Smart phone"],
      classic_class: [[
          "0x7a020c",
          "Networking (LAN, Ad hoc)",
          "Capturing (Scanner, Microphone)",
          "Object Transfer (v-Inbox, v-Folder)",
          "Audio (Speaker, Microphone, Headset)",
          "Telephony (Cordless telephony, Modem, Headset)"
        ]],
      classic_clock_offset: ["0x54a2"],
      classic_rssi: ["-36 dBm (0xdc)"],
      name: ["iPhone"],
      classic_16_bit_service_uuids: [
        "PnP Information (0x1200)",
        "Handsfree Audio Gateway (0x111f)",
        "Phonebook Access Server (0x112f)",
        "Audio Source (0x110a)",
        "A/V Remote Control Target (0x110c)",
        "NAP (0x1116)",
        "Message Access Server (0x1132)"
      ],
      classic_128_bit_service_uuids: [
        "00000000-deca-fade-deca-deafdecacafe",
        "2d8d2466-e14d-451c-88bc-7301abea291a"
      ],
      classic_unknown: [
        "[\"        Company: not assigned (19456)\\r\\n\", \"          Type: iBeacon (2)\\r\\n\"]",
        "02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................",
        "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................",
        "00 00                                            .."
      ]
    }

    BlueHydra::Device.update_or_create_from_result(raw)
    device = BlueHydra::Device.last

    expect(device.address).to eq("00:00:00:00:00:00")
    expect(device.oui).to eq("(Apple)")
    expect(device.name).to eq("iPhone")
    expect(
      JSON.parse(device.classic_class).first).to eq("Networking (LAN, Ad hoc)")
    expect(
      JSON.parse(device.classic_16_bit_service_uuids).first).to eq("PnP Information")
  end
end
