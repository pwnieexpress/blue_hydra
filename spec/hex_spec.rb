`mkdir /usr/src/bluez`
`chmod 777 /usr/src/bluez`
`cd /usr/src/bluez; apt-get source bluez`
VERSION=`apt-cache policy bluez | grep Installed | awk '{print $2}' | awk -F'-' '{print $1}'`.chomp.freeze
MAIN_C = File.read("/usr/src/bluez/bluez-#{VERSION}/monitor/main.c").freeze
PACKET_C = File.read("/usr/src/bluez/bluez-#{VERSION}/monitor/packet.c").freeze
MAIN_C_SCAN = [ 'Bluetooth monitor ver' ].freeze
PACKET_C_SCAN_BTMON = [
  '{ 0x0f, "Command Status",',
  '{ 0x13, "Number of Completed Packets",',
  '{ 0x0e, "Command Complete",',
  '"New Index", label, details);',
  '"Delete Index", label, NULL);',
  '"Open Index", label, NULL);',
  '"Index Info", label, details);',
  '"Note", message, NULL);',
  '{ 0x03, "Connect Complete",',
  '{ 0x07, "Remote Name Req Complete",'
].freeze
PACKET_C_SCAN_CHUNKER = [
  '{ 0x03, "Connect Complete",',
  '{ 0x12, "Role Change"',
  '{ 0x2f, "Extended Inquiry Result"',
  '{ 0x22, "Inquiry Result with RSSI",',
  '{ 0x07, "Remote Name Req Complete"',
  '{ 0x3d, "Remote Host Supported Features",',
  '{ 0x04, "Connect Request",',
  '{ 0x0e, "Command Complete",',
  '{ 0x3e, "LE Meta Event",',
  '{  0, "LE Connection Complete"			},',
  '{  1, "LE Advertising Report"			},'
].freeze

describe "Hex needed for" do
  describe "btmon handler" do
    MAIN_C_SCAN.each do |phrase|
      it "including #{phrase}" do
        expect(MAIN_C.scan(phrase).size).to eq(1)
      end
    end
    PACKET_C_SCAN_BTMON.each do |phrase|
      it "including #{phrase}" do
        expect(PACKET_C.scan(phrase).size).to eq(1)
      end
    end
  end

  describe "chunker" do
    PACKET_C_SCAN_CHUNKER.each do |phrase|
      it "including #{phrase}" do
        expect(PACKET_C.scan(phrase).size).to eq(1)
      end
    end
  end
end
