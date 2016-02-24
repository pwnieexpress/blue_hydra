# this is the bluetooth Device model stored in the DB
class BlueHydra::Device

  attr_accessor :filthy_attributes

  # this is a DataMapper model...
  include DataMapper::Resource

  # Attributes for the DB
  property :id,                            Serial

  property :name,                          String
  property :status,                        String
  property :address,                       String
  property :uap_lap,                       String

  property :vendor,                        Text
  property :appearance,                    String
  property :company,                       String
  property :company_type,                  String
  property :lmp_version,                   String
  property :manufacturer,                  String
  property :firmware,                      String

  property :classic_mode,                  Boolean
  property :classic_service_uuids,         Text
  property :classic_channels,              Text
  property :classic_major_class,           String
  property :classic_minor_class,           String
  property :classic_class,                 Text
  property :classic_rssi,                  Text
  property :classic_tx_power,              Text
  property :classic_features,              Text
  property :classic_features_bitmap,       Text

  property :le_mode,                       Boolean
  property :le_service_uuids,              Text
  property :le_address_type,               String
  property :le_random_address_type,        String
  property :le_flags,                      Text
  property :le_rssi,                       Text
  property :le_tx_power,                   Text
  property :le_features,                   Text
  property :le_features_bitmap,            Text

  property :created_at,                    DateTime
  property :updated_at,                    DateTime
  property :last_seen,                     Integer

  # regex to validate macs
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i

  # validate the address. the only validation currently
  validates_format_of :address, with: MAC_REGEX

  # before saving set the vendor info and the mode flags (le/classic)
  before :save, :set_vendor
  before :save, :set_uap_lap
  before :save, :set_mode_flags
  before :save, :prepare_the_filth

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

  def self.sync_all_to_pulse
    BlueHydra::Device.all.each do |dev|
      dev.sync_to_pulse(true)
    end
  end

  def self.sync_statuses_to_pulse
    BlueHydra::Device.all.each do |dev|
      dev.instance_variable_set(:@filthy_attributes, [:status])
      dev.sync_to_pulse(false)
    end
  end

  def self.mark_old_devices_offline
    # mark hosts as 'offline' if we haven't seen for a while
    BlueHydra::Device.all(classic_mode: true, status: "online").select{|x|
      x.last_seen < (Time.now.to_i - (15*60))
    }.each{|device|
      device.status = 'offline'
      device.save
    }
    BlueHydra::Device.all(le_mode: true, status: "online").select{|x|
      x.last_seen < (Time.now.to_i - (60*3))
    }.each{|device|
      device.status = 'offline'
      device.save
    }
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

    record = self.all(address: address).first || self.find_by_uap_lap(address) || self.new

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
      le_random_address_type
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
      classic_rssi le_service_uuids classic_service_uuids le_features_bitmap classic_features_bitmap
    }.map(&:to_sym).each do |attr|
      if result[attr]
        record.send("#{attr.to_s}=", result.delete(attr))
      end
    end

    if record.valid?
      record.save
      if self.all(uap_lap: record.uap_lap).count > 1
        BlueHydra.logger.warn("Duplicate UAP/LAP detected: #{record.uap_lap}.")
      end
    else
      BlueHydra.logger.warn("#{address} can not save.")
      record.errors.keys.each do |key|
        BlueHydra.logger.warn("#{key.to_s}: #{record.errors[key].inspect} (#{record[key]})")
      end
    end

    record
  end

  # look up the vendor for the address in the Louis gem
  # and set it
  def set_vendor(force=false)
    if self.le_address_type == "Random"
      self.vendor = "N/A - Random Address"
    else
      if self.vendor == nil || self.vendor == "Unknown" || force
        vendor = Louis.lookup(address)
        self.vendor = vendor["long_vendor"] ? vendor["long_vendor"] : vendor["short_vendor"]
      end
    end
  end


  # set the last 4 octets of the mac as the uap_lap values
  #
  # These values are from mac addresses for bt devices as follows
  #
  # |NAP    |UAP |LAP
  # DE : AD : BE : EF : CA : FE
  def set_uap_lap
    self[:uap_lap] = self.address.split(":")[2,4].join(":")
  end

  # lookup helper method for uap_lap
  def self.find_by_uap_lap(address)
    uap_lap = address.split(":")[2,4].join(":")
    self.all(uap_lap: uap_lap).first
  end

  def syncable_attributes
    [
      :name, :status, :vendor, :appearance, :company, :company_type, :lmp_version,
      :manufacturer, :le_features_bitmap, :firmware, :classic_mode,
      :classic_features_bitmap, :classic_major_class, :classic_minor_class,
      :le_mode, :le_address_type, :le_random_address_type, :le_tx_power,
      :last_seen, :classic_tx_power, :le_features, :classic_features,
      :le_service_uuids, :classic_service_uuids, :classic_channels,
      :classic_class, :classic_rssi, :le_flags, :le_rssi
    ]
  end


  def prepare_the_filth
    @filthy_attributes ||= []
    syncable_attributes.each do |attr|
      @filthy_attributes << attr if self.attribute_dirty?(attr)
    end
  end


  # sync record to pulse
  def sync_to_pulse(sync_all=false)
    send_data = {
      type:   "bluetooth",
      source: "blue-hydra",
      version: BlueHydra::VERSION,
      data: {}
    }

    # always include address
    send_data[:data][:address] = address

    @filthy_attributes ||= []

    syncable_attributes.each do |attr|
      # ignore nil value attributes
      if @filthy_attributes.include?(attr) || sync_all
        val = self.send(attr)
        unless [nil, "[]"].include?(val)
          send_data[:data][attr] = val
        end
      end
    end

    # create the json
    json = JSON.generate(send_data)

    # log raw results into device files for review in debugmode
    if BlueHydra.config[:log_level] == "debug"
      file_path = File.expand_path(
        "../../../devices/synced_#{address.gsub(':', '-')}_#{Time.now.to_i}.json", __FILE__
      )
      File.write(file_path, json)
    end

    return if BlueHydra.no_pulse
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

  def address=(new)
    current = self.address

    if current.nil? || current =~ /^00:00/
      self[:address] = new
      set_vendor(true)
    end
  end

  def le_features_bitmap=(arr)
    current = JSON.parse(self.le_features_bitmap||'{}')
    arr.each do |(page, bitmap)|
      current[page] = bitmap
    end
    self[:le_features_bitmap] = JSON.generate(current)
  end

  def classic_features_bitmap=(arr)
    current = JSON.parse(self.classic_features_bitmap||'{}')
    arr.each do |(page, bitmap)|
      current[page] = bitmap
    end
    self[:classic_features_bitmap] = JSON.generate(current)
  end
end
