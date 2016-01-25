class BlueHydra::Device
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i

  include DataMapper::Resource

  property :id,                            Serial

  property :name,                          String
  property :address,                       String
  property :oui,                           Text
  property :status,                        String
  property :appearance,                    String

  property :company,                       String
  property :company_type,                  String

  property :classic_lmp_version,           String
  property :classic_manufacturer,          String
  property :classic_features,              Text
  property :classic_firmware,              String
  property :classic_channels,              String
  property :classic_major_class,           String
  property :classic_minor_class,           String
  property :classic_class,                 Text
  property :classic_rssi,                  Text

  property :uuids,                         Text

  property :le_address_type,               String
  property :le_random_address_type,        String
  property :le_lmp_version,                String
  property :le_features,                   Text
  property :le_flags,                      Text
  property :le_address_type,               Text
  property :le_rssi,                       Text

  property :le_tx_power,                   Text
  property :classic_tx_power,              Text

  property :le_mode,                       Boolean
  property :classic_mode,                  Boolean

  property :created_at,                    DateTime
  property :updated_at,                    DateTime
  property :last_seen,                     Integer

  validates_format_of :address, with: MAC_REGEX

  before :save, :set_oui
  before :save, :set_mode_flags
  after  :save, :sync_to_pulse

  # def self.update_device_file(result)
  #   address = result[:address].first
  #   file_path = File.expand_path(
  #     "../../../devices/#{address.gsub(':', '-')}_device_info.json", __FILE__
  #   )
  #   base = if File.exists?(file_path)
  #            JSON.parse(
  #              File.read(file_path),
  #              symbolize_names: true
  #            )
  #          else
  #            {}
  #          end
  #   result.each do |key, values|
  #     if base[key]
  #       base[key] = (base[key] + values).uniq
  #     else
  #       base[key] = values.uniq
  #     end
  #   end
  #   File.write(file_path, JSON.pretty_generate(base))
  # end

  def self.update_or_create_from_result(result)

    # # log raw results into device files for review
    # if BlueHydra.config[:log_level] == "debug"
    #   update_device_file(result.dup)
    # end

    result = result.dup

    address = result[:address].first

    record = self.all(address: address).first || self.new

    # if we are processing things here we have, implicitly seen them so
    # mark as online?
    record.status = "online"

    if result[:last_seen] &&
      result[:last_seen].class == Array &&
      !result[:last_seen].empty?
      record.last_seen = result[:last_seen].sort.last # latest value
    else
      record.last_seen = Time.now.to_i
    end

    %w{
      address name classic_manufacturer short_name
      classic_lmp_version classic_firmware classic_major_class
      classic_minor_class le_lmp_version le_tx_power classic_tx_power
      le_address_type company company_type appearance le_address_type
      le_random_address_type
    }.map(&:to_sym).each do |attr|
      if result[attr]
        if result[attr].uniq.count > 1
          BlueHydra.logger.warn(
            "#{address} multiple values detected for #{attr}: #{result[attr].inspect}. Using first value..."
          )
        end
        record.send("#{attr.to_s}=", result.delete(attr).uniq.first)
      end
    end

    %w{
      classic_features le_features le_flags classic_channels
      bt_128_bit_service_uuids classic_class le_rssi classic_rssi
      uuids
    }.map(&:to_sym).each do |attr|
      if result[attr]
        record.send("#{attr.to_s}=", result.delete(attr))
      end
    end

    if record.valid?
      record.save
    else
      BlueHydra.logger.warn(
        "#{address} can not save. attrs: #{ record.attributes.inspect }"
      )
    end

    record
  end

  def set_oui
    vendor = Louis.lookup(address)
    if self.oui == nil || self.oui == "Unknown"
      self.oui = vendor["long_vendor"] ? vendor["long_vendor"] : vendor["short_vendor"]
    end
  end

  def sync_to_pulse
    data = self.attributes.dup

    [:id, :created_at, :updated_at].each do |attr|
      data.delete(attr)
    end

    send_data = {
      type:   "bluetooth",
      source: "BlueHydra",
      version: BlueHydra::VERSION,
      data:    data
    }

    json = JSON.generate(send_data)

    File.write("/root/json/#{address}.json", json)

    # TCPSocket.open('127.0.0.1', 8244) do |sock|
    #   sock.write(json)
    #   sock.write("\n")
    #   sock.flush
    # end
  rescue => e
    BlueHydra.logger.warn "Unable to connect to Hermes (#{e.message}), unable to send to pulse"
  end

  def set_mode_flags
    classic = false
    [
      :classic_channels,
      :classic_class,
      :classic_features,
      :classic_firmware,
      :classic_lmp_version,
      :classic_major_class,
      :classic_manufacturer,
      :classic_minor_class,
      :classic_mode,
      :classic_rssi,
      :classic_tx_power,
    ].each do |classic_attr|
      if self[classic_attr]
        classic ||= true
      end
    end
    self[:classic_mode] = classic


    le = false
    [
      :le_address_type,
      :le_features,
      :le_flags,
      :le_lmp_version,
      :le_mode,
      :le_rssi,
      :le_tx_power,
    ].each do |le_attr|
      if self[le_attr]
        le ||= true
      end
    end
    self[:le_mode] = le
  end

  def short_name=(new)
    unless ["",nil].include?(new) || self.name
      self.name = new
    end
  end

  def primary_services=(new)
    current = JSON.parse(self.classic_class || '[]')
    self[:primary_services] = JSON.generate((new + current).uniq)
  end

  def classic_channels=(channels)
    new = channels.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.classic_class || '[]')
    self[:classic_channels] = JSON.generate((new + current).uniq)
  end

  def classic_class=(new_classes)
    new = new_classes.flatten.uniq.reject{|x| x =~ /^0x/}
    current = JSON.parse(self.classic_class || '[]')
    self[:classic_class] = JSON.generate((new + current).uniq)
  end

  def classic_features=(features)
    new = features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.classic_features || '[]')
    self[:classic_features] = JSON.generate((new + current).uniq)
  end

  def le_features=(features)
    new = features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.le_features || '[]')
    self[:le_features] = JSON.generate((new + current).uniq)
  end

  def le_flags=(flags)
    new = flags.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.le_flags || '[]')
    self[:le_flags] = JSON.generate((new + current).uniq)
  end

  def uuids=(new_uuids)
    current = JSON.parse(self.uuids || '[]')
    self[:uuids] = JSON.generate((new_uuids + current).uniq)
  end

  def bt_128_bit_service_uuids=(new_uuids)
    new_uuids.map! do |uuid|
      #TODO extend based on lookup table as available..
      if uuids =~ /\(/
        uuid
      else
        "Unknown (#{ uuid })"
      end
    end
    self.uuids = new_uuids
  end

  def classic_rssi=(rssis)
    current = JSON.parse(self.classic_rssi || '[]')
    new = current + rssis

    until new.count <= 100
      new.shift
    end

    self[:classic_rssi] = JSON.generate(new)
  end

  def le_rssi=(rssis)
    current = JSON.parse(self.le_rssi || '[]')
    new = current + rssis

    until new.count <= 100
      new.shift
    end

    self[:le_rssi] = JSON.generate(new)
  end

  def le_address_type=(type)
    type = type.split(' ')[0]
    if type =~ /Public/
      self[:le_address_type] = type
      self[:le_random_address_type] = nil if le_address_type
    elsif type =~ /Random/
      self[:le_address_type] = type
    end
  end

  def le_random_address_type=(type)
    unless le_address_type && le_address_type =~ /Public/
      self[:le_random_address_type] = type
    end
  end

end
