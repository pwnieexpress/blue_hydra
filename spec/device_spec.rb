require 'spec_helper'

# the actual bluetooth devices dawg
describe BlueHydra::Device do
  it "has useful attributes" do
    device = BlueHydra::Device.new

    %w{
      id
      name
      status
      address
      uap_lap
      vendor
      appearance
      company
      company_type
      lmp_version
      manufacturer
      firmware
      classic_mode
      classic_service_uuids
      classic_channels
      classic_major_class
      classic_minor_class
      classic_class
      classic_rssi
      classic_tx_power
      classic_features
      classic_features_bitmap
      le_mode
      le_service_uuids
      le_address_type
      le_random_address_type
      le_flags
      le_rssi
      le_tx_power
      le_features
      le_features_bitmap
      created_at
      updated_at
      last_seen
      uuid
    }.each do |attr|
      expect(device.respond_to?(attr)).to eq(true)
    end
  end

  it "generates a uuid when saving" do
    d = BlueHydra::Device.new
    d.address = "DE:AD:BE:EF:CA:FE"
    expect(d.uuid).to eq(nil)
    d.save
    expect(d.uuid.class).to eq(String)
    uuid_regex = /^[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}$/
    expect(d.uuid =~ uuid_regex).to eq(0)
  end

  it "sets a uap_lap from an address" do
    address  = "D5:AD:B5:5F:CA:F5"
    device = BlueHydra::Device.new
    device.address = address
    device.save
    expect(device.uap_lap).to eq("B5:5F:CA:F5")

    device2 = BlueHydra::Device.find_by_uap_lap("FF:00:B5:5F:CA:F5")
    expect(device2).to eq(device)
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

    classic_uuids = [
      "PnP Information (0x1200)",
      "Handsfree Audio Gateway (0x111f)",
      "Phonebook Access Server (0x112f)",
      "Audio Source (0x110a)",
      "A/V Remote Control Target (0x110c)",
      "NAP (0x1116)",
      "Message Access Server (0x1132)"
    ]

    le_uuids = ["Unknown (0xfeed)"]

    device.classic_class = classic_class
    device.classic_service_uuids = classic_uuids
    device.le_service_uuids = le_uuids

    expect(JSON.parse(device.classic_class).first).to eq("Networking (LAN, Ad hoc)")
    expect(JSON.parse(device.classic_service_uuids).first).to eq("PnP Information (0x1200)")
    expect(JSON.parse(device.le_service_uuids).first).to eq("Unknown (0xfeed)")
  end

  it "create or updates from a hash" do
    raw = {
      classic_num_responses: ["1"],
      address: ["00:00:00:00:00:00"],
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
      classic_service_uuids: [
        "PnP Information (0x1200)",
        "Handsfree Audio Gateway (0x111f)",
        "Phonebook Access Server (0x112f)",
        "Audio Source (0x110a)",
        "A/V Remote Control Target (0x110c)",
        "NAP (0x1116)",
        "Message Access Server (0x1132)",
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

    device = BlueHydra::Device.update_or_create_from_result(raw)

    expect(device.address).to eq("00:00:00:00:00:00")
    expect(device.name).to eq("iPhone")
    expect(
      JSON.parse(device.classic_class).first).to eq("Networking (LAN, Ad hoc)")
    expect(
      JSON.parse(device.classic_service_uuids).first).to eq("PnP Information (0x1200)")
  end
end
