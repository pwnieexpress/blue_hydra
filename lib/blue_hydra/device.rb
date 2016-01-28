# this is the bluetooth Device model stored in the DB
class BlueHydra::Device

  # regex to validate macs
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i

  # this is a DataMapper model...
  include DataMapper::Resource

  # Attributes for the DB
  property :id,                            Serial

  property :name,                          String
  property :status,                        String
  property :address,                       String
  property :vendor,                        Text
  property :appearance,                    String
  property :company,                       String
  property :company_type,                  String
  property :lmp_version,                   String
  property :manufacturer,                  String
  property :firmware,                      String

  property :classic_mode,                  Boolean
  property :classic_service_uuids,         Text
  property :classic_channels,              String
  property :classic_major_class,           String
  property :classic_minor_class,           String
  property :classic_class,                 Text
  property :classic_rssi,                  Text
  property :classic_tx_power,              Text
  property :classic_features,              Text
  property :classic_features_bitmap,       String

  property :le_mode,                       Boolean
  property :le_service_uuids,              Text
  property :le_address_type,               String
  property :le_random_address_type,        String
  property :le_flags,                      Text
  property :le_rssi,                       Text
  property :le_tx_power,                   Text
  property :le_features,                   Text
  property :le_features_bitmap,            String

  property :created_at,                    DateTime
  property :updated_at,                    DateTime
  property :last_seen,                     Integer

  # validate the address. the only validation currently
  validates_format_of :address, with: MAC_REGEX

  # before saving set the vendor info and the mode flags (le/classic)
  before :save, :set_vendor
  before :save, :set_mode_flags

  # after saving send up to pulse
  after  :save, :sync_to_pulse

  # this method only gets called in debug mode and will write out device files to
  # the devices local dir to be reviewed. These files will be raw data from the parser
  # before being converted to a model
  #
  # == Parameters :
  #   result ::
  #     Hash of results from parser
  def self.update_device_file(result)
    address = result[:address].first
    file_path = File.expand_path(
      "../../../devices/raw_#{address.gsub(':', '-')}_device_info.json", __FILE__
    )
    base = if File.exists?(file_path)
             JSON.parse( File.read(file_path), symbolize_names: true) else
             {}
             end
    result.each do |key, values|
      if base[key]
        base[key] = (base[key] + values).uniq
      else
        base[key] = values.uniq
      end
    end
    File.write(file_path, JSON.pretty_generate(base))
  end

  # this class method is take a result Hash and convert it into a new or update
  # an existing record
  #
  # == Parameters :
  #   result ::
  #     Hash of results from parser
  def self.update_or_create_from_result(result)

     # log raw results into device files for review in debug mode
     if BlueHydra.config[:log_level] == "debug"
       update_device_file(result.dup)
     end

    result = result.dup

    address = result[:address].first

    record = self.all(address: address).first || self.new

    # if we are processing things here we have, implicitly seen them so
    # mark as online?
    record.status = "online"

    # set last_seen or default value if missing
    if result[:last_seen] &&
      result[:last_seen].class == Array &&
      !result[:last_seen].empty?
      record.last_seen = result[:last_seen].sort.last # latest value
    else
      record.last_seen = Time.now.to_i
    end

    # update normal attributes
    %w{
      address name manufacturer short_name lmp_version firmware
      classic_major_class classic_minor_class le_tx_power classic_tx_power
      le_address_type company company_type appearance le_address_type
      le_random_address_type le_features_bitmap classic_features_bitmap
    }.map(&:to_sym).each do |attr|
      if result[attr]
        # we should only get a single value for these so we need to warn if
        # we are getting multiple values for these keys.. it should NOT be...
        if result[attr].uniq.count > 1
          BlueHydra.logger.warn(
            "#{address} multiple values detected for #{attr}: #{result[attr].inspect}. Using first value..."
          )
        end
        record.send("#{attr.to_s}=", result.delete(attr).uniq.first)
      end
    end

    # update array attributes
    %w{
      classic_features le_features le_flags classic_channels classic_class le_rssi
      classic_rssi le_service_uuids classic_service_uuids
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

  # look up the vendor for the address in the Louis gem
  # and set it
  def set_vendor
    vendor = Louis.lookup(address)
    if self.vendor == nil || self.vendor == "Unknown"
      self.vendor = vendor["long_vendor"] ? vendor["long_vendor"] : vendor["short_vendor"]
    end
  end

  # sync record to pulse
  def sync_to_pulse
    send_data = {
      type:   "bluetooth",
      source: "blue-hydra",
      version: BlueHydra::VERSION,
      data: {}
    }

    # ignore nil value attributes
    send_data[:data][:name]                    = name                              unless name.nil?
    send_data[:data][:status]                  = status                            unless status.nil?
    send_data[:data][:address]                 = address                           unless address.nil?
    send_data[:data][:vendor]                  = vendor                            unless vendor.nil?
    send_data[:data][:appearance]              = appearance                        unless appearance.nil?
    send_data[:data][:company]                 = company                           unless company.nil?
    send_data[:data][:company_type]            = company_type                      unless company_type.nil?
    send_data[:data][:lmp_version]             = lmp_version                       unless lmp_version.nil?
    send_data[:data][:manufacturer]            = manufacturer                      unless manufacturer.nil?
    send_data[:data][:le_features_bitmap]      = le_features_bitmap                unless le_features_bitmap.nil?
    send_data[:data][:le_features]             = JSON.parse(le_features)           unless le_features.nil? || le_features == "[]"
    send_data[:data][:classic_features_bitmap] = classic_features_bitmap           unless classic_features_bitmap.nil?
    send_data[:data][:classic_features]        = JSON.parse(classic_features)      unless classic_features.nil? || classic_features == "[]"
    send_data[:data][:firmware]                = firmware                          unless firmware.nil?
    send_data[:data][:le_service_uuids]        = JSON.parse(le_service_uuids)      unless le_service_uuids.nil? || le_service_uuids == "[]"
    send_data[:data][:classic_service_uuids]   = JSON.parse(classic_service_uuids) unless classic_service_uuids.nil? || classic_service_uuids == "[]"
    send_data[:data][:classic_mode]            = classic_mode                      unless classic_mode.nil?
    send_data[:data][:classic_channels]        = JSON.parse(classic_channels)      unless classic_channels.nil? || classic_channels == "[]"
    send_data[:data][:classic_major_class]     = classic_major_class               unless classic_major_class.nil?
    send_data[:data][:classic_minor_class]     = classic_minor_class               unless classic_minor_class.nil?
    send_data[:data][:classic_class]           = JSON.parse(classic_class)         unless classic_class.nil? || classic_class == "[]"
    send_data[:data][:classic_rssi]            = JSON.parse(classic_rssi)          unless classic_rssi.nil? || classic_rssi == "[]"
    send_data[:data][:classic_tx_power]        = classic_tx_power                  unless classic_tx_power.nil?
    send_data[:data][:le_flags]                = JSON.parse(le_flags)              unless le_flags.nil? || le_flags == "[]"
    send_data[:data][:le_mode]                 = le_mode                           unless le_mode.nil?
    send_data[:data][:le_address_type]         = le_address_type                   unless le_address_type.nil?
    send_data[:data][:le_random_address_type]  = le_random_address_type            unless le_random_address_type.nil?
    send_data[:data][:le_rssi]                 = JSON.parse(le_rssi)               unless le_rssi.nil? || le_rssi == "[]"
    send_data[:data][:le_tx_power]             = le_tx_power                       unless le_tx_power.nil?
    send_data[:data][:last_seen]               = last_seen                         unless last_seen.nil?

    # create the json
    json = JSON.generate(send_data)

    # log raw results into device files for review in debugmode
    if BlueHydra.config[:log_level] == "debug"
      file_path = File.expand_path(
        "../../../devices/synced_#{address.gsub(':', '-')}.json", __FILE__
      )
      File.write(file_path, json)
    end

    # write json data to result socket
    TCPSocket.open('127.0.0.1', 8244) do |sock|
      sock.write(json)
      sock.write("\n")
      sock.flush
    end
  rescue => e
    BlueHydra.logger.warn "Unable to connect to Hermes (#{e.message}), unable to send to pulse"
  end

  # set the le_mode and classic_mode flags to true or false based on the
  # presence of certain attributes being set
  def set_mode_flags
    classic = false
    [
      :classic_service_uuids,
      :classic_channels,
      :classic_major_class,
      :classic_minor_class,
      :classic_class,
      :classic_rssi,
      :classic_tx_power,
      :classic_features,
      :classic_features_bitmap,

    ].each do |classic_attr|
      if self[classic_attr]
        classic ||= true
      end
    end
    self[:classic_mode] = classic


    le = false
    [
      :le_service_uuids,
      :le_address_type,
      :le_random_address_type,
      :le_flags,
      :le_rssi,
      :le_tx_power,
      :le_features,
      :le_features_bitmap,
    ].each do |le_attr|
      if self[le_attr]
        le ||= true
      end
    end
    self[:le_mode] = le
  end

  # set the :name attribute from the :short_name key only if name is not already
  # set
  #
  # == Parameters
  #   new ::
  #     new short name value
  def short_name=(new)
    unless ["",nil].include?(new) || self.name
      self.name = new
    end
  end

  # set the :classic_channels attribute by merging with previously seen values
  #
  # == Parameters
  #   channels ::
  #     new channels
  def classic_channels=(channels)
    new = channels.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.classic_class || '[]')
    self[:classic_channels] = JSON.generate((new + current).uniq)
  end

  # set the :classic_class attribute by merging with previously seen values
  #
  # == Parameters
  #   new_classes ::
  #     new classes
  def classic_class=(new_classes)
    new = new_classes.flatten.uniq.reject{|x| x =~ /^0x/}
    current = JSON.parse(self.classic_class || '[]')
    self[:classic_class] = JSON.generate((new + current).uniq)
  end

  # set the :classic_features attribute by merging with previously seen values
  #
  # == Parameters
  #   new_features ::
  #     new features
  def classic_features=(new_features)
    new = new_features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.classic_features || '[]')
    self[:classic_features] = JSON.generate((new + current).uniq)
  end

  # set the :le_features attribute by merging with previously seen values
  #
  # == Parameters
  #   new_features ::
  #     new features
  def le_features=(new_features)
    new = new_features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.le_features || '[]')
    self[:le_features] = JSON.generate((new + current).uniq)
  end

  # set the :le_flags attribute by merging with previously seen values
  #
  # == Parameters
  #   new_flags ::
  #     new flags
  def le_flags=(flags)
    new = flags.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.le_flags || '[]')
    self[:le_flags] = JSON.generate((new + current).uniq)
  end

  # set the :le_service_uuids attribute by merging with previously seen values
  #
  # == Parameters
  #   new_uuids ::
  #     new uuids
  def le_service_uuids=(new_uuids)
    current = JSON.parse(self.le_service_uuids || '[]')
    new = (new_uuids + current)

    new.map! do |uuid|
      if uuid =~ /\(/
        uuid
      else
        "Unknown (#{ uuid })"
      end
    end

    self[:le_service_uuids] = JSON.generate(new.uniq)
  end

  # set the :cassic_service_uuids attribute by merging with previously seen values
  #
  # Wrap some uuids in Unknown(uuid) as needed
  #
  # == Parameters
  #   new_uuids ::
  #     new uuids
  def classic_service_uuids=(new_uuids)
    current = JSON.parse(self.classic_service_uuids || '[]')
    new = (new_uuids + current)

    new.map! do |uuid|
      if uuid =~ /\(/
        uuid
      else
        "Unknown (#{ uuid })"
      end
    end

    self[:classic_service_uuids] = JSON.generate(new.uniq)
  end


  # set the :classic_rss attribute by merging with previously seen values
  #
  # limit to last 100 rssis
  #
  # == Parameters
  #   rssis ::
  #     new rssis
  def classic_rssi=(rssis)
    current = JSON.parse(self.classic_rssi || '[]')
    new = current + rssis

    until new.count <= 100
      new.shift
    end

    self[:classic_rssi] = JSON.generate(new)
  end

  # set the :le_rss attribute by merging with previously seen values
  #
  # limit to last 100 rssis
  #
  # == Parameters
  #   rssis ::
  #     new rssis
  def le_rssi=(rssis)
    current = JSON.parse(self.le_rssi || '[]')
    new = current + rssis

    until new.count <= 100
      new.shift
    end

    self[:le_rssi] = JSON.generate(new)
  end

  # set the :le_address_type carefully , may also result in the
  # le_random_address_type being nil'd out if the type value is "public"
  #
  # == Parameters
  #   type ::
  #     new type to set
  def le_address_type=(type)
    type = type.split(' ')[0]
    if type =~ /Public/
      self[:le_address_type] = type
      self[:le_random_address_type] = nil if le_address_type
    elsif type =~ /Random/
      self[:le_address_type] = type
    end
  end

  # set the :le_random_address_type unless the le_address_type is set
  #
  # == Parameters
  #   type ::
  #     new type to set
  def le_random_address_type=(type)
    unless le_address_type && le_address_type =~ /Public/
      self[:le_random_address_type] = type
    end
  end
end
