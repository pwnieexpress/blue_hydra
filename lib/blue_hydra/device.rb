# this is the bluetooth Device model stored in the DB
class BlueHydra::Device

  attr_accessor :filthy_attributes

  # this is a DataMapper model...
  include DataMapper::Resource

  # Attributes for the DB
  property :id,                            Serial

  # TODO: migrate this column to be called sync_id
  property :uuid,                          String

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

  # classic mode specific attributes
  property :classic_mode,                  Boolean, default: false
  property :classic_service_uuids,         Text
  property :classic_channels,              Text
  property :classic_major_class,           String
  property :classic_minor_class,           String
  property :classic_class,                 Text
  property :classic_rssi,                  Text
  property :classic_tx_power,              Text
  property :classic_features,              Text
  property :classic_features_bitmap,       Text

  # low energy mode specific attributes
  property :le_mode,                       Boolean, default: false
  property :le_service_uuids,              Text
  property :le_address_type,               String
  property :le_random_address_type,        String
  property :le_company_data,               String
  property :le_company_uuid,               String
  property :le_proximity_uuid,             String
  property :le_major_num,                  String
  property :le_minor_num,                  String
  property :le_flags,                      Text
  property :le_rssi,                       Text
  property :le_tx_power,                   Text
  property :le_features,                   Text
  property :le_features_bitmap,            Text
  property :ibeacon_range,                 String

  property :created_at,                    DateTime
  property :updated_at,                    DateTime
  property :last_seen,                     Integer
  property :needs_sync,                    Boolean
  property :filthy_attrs,                  Text

  # regex to validate macs
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i

  # validate the address. the only validation currently
  validates_format_of :address, with: MAC_REGEX

  # before saving set the vendor info and the mode flags (le/classic)
  before :save, :set_vendor
  before :save, :set_uap_lap
  before :save, :set_uuid
  before :save, :prepare_the_filth
  after :save, :delete_unnecessary_assets

  # 1 week in seconds == 7 * 24 * 60 * 60 == 604800
  def self.sync_all_to_pulse(since=Time.at(Time.now.to_i - 604800))
    if BlueHydra::PULSE_TRACKER.allowed_to_ship_data?
      BlueHydra.logger.info("Sync all starting")
      BlueHydra::Device.all(:updated_at.gte => since).each do |dev|
        dev.do_sync_to_pulse(true)
      end
      BlueHydra::PULSE_TRACKER.update_synced_at
      BlueHydra.logger.info("Sync all complete")
    else
      BlueHydra.logger.warn("Sync all throttled, dont spam the cloud")
    end
  end

  def self.sync_dirty_hosts
    BlueHydra.logger.debug("Syncing dirty hosts...")
    (d = BlueHydra::Device.all(needs_sync: true)).each do |dev|
      BlueHydra.logger.debug("#{dev.id} syncd")
      dev.do_sync_to_pulse
      BlueHydra.logger.debug("#{dev.id} flag off")
      dev.save
    end
    BlueHydra.logger.info("#{d.count} host sync complete")
  end

  # mark hosts as 'offline' if we haven't seen for a while
  def self.mark_old_devices_offline(startup=false)
    if startup
      # efficiently kill old things with fire
      if DataMapper.repository.adapter.select("select uuid from blue_hydra_devices where updated_at between \"1970-01-01\" AND \"#{Time.at(Time.now.to_i-1209600).to_s.split(" ")[0]}\" limit 5000;").count == 5000
        DataMapper.repository.adapter.select("delete from blue_hydra_devices where updated_at between \"1970-01-01\" AND \"#{Time.at(Time.now.to_i-1209600).to_s.split(" ")[0]}\" ;")
        BlueHydra::Pulse.hard_reset
      end

      # unknown mode devices have 15 min timeout (SHOULD NOT EXIST, BUT WILL CLEAN
      # OLD DBS)
      BlueHydra::Device.all(
        le_mode:       false,
        classic_mode:  false,
        status:        "online"
      ).select{|x|
        x.last_seen < (Time.now.to_i - (15*60))
      }.each{|device|
        device.status = 'offline'
        device.save
      }
    end

    # Kill old things with fire
    BlueHydra::Device.all(:updated_at.lte => Time.at(Time.now.to_i - 604800*2)).each do |dev|
      dev.status = 'offline'
      dev.do_sync_to_pulse(true)
      BlueHydra.logger.debug("Destroying #{dev.address} #{dev.uuid}")
      dev.destroy
    end

    # classic mode devices have 15 min timeout
    BlueHydra::Device.all(classic_mode: true, status: "online").select{|x|
      x.last_seen < (Time.now.to_i - (15*60))
    }.each{|device|
      device.status = 'offline'
      device.save
    }

    # le mode devices have 3 min timeout
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

    result = result.dup

    address = result[:address].first

    lpu  = result[:le_proximity_uuid].first if result[:le_proximity_uuid]
    lmn  = result[:le_major_num].first      if result[:le_major_num]
    lmn2 = result[:le_minor_num].first      if result[:le_minor_num]

    c = result[:company].first              if result[:company]
    d = result[:le_company_data].first      if result[:le_company_data]

    record = self.all(address: address).first ||
             self.find_by_uap_lap(address) ||
             (lpu && lmn && lmn2 && self.all(
               le_proximity_uuid: lpu,
               le_major_num: lmn,
               le_minor_num: lmn2
             ).first) ||
             (c && d && c =~ /Gimbal/i && self.all(
               le_company_data: d
             ).first) ||
             self.new

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
      company appearance le_address_type
      le_random_address_type le_company_uuid le_company_data le_proximity_uuid
      le_major_num le_minor_num classic_mode le_mode
    }.map(&:to_sym).each do |attr|
      if result[attr]
        # we should only get a single value for these so we need to warn if
        # we are getting multiple values for these keys.. it should NOT be...
        if result[attr].uniq.count > 1
          BlueHydra.logger.debug(
            "#{address} multiple values detected for #{attr}: #{result[attr].inspect}. Using first value..."
          )
        end
        record.send("#{attr.to_s}=", result.delete(attr).uniq.sort.first)
      end
    end

# update flappy company_type
    if result[:company_type]
      data = result.delete(:company_type).uniq.sort.first
      if data =~ /Unknown/
        data = "Unknown"
        record.send("#{:company_type}=", data)
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
      BlueHydra.logger.warn("#{address} save failed.")
    end

    record
  end

  # look up the vendor for the address in the Louis gem
  # and set it
  def delete_unnecessary_assets
    if self.vendor == "N/A - Random Address"
      self.destroy!
    end
  end

  def set_vendor(force=false)
    if self.le_address_type == "Random"
      self.vendor = "N/A - Random Address"
    else
      if self.vendor == nil || self.vendor == "Unknown" || force
        self.vendor = "Not set"
      end
    end
  end

  # set a sync id as a UUID
  def set_uuid
    unless self.uuid
      new_uuid = SecureRandom.uuid

      until BlueHydra::Device.all(uuid: new_uuid).count == 0
        new_uuid = SecureRandom.uuid
      end

      self.uuid = new_uuid
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
      :name, :vendor, :appearance, :company, :le_company_data, :company_type,
      :lmp_version, :manufacturer, :le_features_bitmap, :firmware,
      :classic_mode, :classic_features_bitmap, :classic_major_class,
      :classic_minor_class, :le_mode, :le_address_type,
      :le_random_address_type, :le_tx_power, :last_seen, :classic_tx_power,
      :le_features, :classic_features, :le_service_uuids,
      :classic_service_uuids, :classic_channels, :classic_class, :classic_rssi,
      :le_flags, :le_rssi, :le_company_uuid
    ]
  end

  def is_serialized?(attr)
    [
      :classic_channels,
      :classic_class,
      :classic_features,
      :le_features,
      :le_flags,
      :le_service_uuids,
      :classic_service_uuids,
      :classic_rssi,
      :le_rssi
    ].include?(attr)
  end

  # This is a helper method to track what attributes change because all
  # attributes lose their 'dirty' status after save and the sync method is an
  # after save so we need to keep a record of what changed to only sync relevant
  def prepare_the_filth
    fa ||= []
    syncable_attributes.each do |attr|
      fa << attr if self.attribute_dirty?(attr)
    end
    self.filthy_attrs = JSON.generate(fa)
    if !fa.empty?
      if BlueHydra.pulse || BlueHydra.pulse_debug
        self.needs_sync = true
      end
    end
  end

  # sync record to pulse
  def do_sync_to_pulse(sync_all=false)
    if BlueHydra.pulse || BlueHydra.pulse_debug
      send_data = {
        type:   "bluetooth",
        source: "blue-hydra",
        version: BlueHydra::VERSION,
        data: {}
      }

      # always include uuid, address, status
      send_data[:data][:sync_id]    = self.uuid
      send_data[:data][:status]     = self.status
      send_data[:data][:sync_version] = BlueHydra::SYNC_VERSION

      if self.le_proximity_uuid
        send_data[:data][:le_proximity_uuid] = self.le_proximity_uuid
      end

      if self.le_major_num
        send_data[:data][:le_major_num] = self.le_major_num
      end

      if self.le_minor_num
        send_data[:data][:le_minor_num] = self.le_minor_num
      end

      # always include both of these if they are both set, otherwise they will
      # be set as part of syncable_attributes below
      if self.le_company_data && self.company
        send_data[:data][:le_company_data] = self.le_company_data
        send_data[:data][:company] = self.company
      end

      # TODO once pulse is using uuid to lookup records we can move
      # address into the syncable_attributes list and only include it if
      # changes, unless of course we want to handle the case where the db gets
      # reset and we have to resync hosts based on address alone or something
      # but, like, that'll never happen right?
      #
      # XXX for cases like Gimbal the only thing that prevents us from sending 60
      # address updates a minute is the fact that address is *not* in syncable attributes
      # and it only gets sent when something else changes (like rssi).
      # This was originally unintentional but it's really saving out bacon, don't change this for now
      send_data[:data][:address] = self.address

      attrs_to_ship ||= []
      attrs_to_ship = JSON.parse(self.filthy_attrs) if self.filthy_attrs

      syncable_attributes.each do |attr|
        # ignore nil value attributes
        if attrs_to_ship.include?(attr) || sync_all
          val = self.send(attr)
          unless [nil, "[]"].include?(val)
            if is_serialized?(attr)
              send_data[:data][attr] = JSON.parse(val)
            else
              send_data[:data][attr] = val
            end
          end
        end
      end

      # create the json
      json_msg = JSON.generate(send_data)
	  # reset pulse db and then send the json
	  BlueHydra::Pulse.hard_reset
      BlueHydra::Pulse.do_send(json_msg)

      #CLEANUP AFTER SYNC
    end
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

    #first we fix our old data if needed
    current_fixed = current.map do |x|
      if x.split(':')[1]
        #example x "(UUID 0xfe9f): 0000000000000000000000000000000000000000"
        # this split/scan handles removing the service data we used to capture and normalizing it to just show uuid
        x.split(':')[0].scan(/\(([^)]+)\)/).flatten[0].split('UUID ')[1]
      else
        x
      end
    end

    new = (new_uuids + current_fixed)

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
      self[:le_random_address_type] = nil if self.le_address_type
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

  # set the addres field but only conditionally set vendor based on some whether
  # or not we have an appropriate address to use for vendor lookup. Don't do
  # vendor lookups if address starts with 00:00
  def address=(new)
    if new
      current = self.address

      self[:address] = new

      if current =~ /^00:00/ || new !~ /^00:00/
        set_vendor(true)
      end
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
