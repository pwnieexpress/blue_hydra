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

end

