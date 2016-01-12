class BlueHydra::Device
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i

  include DataMapper::Resource

  property :id,                           Serial

  property :name,                         String
  property :address,                      String
  property :oui,                          Text

  # TODO confirm these
  property :peer_address,                 String
  property :peer_address_type,            String
  property :peer_address_oui,             String

  property :classic_role,                 String
  property :classic_lmp_version,          String
  property :classic_manufacturer,         String
  property :classic_features,             Text
  property :classic_firmware,             String
  property :classic_channels,             String
  property :classic_major_class,          String
  property :classic_minor_class,          String
  property :classic_16_bit_service_uuids, Text
  property :classic_class,                Text

  property :le_16_bit_service_uuids,      Text

  property :created_at,                   DateTime
  property :updated_at,                   DateTime
  property :last_seen,                    Integer

  property :le_mode, Boolean
  property :classic_mode, Boolean

  validates_format_of :address, with: MAC_REGEX

  before :save, :set_mode_flags

  def self.update_or_create_from_result(result)

    result = result.dup

    address = result[:address].first

    record = self.all(address: address).first || self.new

    attrs = %w{
      address
      name
      oui
      peer_address
      peer_address_type
      peer_address_oui
      classic_role
      classic_manufacturer
      classic_lmp_version
      classic_firmware
      classic_major_class
      classic_minor_class
    }.map(&:to_sym)

    if result[:classic_features]
      record.classic_features = result[:classic_features]
    end

    if result[:classic_channels]
      record.classic_channels = result[:classic_channels]
    end

    if result[:le_16_bit_service_uuids]
      record.le_16_bit_service_uuids = result[:le_16_bit_service_uuids]
    end

    if result[:classic_16_bit_service_uuids]
      record.classic_16_bit_service_uuids = result[:classic_16_bit_service_uuids]
    end

    if result[:classic_class]
      record.classic_class = result[:classic_class]
    end

    if result[:last_seen] &&
       result[:last_seen].class == Array &&
       !result[:last_seen].empty?
      record.last_seen = result[:last_seen].sort.last
    else
      record.last_seen = Time.now.to_i
    end

    attrs.each do |attr|
      if result[attr]

        if result[attr].uniq.count > 1
          BlueHydra.logger.debug(
            "#{address} multiple values detected for #{attr}: #{result[attr].inspect}. Using first value..."
          )
        end

        new_val     = result[attr].first
        current_val = record[attr]

        unless new_val == current_val
          record[attr] = result.delete(attr).uniq.first
        end

        if record.valid?
          record.save
        else
          BlueHydra.logger.warn(
            "#{address} can not save. attrs: #{ record.attributes.inspect }"
          )
        end
      end
    end
    record
  end

  def set_mode_flags
    classic = false
    [
      :classic_role,
      :classic_lmp_version,
      :classic_manufacturer,
      :classic_features,
      :classic_firmware,
      :classic_channels,
      :classic_major_class,
      :classic_minor_class,
      :classic_16_bit_service_uuids,
      :classic_class
    ].each do |classic_attr|
      if self[classic_attr]
        classic ||= true
      end
    end
    self[:classic_mode] = classic


    le = false
    [ :le_16_bit_service_uuids ].each do |le_attr|
      if self[le_attr]
        le ||= true
      end
    end
    self[:le_mode] = le
  end

  # NOTE: returns raw json...
  def classic_channels
    self[:classic_channels] || '[]'
  end

  def classic_channels=(channels)
     new = channels.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
     current = JSON.parse(self.classic_class)
     self[:classic_channels] = JSON.generate((new + current).uniq)
  end

  # NOTE: returns raw json...
  def classic_class
    self[:classic_class] || '[]'
  end

  def classic_class=(new_classes)
     new = new_classes.flatten.uniq.reject{|x| x =~ /^0x/}
     current = JSON.parse(self.classic_class)
     self[:classic_class] = JSON.generate((new + current).uniq)
  end

  # NOTE: returns raw json...
  def classic_features
    self[:classic_features] || '[]'
  end

  def classic_features=(features)
     new = features.map{|x| x.split(", ").reject{|x| x =~ /^0x/}}.flatten.sort.uniq
     current = JSON.parse(self.classic_features)
     self[:classic_features] = JSON.generate((new + current).uniq)
  end

  # NOTE: returns raw json...
  def classic_16_bit_service_uuids
    self[:classic_16_bit_service_uuids] || '[]'
  end

  def classic_16_bit_service_uuids=(new_uuids)
     new = new_uuids.reject{|x| x =~ /^0x/}
     new.map!{|x| x.scan(/(.*) \(0x/).flatten.first}
     current = JSON.parse(self.classic_16_bit_service_uuids)
     self[:classic_16_bit_service_uuids] = JSON.generate((new + current).uniq)
  end

  # NOTE: returns raw json...
  def le_16_bit_service_uuids
    self[:le_16_bit_service_uuids] || '[]'
  end

  def le_16_bit_service_uuids=(new_uuids)
     new = new_uuids.reject{|x| x =~ /^0x/}
     new.map!{|x| x.scan(/(.*) \(0x/).flatten.first}
     current = JSON.parse(self.le_16_bit_service_uuids)
     self[:le_16_bit_service_uuids] = JSON.generate((new + current).uniq)
  end
end
