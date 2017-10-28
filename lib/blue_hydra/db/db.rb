module BlueHydra::DB
  #  NOTES:
  # finalize_setup! builds master schema and sqlschema
  # DOES NOT HANDLE RELATIONSHIPS
  # handles automatically adding columns and tables for new models
  # automatically generates sql schema based on model's schema constants

  @models ||= []
  @setup = false
  def self.finalize_setup!
    @schema ||= {}
    @sqlschema = ""
    @models.map do |model|
     @schema[model::TABLE_NAME] = { model: model, schema: model.schema }
     @sqlschema << model.build_model_schema + " "
    end
    @setup = true
    @sqlschema.chomp!(" ")
    return nil
  end

  # MASTER SCHEMA getter
  # built by teh call to BlueHydra::DB.finalize_setup!
  #  { "table_name" => {model: <SQLModel>, schema: <SQLModel>.schema},
  #   etc,
  #   etc }
  def self.schema
    @schema
  end

  # return schema based on string table name
  def self.keys(table)
   @schema[table][:schema]
  end

  # adds model object to @models, used to build @schema and @sqlschema
  # required call for models
  def self.subscribe_model(model)
    @models << model unless @setup
  end

  def self.model_by_table_name(name)
    @schema[name][:model]
  end

  def self.schema_by_table_name(name)
    @schema[name][:schema]
  end

  def self.db_exist?
    return true if File.exist?(DATABASE_LOCATION)
    return false
  end

  def self.create_db
    `touch /opt/pwnix/data/blue_hydra/blue_hydra.db`
    `sqlite3 /opt/pwnix/data/blue_hydra/blue_hydra.db \"#{@sqlschema}\"`
  end

  def self.db
    unless @db
      @db ||= SQLite3::Database.new(DATABASE_LOCATION)
      @db.results_as_hash = true
    end
    return @db
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

  ####################################
  # Migration Logic
  ####################################

  # handles migrations, adds missing columns based on schema on the model,
  # adds missing tables based on model schemas and master schema (models must inherit and be sub'd)
  def self.auto_migrate!
    BlueHydra.logger.info("DB Auto Upgrade...")
    migrated = false
    # handle auto adding columns and tables
    # chaep check, if schema out of order diff is smart enough to handle but not this check
    if self.needs_schema_update?
      # make db complete before modiftying types below
      migrated = true if self.diff_and_update
    end
    # handle complex migrations like column type changes etc
    migrated = true if self.do_custom_migrations
    BlueHydra.logger.info("DB Auto Upgrade Complete. Changes Made: #{migrated}")
    GC.start
    return migrated
  end

  # Handle migrations outside of what sqlite supports (i.e type changes, adding defaults)
  def self.do_custom_migrations
    migrated = false
    if self.needs_boolean_migration?
      BlueHydra.logger.info("DB MIGRATION: adding missing boolean default values...")
      do_migration("default_boolean_fix")
      migrated = true
    end
    if self.needs_varchar_migration?
      BlueHydra.logger.info("DB MIGRATION: fixing varchar values...")
      do_migration("fix_varchar")
      migrated = true
    end
    # additional custom migrations and checks should be defined here before return
    # if self.some_migration_needed?
    #   Log
    #   do_migration(<some_file_name>)
    #   migrated = true
    # end
    return migrated
  end

  ####################################
  # Custom Migration Checks
  ####################################

  # le mode and classic mode had a default added
  def self.needs_boolean_migration?
    return true unless whole_disk_schema.include?("le_mode BOOLEAN DEFAULT 'f'") && whole_disk_schema.include?("classic_mode BOOLEAN DEFAULT 'f'")
    return false
  end

  # company and le_company_data varchar(50) to varchar(255) conversion
  def self.needs_varchar_migration?
    return true unless whole_disk_schema.include?("company VARCHAR(255)") && whole_disk_schema.include?("le_company_data VARCHAR(255)")
    return false
  end

  ####################################
  # Schema Helper Functions
  ####################################

  def self.get_master_schema_split
    return @sqlschema.split("; ")
  end

  def self.whole_disk_schema
    return (self.get_disk_schema_split.join("; ")+";")
  end

  def self.get_disk_schema_split
    return nil unless self.db_exist?
    tables = BlueHydra::DB.query("SELECT sql FROM sqlite_master ORDER BY tbl_name, type DESC, name").map{|h| h.values}.flatten
    @tables ||= tables.select!{|t| self.schema.keys.include?(t.split(" ")[2])}
    return @tables
  end

  # Cheap helper, disk schema should match master schema @sqlschema exactly
  def self.needs_schema_update?
    return true if @sqlschema != self.whole_disk_schema
    return false
  end

  # automatically add new tables and columns
  # new tables and columns need to be places in lib/blue_hydra/db/migrations/run
  # file names need to match the table/column name exactly i.e le_company_data.sql
  def self.diff_and_update
    BlueHydra.logger.info("DB master sql schema may differ from disk sql schema... doing diff")
    # diff data setup
    disk_schema = {}
    master_schema = {}
    # table name => column names on disk
    get_disk_schema_split.each do |table_create_stmt|
                        schema = {}
                        table_create_stmt.split(", ").map{|r| r.split(" ")}[1..-1].each{|a| schema[a[0]] = a[1]}
                        disk_schema[table_create_stmt.split(" ")[2]] = schema
                      end
    # table name => column names as defined in @sqlschema (generated)
    get_master_schema_split.each do |table_create_stmt|
                        schema = {}
                        table_create_stmt.split(", ").map{|r| r.split(" ")}[1..-1].each{|a| schema[a[0]] = a[1]}
                        master_schema[table_create_stmt.split(" ")[2]] = schema
                      end
    disk_tables = disk_schema.keys
    master_tables = master_schema.keys

    # diffs and updates
    migrated = false
    # MODEL / table diff & update
    if disk_tables.sort != master_tables.sort
      missing_tables_on_disk = (master_tables - disk_tables)
      if !missing_tables_on_disk.empty?
        self.add_missing_tables(missing_tables_on_disk)
        migrated = true
      else
#table/model name/def mismatch
      end
    end

    # PROPERTY / column diff & update
    # compare types AND names
    # iterates over tables
    # t => columns{ name => type }
    master_schema.each do |table,columns|
      if columns.sort != disk_schema[table].sort
        missing_columns_on_disk = (columns.keys.sort - disk_schema[table].keys.sort)
        if !missing_columns_on_disk.empty?
          self.add_missing_columns(table,missing_columns_on_disk)
          migrated = true
        else
#type mismatch
        end
      end
    end
    GC.start
    return migrated
  end

  # generate and trigger migration based on the missing table name
  def self.add_missing_tables(tables)
    tables.each do |m|
     BlueHydra.logger.info("adding missing table #{m}")
     missing_table_model = self.model_by_table_name(table)
     create_stmt = missing_table_model.build_model_schema
     self.do_automatic_migration(create_stmt)
    end
  end

  # generate and trigger migration based on the missing column name
  def self.add_missing_columns(table,columns)
    columns.each do |m|
     BlueHydra.logger.info("adding missing column #{m}")
     missing_column_type = self.schema_by_table_name(table)[m.to_sym][:sqldef]
     self.do_automatic_migration("ALTER TABLE #{table} ADD COLUMN #{m} #{missing_column_type};")
    end
  end

  # helper to shell out and run custom migration sql command
  def self.do_automatic_migration(script)
    `sqlite3 #{DATABASE_LOCATION} "#{script}"`
  end

  # helepr to shell out and run whole file migration /migration/run/<file_name>.sql
  def self.do_migration(file_name)
    `sqlite3 #{DATABASE_LOCATION} < $(pwd)'/lib/blue_hydra/db/migrations/run/#{file_name}.sql'`
  end
end

