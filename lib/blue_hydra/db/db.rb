module BlueHydra::DB
  # master schema defines table names and the schema for each table
  SCHEMA  = { BlueHydra::Device::TABLE_NAME => BlueHydra::Device.schema,
                 BlueHydra::SyncVersion::TABLE_NAME => BlueHydra::SyncVersion.schema }.freeze
  def self.schema
    SCHEMA
  end
  def keys(table)
   SCHEMA[table]
  end
  SENSOR_DB_PATH = '/opt/pwnix/data/blue_hydra/blue_hydra.db'.freeze
  def db_exist?
    return true if File.exist?(SENSOR_DB_PATH)
    return false
  end

  def self.db
    unless @db
      @db = SQLite3::Database.new SENSOR_DB_PATH
      @db.results_as_hash = true
    end
    return @db
  end

  def self.query(statement,args={})
    #query = self.db.prepare(statement)
    #resultset = query.execute
    begin
      resultset = self.db.query(statement)
    rescue
      BlueHydra.logger.error(statement)
      require 'pry'
      binding.pry
    end
    result_array = []
    resultset.each_hash do |h|
      result_array << h.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
    end
    resultset.reset
    resultset.close
    resultset = nil
    query = nil
    GC.start(full_mark:false,immediate_sweep:true)
    return result_array
  end

  def create_db
   sqlschema = "CREATE TABLE IF NOT EXISTS blue_hydra_devices (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, uuid VARCHAR(50), name VARCHAR(50), status VARCHAR(50), address VARCHAR(50), uap_lap VARCHAR(50), vendor TEXT, appearance VARCHAR(50), company VARCHAR(50), company_type VARCHAR(50), lmp_version VARCHAR(50), manufacturer VARCHAR(50), firmware VARCHAR(50), classic_mode BOOLEAN DEFAULT 'f', classic_service_uuids TEXT, classic_channels TEXT, classic_major_class VARCHAR(50), classic_minor_class VARCHAR(50), classic_class TEXT, classic_rssi TEXT, classic_tx_power TEXT, classic_features TEXT, classic_features_bitmap TEXT, le_mode BOOLEAN DEFAULT 'f', le_service_uuids TEXT, le_address_type VARCHAR(50), le_random_address_type VARCHAR(50), le_company_data VARCHAR(50), le_company_uuid VARCHAR(50), le_proximity_uuid VARCHAR(50), le_major_num VARCHAR(50), le_minor_num VARCHAR(50), le_flags TEXT, le_rssi TEXT, le_tx_power TEXT, le_features TEXT, le_features_bitmap TEXT, ibeacon_range VARCHAR(50), created_at TIMESTAMP, updated_at TIMESTAMP, last_seen INTEGER); CREATE TABLE IF NOT EXISTS blue_hydra_sync_versions (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, version VARCHAR(50));"
    `touch /opt/pwnix/data/blue_hydra/blue_hydra.db`
    `sqlite3 /opt/pwnix/data/blue_hydra/blue_hydra.db \"#{sqlschema}\"`
  end

  module_function :keys,:db_exist?,:create_db
end

