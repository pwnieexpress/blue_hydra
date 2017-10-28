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
    return migrated
  end

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

  # handles migrations, adds missing columns based on schema on the model,
  # adds missing tables based on model schemas and master schema (models must inherit and be sub'd)
  def self.auto_migrate!
    BlueHydra.logger.info("DB Auto Upgrade...")
    migrated = false
    # handle auto adding columns and tables
    if self.needs_schema_update?
      BlueHydra.logger.info("DB master sql schema different from disk sql schema...")
      # make db complete before modiftying types below
      self.diff_and_update
      migrated = true
    end
    # handle complex migrations like column type changes etc
    migrated = true if self.do_custom_migrations
    BlueHydra.logger.info("DB Upgrade Complete. Changes Made: #{migrated}")
    GC.start
    return migrated
  end

  # automatically add new tables and columns
  # new tables and columns need to be places in lib/blue_hydra/db/migrations/run
  # file names need to match the table/column name exactly i.e le_company_data.sql
  def self.diff_and_update
    disk_columns = {}
    master_columns = {}
    # table name => column names on disk
    get_disk_schema_split.each do |t|
                        disk_columns[t.split(" ")[2]] = t.split(", ").map{|r| r.split(" ")[0]}[1..-1]
                        disk_columns[t.split(" ")[2]] << "id"
                      end
    # table name => column names as defined in @sqlschema (generated)
    get_master_schema_split.each do |t|
                        master_columns[t.split(" ")[2]] = t.split(", ").map{|r| r.split(" ")[0]}[1..-1]
                        master_columns[t.split(" ")[2]] << "id"
                      end
    disk_tables = disk_columns.keys
    master_tables = master_columns.keys
    # diff and update tables
    if disk_tables != master_tables
       BlueHydra.logger.info("adding missing tables")
       self.add_missing_tables((master_tables - disk_tables))
    end
    # diff and update columns
    master_columns.each do |t,c|
      if c.sort != disk_columns[t].sort
        BlueHydra.logger.info("adding missing columns")
        self.add_missing_columns(t,(c.sort - disk_columns[t].sort))
      end
    end
    GC.start
  end

  # trigger migration file based on the missing table name
  def self.add_missing_tables(tables)
    tables.each do |m|
     BlueHydra.logger.info("adding missing table #{m}")
     missing_table_model = self.model_by_table_name(table)
     create_stmt = missing_table_model.build_model_schema
     self.do_automatic_migration(create_stmt)
    end
  end

  # trigger migration file based on the missing column name
  def self.add_missing_columns(table,columns)
    columns.each do |m|
     BlueHydra.logger.info("adding missing column #{m}")
     missing_column_type = self.schema_by_table_name(table)[m.to_sym][:sqldef]
     self.do_automatic_migration("ALTER TABLE #{table} ADD COLUMN #{m} #{missing_column_type};")
    end
  end

  def self.do_automatic_migration(script)
    `sqlite3 #{DATABASE_LOCATION} "#{script}"`
  end

  def self.do_migration(file_name)
    `sqlite3 #{DATABASE_LOCATION} < $(pwd)'/lib/blue_hydra/db/migrations/run/#{file_name}.sql'`
  end
  # End migration logic
  ########################################
end

