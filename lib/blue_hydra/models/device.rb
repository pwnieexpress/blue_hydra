#l this is the bluetooth Device model stored in the DB
class BlueHydra::Device < BlueHydra::SQLModel

  #############################
  # Model setup
  #############################
  BlueHydra::DB.subscribe_model(self)
  TABLE_NAME = 'blue_hydra_devices'.freeze
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i.freeze
  EXISTS = /^.+$/.freeze
  def table_name
    TABLE_NAME
  end

  # ORDER OF THESE ATTRIBTUES MATTERS
  SCHEMA =  { id:                       { type: :integer,   sqldef: ID                                           },
              uuid:                     { type: :string,    sqldef: VARCHAR50  },#sync:true                      },
              name:                     { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              status:                   { type: :string,    sqldef: VARCHAR50  },#sync:true                      },
              address:                  { type: :string,    sqldef: VARCHAR50,               validate: MAC_REGEX },
              uap_lap:                  { type: :string,    sqldef: VARCHAR50                                    },
              vendor:                   { type: :string,    sqldef: TEXT,        sync: true                      },
              appearance:               { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              company:                  { type: :string,    sqldef: VARCHAR255,  sync: true                      },
              company_type:             { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              lmp_version:              { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              manufacturer:             { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              firmware:                 { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              classic_mode:             { type: :boolean,   sqldef: BOOLEANF,    sync: true                      },
              classic_service_uuids:    { type: :json,      sqldef: TEXT,        sync: true                      },
              classic_channels:         { type: :json,      sqldef: TEXT,        sync: true                      },
              classic_major_class:      { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              classic_minor_class:      { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              classic_class:            { type: :json,      sqldef: TEXT,        sync: true                      },
              classic_rssi:             { type: :json,      sqldef: TEXT,        sync: true                      },
              classic_tx_power:         { type: :string,    sqldef: TEXT,        sync: true                      },
              classic_features:         { type: :json,      sqldef: TEXT,        sync: true                      },
              classic_features_bitmap:  { type: :json,      sqldef: TEXT,        sync: true                      },
              le_mode:                  { type: :boolean,   sqldef: BOOLEANF,    sync: true                      },
              le_service_uuids:         { type: :json,      sqldef: TEXT,        sync: true                      },
              le_address_type:          { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              le_random_address_type:   { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              le_company_data:          { type: :string,    sqldef: VARCHAR255,  sync: true                      },
              le_company_uuid:          { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              le_proximity_uuid:        { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              le_major_num:             { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              le_minor_num:             { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              le_flags:                 { type: :json,      sqldef: TEXT,        sync: true                      },
              le_rssi:                  { type: :json,      sqldef: TEXT,        sync: true                      },
              le_tx_power:              { type: :string,    sqldef: TEXT,        sync: true                      },
              le_features:              { type: :json,      sqldef: TEXT,        sync: true                      },
              le_features_bitmap:       { type: :json,      sqldef: TEXT,        sync: true                      },
              ibeacon_range:            { type: :string,    sqldef: VARCHAR50,   sync: true                      },
              created_at:               { type: :datetime,  sqldef: TIMESTAMP                                    },
              updated_at:               { type: :datetime,  sqldef: TIMESTAMP                                    },
              last_seen:                { type: :integer,   sqldef: INTEGER,     sync: true                      }
           }.freeze

  def self.schema
    SCHEMA
  end

  SCHEMA.each do |property,metadata|
    sql_model_attr_accessor property
  end
  attr_accessor :filthy_attributes

  SYNCABLE_ATTRIBUTES = SCHEMA.select{|p,h| h.keys.include?(:sync)}.keys
  SERIALIZED_ATTRIBUTES = SCHEMA.select{|p,h| h[:type] == :json}.keys
  INTERNAL_ATTRIBUTES = [:id]
  NORMAL_ATTRIBUTES = ((SCHEMA.keys - SERIALIZED_ATTRIBUTES) - INTERNAL_ATTRIBUTES)
  valid = {}
  SCHEMA.select{|p,h| h.keys.include?(:validate)}.each{|p,h| valid[p] = h[:validate]}
  VALIDATION_MAP = valid

  def validation_map
    VALIDATION_MAP
  end

  def syncable_attributes
    SYNCABLE_ATTRIBUTES
  end

  def is_serialized?(attr)
    SERIALIZED_ATTRIBUTES.include?(attr)
  end

  def initialize(id=nil)
     setup
     load_row(id) if id
     self
  end

  def save
     set_vendor
     set_uap_lap
     set_uuid
     prepare_the_filth
     set_updated_at
     set_created_at if self.new_row
     super
     sync_to_pulse
  end
  #############################
  # END boilerplate model setup
  #############################

  # mark hosts as 'offline' if we haven't seen for a while
  def self.mark_old_devices_offline(startup=false)
    GC.start(immedaiate_sweep:true,full_mark:true)
    if startup
      # efficiently kill old things with fire
      if BlueHydra::DB.query("select uuid from blue_hydra_devices where updated_at between \"1970-01-01\" AND \"#{Time.at(Time.now.to_i-1209600).to_s.split(" ")[0]}\" limit 5000;").count == 5000
        BlueHydra::DB.query("delete from blue_hydra_devices where updated_at between \"1970-01-01\" AND \"#{Time.at(Time.now.to_i-1209600).to_s.split(" ")[0]}\" ;")
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
      GC.start(immedaiate_sweep:true,full_mark:true)
      # Kill old things with fire
      BlueHydra::Device.all(status:'online').each do |dev|
        next if dev.updated_at.nil? || dev.updated_at.empty?
        if DateTime.parse(dev.updated_at) <= DateTime.parse(Time.at(Time.now.to_i - 604800*2).to_s)
          dev.status = 'offline'
          dev.save
          dev.sync_to_pulse(true)
          BlueHydra.logger.debug("Destroying #{dev.address} #{dev.uuid}")
          dev.destroy!
        end
      end
      GC.start(immedaiate_sweep:true,full_mark:true)
    end
    # classic mode devices have 15 min timeout
    BlueHydra::Device.all(classic_mode: true, status: "online").select{|x|
      x.last_seen < (Time.now.to_i - (15*60))
    }.each{|device|
      device.status = 'offline'
      device.save
    }
    GC.start(immedaiate_sweep:true,full_mark:true)
    # le mode devices have 3 min timeout
    BlueHydra::Device.all(le_mode: true, status: "online").select{|x|
      x.last_seen < (Time.now.to_i - (60*3))
    }.each{|device|
      device.status = 'offline'
      device.save
    }
    GC.start(immedaiate_sweep:true,full_mark:true)
  end

  # this class method is take a result Hash and convert it into a new or update
  # an existing record
  #
  # == Parameters :
  #   result ::
  #     Hash of results from parser
  def self.update_or_create_from_result(result)
    #BlueHydra.logger.info("----------------------------------------------begin result")
    result = result.dup
    address = result[:address].first
    lpu  = result[:le_proximity_uuid].first if result[:le_proximity_uuid]
    lmn  = result[:le_major_num].first      if result[:le_major_num]
    lmn2 = result[:le_minor_num].first      if result[:le_minor_num]
    c = result[:company].first              if result[:company]
    d = result[:le_company_data].first      if result[:le_company_data]
    record = self.all(:address => address,:limit => 1).first ||
             self.find_by_uap_lap(address) ||
             (lpu && lmn && lmn2 && self.all(
              :le_proximity_uuid => lpu,
              :le_major_num => lmn,
              :le_minor_num => lmn2,
              :limit => 1
             ).first) ||
             (c && d && c =~ /Gimbal/i && self.all(
               :le_company_data => d,
               :limit => 1
             ).first)
    if record.nil?
        record = BlueHydra::Device.create_new
        BlueHydra.logger.info("-------no match new record")
    end
    record.status = 'online'
    # set last_seen or default value if missing
    if result[:last_seen] &&
      result[:last_seen].class == Array &&
      !result[:last_seen].empty?
      record.last_seen = result[:last_seen].sort.last # latest value
    else
      record.last_seen = Time.now.to_i
    end

    NORMAL_ATTRIBUTES.each do |sym_key|
      if result[sym_key]
        if result[sym_key].uniq.count > 1
          BlueHydra.logger.debug(
            "#{record.address} multiple values detected for #{sym_key}: #{result[sym_key].inspect}. Using first value..."
          )
        end
        record.send("#{sym_key}=", result.delete(sym_key).uniq.first)
      end
    end

    SERIALIZED_ATTRIBUTES.each do |sym_key|
      if result[sym_key]
        record.send("#{sym_key}=", result.delete(sym_key))
      end
    end

    if record.valid?
      #todo save conditionally on changed using dirty attrs
      record.save
      if self.all(:uap_lap => record.uap_lap,:limit => 1).count > 1
        BlueHydra.logger.warn("Duplicate UAP/LAP detected: #{record.uap_lap}.")
      end
    else
      require 'pry'
      binding.pry
    end

    record
  end

  # look up the vendor for the address in the Louis gem
  # and set it
  RANDOM_ADDRESS = "N/A - Random Address"
  UNKNOWN = "Unknown"
  RANDOM = "Random"
  def set_vendor(force=false)
    if self.le_address_type == RANDOM
      self.vendor = RANDOM_ADDRESS unless self.vendor == RANDOM_ADDRESS
    else
      if self.vendor == nil || self.vendor == UNKNOWN || force
        vendor = Louis.lookup(self.address)
        new_v = vendor["long_vendor"] ? vendor["long_vendor"] : vendor["short_vendor"]
        self.vendor = new_v unless self.vendor == new_v
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

      self.uuid = new_uuid unless uuid == new_uuid
    end
  end

  # set the last 4 octets of the mac as the uap_lap values
  #
  # These values are from mac addresses for bt devices as follows
  #
  # |NAP    |UAP |LAP
  # DE : AD : BE : EF : CA : FE

  ADDRESS_DELIM = ":"
  def set_uap_lap
    newd = self.address.split(ADDRESS_DELIM)[2,4].join(ADDRESS_DELIM)
    self[:uap_lap] = newd unless self[:uap_lap] == newd
  end

  # lookup helper method for uap_lap
  def self.find_by_uap_lap(address)
    uap_lap = address.split(ADDRESS_DELIM)[2,4].join(ADDRESS_DELIM)
    self.all(:uap_lap => uap_lap,:limit => 1).first
  end

  # This is a helper method to track what attributes change because all
  # attributes lose their 'dirty' status after save and the sync method is an
  # after save so we need to keep a record of what changed to only sync relevant
  def prepare_the_filth
    @filthy_attributes ||= []
    syncable_attributes.each do |attr|
      @filthy_attributes << attr if self.attribute_dirty?(attr)
    end
  end

  # sync record to pulse
  PULSE_TYPE = "bluetooth".freeze
  PULSE_SOURCE = "blue-hydra".freeze
  def sync_to_pulse(sync_all=false)
    if BlueHydra.pulse || BlueHydra.pulse_debug

      send_data = {
        type:   PULSE_TYPE,
        source: PULSE_SOURCE,
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

      @filthy_attributes ||= []

      syncable_attributes.each do |attr|
        # ignore nil value attributes
        if @filthy_attributes.include?(attr) || sync_all
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
      # send the json
      BlueHydra::Pulse.do_send(json_msg)
      self.dirty_attributes = []
    end
      return nil
  end

  # set the :name attribute from the :short_name key only if name is not already
  # set
  #
  # == Parameters
  #   new ::
  #     new short name value
  def short_name=(new)
    unless ["",nil].include?(new) || self.name
      self[:name] = new unless self[:name] == new
    end
    return nil
  end

  # set the :classic_channels attribute by merging with previously seen values
  #
  # == Parameters
  #   channels ::
  #     new channels
  def classic_channels=(channels)
    newd = channels.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.classic_channels || '[]')
    new_to_set = (newd + current).uniq
    self[:classic_channels] = JSON.generate(new_to_set)
    return nil
  end

  # set the :classic_class attribute by merging with previously seen values
  #
  # == Parameters
  #   new_classes ::
  #     new classes
  def classic_class=(new_classes)
    newd = new_classes.flatten.uniq.reject{|x| x =~ /^0x/}
    current = JSON.parse(self.classic_class || '[]')
    new_to_set = (newd + current).uniq
    self[:classic_class] = JSON.generate(new_to_set)
    return nil
  end

  # set the :classic_features attribute by merging with previously seen values
  #
  # == Parameters
  #   new_features ::
  #     new features
  def classic_features=(new_features)
    newd = new_features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.classic_features || '[]')
    new_to_set = (newd + current).uniq
    self[:classic_features] = JSON.generate(new_to_set)
    return nil
  end

  # set the :le_features attribute by merging with previously seen values
  #
  # == Parameters
  #   new_features ::
  #     new features
  def le_features=(new_features)
    newd = new_features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.le_features || '[]')
    new_to_set = (newd + current).uniq
    self[:le_features] = JSON.generate(new_to_set)
    return nil
  end

  # set the :le_flags attribute by merging with previously seen values
  #
  # == Parameters
  #   new_flags ::
  #     new flags
  def le_flags=(flags)
    newd = flags.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = JSON.parse(self.le_flags ||'[]')
    new_to_set = (newd + current).uniq
    self[:le_flags] = JSON.generate(new_to_set)
    return nil
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
    newd = (new_uuids + current_fixed)
    newd.map! do |uuid|
      if uuid =~ /\(/
        uuid
      else
        "Unknown (#{ uuid })"
      end
    end
    self[:le_service_uuids] = JSON.generate(newd.uniq)
    return nil
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
    newd = (new_uuids + current)
    newd.map! do |uuid|
      if uuid =~ /\(/
        uuid
      else
        "Unknown (#{ uuid })"
      end
    end
    self[:classic_service_uuids] = JSON.generate(newd.uniq)
    return nil
  end


  # set the :classic_rss attribute by merging with previously seen values
  #
  # limit to last 100 rssis
  #
  # == Parameters
  #   rssis ::
  #     new rssis
  def classic_rssi=(rssis)
    current = JSON.parse(self.classic_rssi ||'[]')
    newd = current + rssis
    until newd.count <= 100
      newd.shift
    end
    self[:classic_rssi] = JSON.generate(newd)
    return nil
  end

  # set the :le_rss attribute by merging with previously seen values
  #
  # limit to last 100 rssis
  #
  # == Parameters
  #   rssis ::
  #     new rssis
  def le_rssi=(rssis)
    current = JSON.parse(self.le_rssi ||'[]')
    newd = current + rssis
    until newd.count <= 100
      newd.shift
    end
    self[:le_rssi] = JSON.generate(newd)
    return nil
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
      self[:le_address_type] = type unless self[:le_address_type] == type
      self[:le_random_address_type] = nil if le_address_type && !self[:le_random_address_type].nil?
    elsif type =~ /Random/
      self[:le_address_type] = type unless self[:le_address_type] == type
    end
    return nil
  end

  # set the :le_random_address_type unless the le_address_type is set
  #
  # == Parameters
  #   type ::
  #     new type to set
  def le_random_address_type=(type)
    unless le_address_type && le_address_type =~ /Public/
      self[:le_random_address_type] = type unless self[:le_random_address_type] == type
    end
    return nil
  end

  # set the addres field but only conditionally set vendor based on some whether
  # or not we have an appropriate address to use for vendor lookup. Don't do
  # vendor lookups if address starts with 00:00
  def address=(newd)
    if newd
      current = self.address
      unless newd == self[:address]
        self[:address] = newd
        if current =~ /^00:00/ || newd !~ /^00:00/
          set_vendor(true)
        end
      end
    end
    return nil
  end

  def le_features_bitmap=(arr)
    current = JSON.parse(self.le_features_bitmap||'{}')
    arr.each do |(page, bitmap)|
      current[page] = bitmap
    end
    self[:le_features_bitmap] = JSON.generate(current)
    return nil
  end

  def classic_features_bitmap=(arr)
    current = JSON.parse(self.classic_features_bitmap||'{}')
    arr.each do |(page, bitmap)|
      current[page] = bitmap
    end
    self[:classic_features_bitmap] = JSON.generate(current)
    return nil
  end

  # 1 week in seconds == 7 * 24 * 60 * 60 == 604800
  def self.sync_all_to_pulse(since=Time.at(Time.now.to_i - 604800))
    BlueHydra::Device.all.each do |dev|
      dev.sync_to_pulse(true)
    end
    GC.start
    return nil
  end

end
