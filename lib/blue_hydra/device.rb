class BlueHydra::Device
  MAC_REGEX    = /^((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})$/i

  include DataMapper::Resource

  property :id,                 Serial
  property :address,            String
  property :oui,                String
  property :peer_address,       String
  property :peer_address_type,  String
  property :peer_address_oui,   String
  property :role,               String
  property :lmp_version,        String
  property :manufacturer,       String
  property :features,           String
  property :firmware,           String
  property :uuid,               String
  property :channels,           String
  property :name,               String

  def self.update_or_create_from_result(result)
    result = result.dup

    address = result[:address].first

    record = self.all(address: address).first || self.new

    attrs = %w{
      address oui peer_address peer_address_type peer_address_oui
      role lmp_version manufacturer features firmware uuid channels
      name
    }.map(&:to_sym)

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
          record[attr] = result.delete(attr)
          BlueHydra.logger.debug(
            "#{address} updating #{attr} from #{current_val.inspect} to #{new_val}"
          )
        end

        unless result.empty?
          BlueHydra.logger.debug(
            "#{address} updated. unused values: #{result.inspect}"
          )
        end

      end
    end
  end

end
