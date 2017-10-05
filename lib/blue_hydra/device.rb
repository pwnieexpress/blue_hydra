#l this is the bluetooth Device model stored in the DB
class BlueHydra::Device < BlueHydra::DB::SQLModel
  TABLE_NAME = 'blue_hydra_devices'.freeze
  def table_name
    TABLE_NAME
  end
  # set up properties
  BlueHydra::DB.keys(TABLE_NAME).each do |key,type|
    sql_model_attr_accessor key
  end
  # validate the address. the only validation currently
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i.freeze
  VALIDATION_MAP= { :address => MAC_REGEX }.freeze
  def validation_map
    VALIDATION_MAP
  end
  # map because results come back as symbol key and i didnt wanna change everything right now also didnt wanna dynamically generate symbols vs keys
  NORMAL_ATTRS = {'address' => :address,
                  'name' => :name,
                  'manufacturer' => :manufacturer,
                  'short_name' => :short_name,
                  'lmp_version' => :lmp_version,
                  'firmware' => :firmware,
                  'classic_major_class' => :classic_major_class,
                  'classic_minor_class' => :classic_minor_class,
                  'le_tx_power' => :le_tx_power,
                  'classic_tx_power' => :classic_tx_power,
                  'company' => :company,
                  'company_type' => :company_type,
                  'appearance' => :appearance,
                  'le_address_type' => :le_address_type,
                  'le_random_address_type' => :le_random_address_type,
                  'le_company_uuid' => :le_company_uuid,
                  'le_company_data' => :le_company_data,
                  'le_proximity_uuid' => :le_proximity_uuid,
                  'le_major_num' => :le_major_num,
                  'le_minor_num' => :le_minor_num,
                  'classic_mode' => :classic_mode,
                  'le_mode' => :le_mode
                  }.freeze
  ARRAY_ATTRS = {'classic_features' => :classic_features,
                  'le_features' => :le_features,
                  'le_flags' => :le_flags,
                  'classic_channels' => :classic_channels,
                  'classic_class' => :classic_class,
                  'le_rssi' => :le_rssi,
                  'classic_rssi' => :classic_rssi,
                  'le_service_uuids' => :le_service_uuids,
                  'classic_service_uuids' => :classic_service_uuids,
                  'le_features_bitmap' => :le_features_bitmap,
                  'classic_features_bitmap' => :classic_features_bitmap
                  }.freeze

  SYNCABLE_ATTRS = [
                    :name, :vendor, :appearance, :company, :le_company_data, :company_type,
                    :lmp_version, :manufacturer, :le_features_bitmap, :firmware,
                    :classic_mode, :classic_features_bitmap, :classic_major_class,
                    :classic_minor_class, :le_mode, :le_address_type,
                    :le_random_address_type, :le_tx_power, :last_seen, :classic_tx_power,
                    :le_features, :classic_features, :le_service_uuids,
                    :classic_service_uuids, :classic_channels, :classic_class, :classic_rssi,
                    :le_flags, :le_rssi, :le_company_uuid
                   ].freeze

  def syncable_attributes
    SYNCABLE_ATTRS
  end

  SERIALIZED_ATTRS= [
                     :classic_channels,
                     :classic_class,
                     :classic_features,
                     :le_features,
                     :le_flags,
                     :le_service_uuids,
                     :classic_service_uuids,
                     :classic_rssi,
                     :le_rssi
                    ].freeze

  def self.is_serialized?(attr)
    SERIALIZED_ATTRS.include?(attr)
  end

  def initialize(id=nil)
     super(self)
     load_row(id) if id
     self
  end

  def self.create_new
    newobj = BlueHydra::Device.new
    newobj.id = newobj.create_new_row
    return newobj
  end

  def load_row(id=nil)
    id = self.id if id.nil?
    return nil if id.nil?
    sql_to_model_conversion(BlueHydra::DB.query("select * from #{TABLE_NAME} where id = #{id} limit 1;").first)
    return nil
    #self
  end

  def attributes
#TODO
  end

  def destroy!
#todo
  end

  def save
     return false unless self.valid?
     set_vendor
     set_uap_lap
     set_uuid
     prepare_the_filth
     self.set_updated_at
     self.set_created_at if self.new_row
     statement = "update #{TABLE_NAME} set #{self.model_to_sql_conversion} where id = #{self.id} limit 1;"
     BlueHydra::DB.query(statement)
     statement = nil
     BlueHydra::DB.query("commit;") if self.transaction_open
     self.new_row = false
     self.transaction_open = false if self.transaction_open
     self.sync_to_pulse
     return nil
     #self
  end


  def save_subset(rows)
    #update without entire row
  end

  def self.first
    model = BlueHydra::Device.new(false)
      model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{TABLE_NAME} order by id asc limit 1;").map{|r| r.to_h}.first)
      return model
  end

  def self.last
    model = BlueHydra::Device.new(false)
      model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{TABLE_NAME} order by id desc limit 1;").map{|r| r.to_h}.first)
      return model
  end

  def self.get(id)
    return nil unless BlueHydra::Device.id_exist?(id)
    self.new(id)
  end

  def self.id_exist?(id)
    row_ids = BlueHydra::DB.query("select id from #{TABLE_NAME} where id = #{id} limit 1;")
    return false if row_ids.nil? || row_ids.first.nil?
    return true
  end

  def self.all(query={})
    basequery = "select * from #{TABLE_NAME}"
    unless query.empty?
      statement = " WHERE "
      endstatement = ""
      if query.keys.include?(:order)
        endstatement << " order by "
        endstatement << "#{query.delete(:order)}"
      end
      if query.keys.include?(:limit)
        endstatement << " limit "
        endstatement << "#{query.delete(:limit)}"
      end
      query.each do |key, val|
        val = self.boolean_to_string(val) if BlueHydra::DB.keys(TABLE_NAME)[key] == :boolean
        statement << "#{key} = '#{val}'"
        statement << " AND " unless key == query.keys.last
      end
      basequery << statement
      basequery << endstatement unless endstatement.empty?
    end
    records = []
    row_hashes = BlueHydra::DB.query("#{basequery};").map{|r| r.to_h}
    #BlueHydra.logger.info("#{basequery};")
    row_hashes.each do |row|
      obj = BlueHydra::Device.new(false)
      obj.sql_to_model_conversion(row)
      records << obj
    end
    basequery = nil
    statement = nil
    endstatement = nil
    row_hashes = nil
    query = nil
    records
  end

  # mark hosts as 'offline' if we haven't seen for a while
  def self.mark_old_devices_offline(startup=false)
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
    end

#TODO fix
    # Kill old things with fire
   # BlueHydra::Device.all(:updated_at.lte => Time.at(Time.now.to_i - 604800*2)).each do |dev|
   #   dev.status = 'offline'
   #   dev.sync_to_pulse(true)
   #   BlueHydra.logger.debug("Destroying #{dev.address} #{dev.uuid}")
   #   dev.destroy
   # end

   # # classic mode devices have 15 min timeout
   # BlueHydra::Device.all(classic_mode: true, status: "online").select{|x|
   #   x.last_seen < (Time.now.to_i - (15*60))
   # }.each{|device|
   #   device.status = 'offline'
   #   device.save
   # }

   # # le mode devices have 3 min timeout
   # BlueHydra::Device.all(le_mode: true, status: "online").select{|x|
   #   x.last_seen < (Time.now.to_i - (60*3))
   # }.each{|device|
   #   device.status = 'offline'
   #   device.save
   # }
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

    NORMAL_ATTRS.each do |attr, sym_key|
      if result[sym_key]
        if result[sym_key].uniq.count > 1
          BlueHydra.logger.debug(
            "#{record.address} multiple values detected for #{attr}: #{result[sym_key].inspect}. Using first value..."
          )
        end
        if result[sym_key].uniq.first != record[attr]
          record.send("#{attr}=", result.delete(sym_key).uniq.first)
        end
      end
    end

    ARRAY_ATTRS.each do |attr, sym_key|
      if result[sym_key]
        if !(result[sym_key] == "[]" || result[sym_key] == [])
          if result[sym_key] != record[attr]
            record.send("#{attr}=", result.delete(sym_key))
          end
        end
      end
    end

    if record.valid?
      #todo save conditionally on changed using dirty attrs
      record.save
      if self.all(:uap_lap => record.uap_lap,:limit => 1).count > 1
        BlueHydra.logger.warn("Duplicate UAP/LAP detected: #{record.uap_lap}.")
      end
    else
      BlueHydra.logger.warn("#{record.address} can not save.")
      record.errors.keys.each do |key|
        BlueHydra.logger.warn("#{key.to_s}: #{record.errors[key].inspect} (#{record[key]})")
      end
    end

    record
  end

  # look up the vendor for the address in the Louis gem
  # and set it
  RANDOM_ADDRESS = "N/A - Random Address".freeze
  UNKNOWN = "Unknown".freeze
  RANDOM = "Random".freeze
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

  ADDRESS_DELIM = ":".freeze
  def set_uap_lap
    self[:uap_lap] = self.address.split(ADDRESS_DELIM)[2,4].join(ADDRESS_DELIM)
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
            if self.is_serialized?(attr)
              send_data[:data][attr] = val
            else
              send_data[:data][attr] = val
            end
          end
        end
      end

      # create the json
      json_msg = Oj.dump(send_data)
      # send the json
      self.dirty_attributes = []
      BlueHydra::Pulse.do_send(json_msg)
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
      self[:name] = new unless self[:name] == new
    end
  end

  # set the :classic_channels attribute by merging with previously seen values
  #
  # == Parameters
  #   channels ::
  #     new channels
  def classic_channels=(channels)
    new = channels.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = self.classic_channels || []
    new_to_set = (new + current).uniq
    self[:classic_channels] = new_to_set unless self[:classic_channels] == new_to_set
  end

  # set the :classic_class attribute by merging with previously seen values
  #
  # == Parameters
  #   new_classes ::
  #     new classes
  def classic_class=(new_classes)
    new = new_classes.flatten.uniq.reject{|x| x =~ /^0x/}
    current = self.classic_class || []
    new_to_set = (new + current).uniq
    self[:classic_class] = new_to_set unless self[:classic_class] == new_to_set
  end

  # set the :classic_features attribute by merging with previously seen values
  #
  # == Parameters
  #   new_features ::
  #     new features
  def classic_features=(new_features)
    new = new_features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = self.classic_features || []
    new_to_set = (new + current).uniq
    self[:classic_features] = new_to_set unless self[:classic_features] == new_to_set
  end

  # set the :le_features attribute by merging with previously seen values
  #
  # == Parameters
  #   new_features ::
  #     new features
  def le_features=(new_features)
    new = new_features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = self.le_features || []
    new_to_set = (new + current).uniq
    self[:le_features] = new_to_set unless self[:le_features] == new_to_set
  end

  # set the :le_flags attribute by merging with previously seen values
  #
  # == Parameters
  #   new_flags ::
  #     new flags
  def le_flags=(flags)
    new = flags.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
    current = self.le_flags || []
    new_to_set = (new + current).uniq
    self[:le_flags] = new_to_set unless self[:le_flags] == new_to_set
  end

  # set the :le_service_uuids attribute by merging with previously seen values
  #
  # == Parameters
  #   new_uuids ::
  #     new uuids
  def le_service_uuids=(new_uuids)
    current = self.le_service_uuids || []
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
    self[:le_service_uuids] = new.uniq unless self[:le_service_uuids] == new.uniq
  end

  # set the :cassic_service_uuids attribute by merging with previously seen values
  #
  # Wrap some uuids in Unknown(uuid) as needed
  #
  # == Parameters
  #   new_uuids ::
  #     new uuids
  def classic_service_uuids=(new_uuids)
    current = self.classic_service_uuids || []
    new = (new_uuids + current)
    new.map! do |uuid|
      if uuid =~ /\(/
        uuid
      else
        "Unknown (#{ uuid })"
      end
    end
    self[:classic_service_uuids] = new.uniq unless self[:classic_service_uuids] == new.uniq
  end


  # set the :classic_rss attribute by merging with previously seen values
  #
  # limit to last 100 rssis
  #
  # == Parameters
  #   rssis ::
  #     new rssis
  def classic_rssi=(rssis)
    current = self.classic_rssi || []
    new = current + rssis
    until new.count <= 100
      new.shift
    end
    self[:classic_rssi] = new unless self[:classic_rssi] == new
  end

  # set the :le_rss attribute by merging with previously seen values
  #
  # limit to last 100 rssis
  #
  # == Parameters
  #   rssis ::
  #     new rssis
  def le_rssi=(rssis)
    current = self.le_rssi || []
    new = current + rssis
    until new.count <= 100
      new.shift
    end
    self[:le_rssi] = new unless self[:le_rssi] == new
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
  end

  # set the addres field but only conditionally set vendor based on some whether
  # or not we have an appropriate address to use for vendor lookup. Don't do
  # vendor lookups if address starts with 00:00
  def address=(new)
    if new
      current = self.address
      unless new == self[:address]
        self[:address] = new
        if current =~ /^00:00/ || new !~ /^00:00/
          set_vendor(true)
        end
      end
    end
  end

  def le_features_bitmap=(arr)
    current = self.le_features_bitmap||{}
    arr.each do |(page, bitmap)|
      current[page] = bitmap
    end
    self[:le_features_bitmap] = current unless self[:le_features_bitmap] == current
  end

  def classic_features_bitmap=(arr)
    current = self.classic_features_bitmap||{}
    arr.each do |(page, bitmap)|
      current[page] = bitmap
    end
    self[:classic_features_bitmap] = current unless self[:classic_features_bitmap] == current
  end

  # 1 week in seconds == 7 * 24 * 60 * 60 == 604800
  def self.sync_all_to_pulse(since=Time.at(Time.now.to_i - 604800))
    BlueHydra::Device.all.each do |dev|
      dev.sync_to_pulse(true)
    end
    return nil
  end

end
