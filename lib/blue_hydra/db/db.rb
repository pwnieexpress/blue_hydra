module BlueHydra::DB
  # master schema defines table names and the schema for each table
  @sqlschema = "CREATE TABLE blue_hydra_devices (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, uuid VARCHAR(50), name VARCHAR(50), status VARCHAR(50), address VARCHAR(50), uap_lap VARCHAR(50), vendor TEXT, appearance VARCHAR(50), company VARCHAR(50), company_type VARCHAR(50), lmp_version VARCHAR(50), manufacturer VARCHAR(50), firmware VARCHAR(50), classic_mode BOOLEAN DEFAULT 'f', classic_service_uuids TEXT, classic_channels TEXT, classic_major_class VARCHAR(50), classic_minor_class VARCHAR(50), classic_class TEXT, classic_rssi TEXT, classic_tx_power TEXT, classic_features TEXT, classic_features_bitmap TEXT, le_mode BOOLEAN DEFAULT 'f', le_service_uuids TEXT, le_address_type VARCHAR(50), le_random_address_type VARCHAR(50), le_company_data VARCHAR(50), le_company_uuid VARCHAR(50), le_proximity_uuid VARCHAR(50), le_major_num VARCHAR(50), le_minor_num VARCHAR(50), le_flags TEXT, le_rssi TEXT, le_tx_power TEXT, le_features TEXT, le_features_bitmap TEXT, ibeacon_range VARCHAR(50), created_at TIMESTAMP, updated_at TIMESTAMP, last_seen INTEGER); CREATE TABLE blue_hydra_sync_versions (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, version VARCHAR(50));"

  SCHEMA  = { BlueHydra::Device::TABLE_NAME =>       BlueHydra::Device.schema,
              BlueHydra::SyncVersion::TABLE_NAME =>  BlueHydra::SyncVersion.schema }.freeze
  def self.schema
    SCHEMA
  end

  def keys(table)
   SCHEMA[table]
  end

  def db_exist?
    return true if File.exist?(DATABASE_LOCATION)
    return false
  end

  def self.db
    unless @db
      @db = SQLite3::Database.new(DATABASE_LOCATION)
      @db.results_as_hash = true
    end
    return @db
  end

  def self.needs_schema_update?
    return true if self.current_master_schema != self.current_disk_schema
    return false
  end

  def self.needs_type_change_migration?
    # le mode and classic mode had a default added
    return true unless current_disk_schema.include?("le_mode BOOLEAN DEFAULT 'f'") && current_disk_schema.include?("classic_mode BOOLEAN DEFAULT 'f'")
    return false
  end

  def self.auto_migrate!
    BlueHydra.logger.info("DB Auto Upgrade...")
    unless self.db_exist?
      BlueHydra.logger.info("No DB found. DB created...")
      self.create_db
      return true
    end
    migrated = false
    # make tables whole
    if self.needs_schema_update?
      BlueHydra.logger.info("DB missing columns...")
      self.diff_and_update
      migrated = true
    end
    # upgrade default values with new table migration
    if self.needs_type_change_migration?
      BlueHydra.logger.info("DB MIGRATION: adding missing boolean default values...")
      do_migration("default_boolean_fix")
      migrated = true
    end
    BlueHydra.logger.info("DB Upgrade Complete. Changes Made: #{migrated}")
    GC.start
    return migrated
  end

  # migrations support for adding tables and columns
  def self.diff_and_update
    disk_columns = {}
    master_columns = {}
    get_disk_schema.each do |t|
                        disk_columns[t.split(" ")[2]] = t.split(", ").map{|r| r.split(" ")[0]}[1..-1]
                        disk_columns[t.split(" ")[2]] << "id"
                      end
    get_master_schema.each do |t|
                        master_columns[t.split(" ")[2]] = t.split(", ").map{|r| r.split(" ")[0]}[1..-1]
                        master_columns[t.split(" ")[2]] << "id"
                      end
    disk_tables = disk_columns.keys
    master_tables = master_columns.keys
    if disk_tables != master_tables
       BlueHydra.logger.info("adding missing tables")
       self.add_missing_tables((master_tables - disk_tables))
    end
    master_columns.each do |t,c|
      if c.sort != disk_columns[t].sort
        BlueHydra.logger.info("adding missing columns")
        self.add_missing_columns((c.sort - disk_columns[t].sort))
      end
    end
    GC.start
  end

  # trigger migration file based on the missing column name
  def self.add_missing_tables(tables)
    tables.each do |m|
     BlueHydra.logger.info("adding missing table #{m}")
     self.do_migration(m)
    end
  end

  # trigger migration file based on the missing column name
  def self.add_missing_columns(columns)
    columns.each do |m|
     BlueHydra.logger.info("adding missing column #{m}")
     self.do_migration(m)
    end
  end

  # MIGRATION FILES NEED TO BE NAMED THE MISSING TABLE OR COLUMN NAME EXACTLY
  def self.do_migration(file_name)
    `sqlite3 #{DATABASE_LOCATION} < $(pwd)'/lib/blue_hydra/db/migrations/run/#{file_name}.sql'`
  end

  # helper functions to parse sql schemas and build the same structured hash
  # table name => columns
  def self.get_master_schema
    return self.current_master_schema.split("; ")
  end

  def self.current_master_schema
    @sqlschema
  end

  def self.current_disk_schema
    return (self.get_disk_schema.join("; ")+";")
  end

  def self.get_disk_schema
    return nil unless self.db_exist?
    tables = BlueHydra::DB.query("SELECT sql FROM sqlite_master ORDER BY tbl_name, type DESC, name").map{|h| h.values}.flatten
    @tables ||= tables.select!{|t| SCHEMA.keys.include?(t.split(" ")[2])}
    return @tables
  end

  @dbmutex = Mutex.new
  def self.query(statement)
    @dbmutex.synchronize do
      begin
        resultset = self.db.query(statement)
      rescue
        BlueHydra.logger.error(statement)
        require 'pry'
        binding.pry
        return []
      end
      result_array = []
      resultset.each_hash do |h|
        result_array << h.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
      end
      resultset.reset
      resultset.close
      resultset = nil
      statement = nil
      query = nil
      GC.start(full_mark:false,immediate_sweep:true)
      return result_array
    end
  end

  def create_db
    `touch /opt/pwnix/data/blue_hydra/blue_hydra.db`
    `sqlite3 /opt/pwnix/data/blue_hydra/blue_hydra.db \"#{@sqlschema}\"`
  end

  module_function :keys,:db_exist?,:create_db
end

