module BlueHydra::DB
  SCHEMA = {
    'blue_hydra_sync_versions' => { 'id' => :integer,
                                    'version' => :string
                                  }.freeze,
    'blue_hydra_devices'       => { 'id' => :integer,
                                    'uuid' => :string,
                                    'name' => :string,
                                    'status' => :string,
                                    'address' => :string,
                                    'uap_lap' => :string,
                                    'vendor' => :string,
                                    'appearance' => :string,
                                    'company' => :string,
                                    'company_type' => :string,
                                    'lmp_version' => :string,
                                    'manufacturer' => :string,
                                    'firmware' => :string,
                                    'classic_mode' => :boolean,
                                    'classic_service_uuids' => :json,
                                    'classic_channels' => :json,
                                    'classic_major_class' => :string,
                                    'classic_minor_class' => :string,
                                    'classic_class' => :json,
                                    'classic_rssi' => :json,
                                    'classic_tx_power' => :string,
                                    'classic_features' => :json,
                                    'classic_features_bitmap' => :json,
                                    'le_mode' => :boolean,
                                    'le_service_uuids' => :json,
                                    'le_address_type' => :string,
                                    'le_random_address_type' => :string,
                                    'le_company_data' => :string,
                                    'le_company_uuid' => :string,
                                    'le_proximity_uuid' => :string,
                                    'le_major_num' => :string,
                                    'le_minor_num' => :string,
                                    'le_flags' => :json,
                                    'le_rssi' => :json,
                                    'le_tx_power' => :string,
                                    'le_features' => :json,
                                    'le_features_bitmap' => :json,
                                    'ibeacon_range' => :string,
                                    'created_at' => :datetime,
                                    'updated_at' => :datetime,
                                    'last_seen' => :integer
                                  }.freeze
            }.freeze

  def keys(table='blue_hydra_devices')
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
			@db.cache_size = 512000   # 500M
			@db.temp_store = 2            # memory
    end
    return @db
  end

  def self.query(statement,args={})
    #query = self.db.prepare(statement)
    #resultset = query.execute
    resultset = self.db.query(statement)
    result_array = []
    resultset.each_hash do |h|
      result_array << h
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

  class SQLModel
    attr_accessor :dirty_attributes,:model_obj,:new_row,:transaction_open

    def valid?
      BlueHydra::DB.keys(self.model_obj.table_name).each do |key,type|
        if self.model_obj.validation_map.keys.include?(key)
          self.model_obj.validation_map.each do |key,value|
            return false unless self.model_obj[key] =~ value
          end
        end
      end
      return true
    end

    def self.table_count(table)
      BlueHydra::DB.query("select id from #{table};").count
    end

    def [](key)
      get_key = "@#{key}"
      data = self.instance_variable_get(get_key)
      get_key = nil
      key = nil
      return data
    end

    def []=(key,data)
      set_key = "@#{key}"
      self.instance_variable_set(set_key,data)
      self.dirty_attributes << key unless [:@id,:@dirty_attributes].include?(key)
      set_key = nil
      key = nil
      return nil
    end

    def create_new_row
      self.new_row = true
      BlueHydra::DB.query("begin transaction;")
#TODO optimize one call
      BlueHydra::DB.query("insert into #{self.model_obj.table_name} default values;")
      newid = BlueHydra::DB.query("select id from #{self.model_obj.table_name} order by id desc limit 1;").first['id']
#TODO replace with commit call
      BlueHydra::DB.query("commit;")
      BlueHydra.logger.debug("--DB new row id: #{newid}")
      return newid
    end

    def load_row_subset(keys=[])
      return nil if keys.empty?
      statement = ""
      keys.each do |k|
        statement << "#{k}"
        statement << "," unless k == keys.last
      end
      self.new_row = true
      self.transaction_open = true
      result = BlueHydra::DB.query("select #{statement} from #{self.model_obj.table_name} where id = #{self.id} limit 1;").first
      statement = nil
      keys = nil
      return result
    end

    def model_to_sql_conversion
      statement = ""
      excluded = ['created_at','id']
      excluded.shift if self.new_row
      BlueHydra::DB.keys(self.model_obj.table_name).each do |key, type|
        next if excluded.include?(key)
        if type == :json
          data = self.model_obj.instance_variable_get("@#{key}")
          next if data.nil? || data.empty?
          jsondata = Oj.dump(data)
          statement << "#{key} = '#{jsondata}'"
          data = nil
        elsif type == :string
          data = self.model_obj.instance_variable_get("@#{key}").to_s
          if data.nil? || data.empty?
            data = nil
            next 
          end
          statement << "#{key} = '#{data}'"
          data = nil
        elsif type == :integer
          data = self.model_obj.instance_variable_get("@#{key}")
          next if data.nil?
          statement << "#{key} = #{data.to_i}"
          data = nil
        elsif type == :boolean
          data = self.model_obj.instance_variable_get("@#{key}")
          next if data.nil?
          sqlbool = BlueHydra::DB::SQLModel.boolean_to_string(data)
          statement << "#{key} = '#{sqlbool}'"
          data = nil
          sqlbool = nil
        elsif type == :datetime
          data = self.model_obj.instance_variable_get("@#{key}")
          next if data.nil?
          statement << "#{key} = '#{data}'"
          data = nil
        end
        statement << ","
      end
      instance_variables = nil
      statement = statement[0..statement.length-2]
      return statement
    end

    THROWOUT = [nil,[],'',{},'[]','{}'].freeze
    def sql_to_model_conversion(results={})
      return nil if results.nil? || results.empty?
      BlueHydra::DB.keys(self.model_obj.table_name).each do |key, type|
        model_key = "@" << key
        if type == :json
          unless results[key].nil? || results[key].empty?
            new_data = results.delete(key)
            jsondata = JSON.parse(new_data)
            unless THROWOUT.include?(jsondata)
              self.instance_variable_set(model_key,jsondata)
            end
            jsondata = nil
            new_data = nil
          end
        elsif type == :string
          self.model_obj.instance_variable_set(model_key, results.delete(key).to_s) unless results[key].nil? || results[key].empty?
        elsif type == :integer
          self.model_obj.instance_variable_set(model_key, results.delete(key).to_i) unless results[key].nil?
        elsif type == :boolean
          unless results[key].nil?
            data = results.delete(key)
            mdata = BlueHydra::DB::SQLModel.string_to_boolean(data)
            self.model_obj.instance_variable_set(model_key, mdata)
            data = nil
            mdata = nil
          end
        elsif type == :datetime
          self.model_obj.instance_variable_set(model_key, results.delete(key)) unless results[key].nil?
        end
        model_key = nil
      end
      results = nil
      #self.model_obj
    end

    def set_created_at
      self.model_obj.created_at = generate_datetime
    end

    def set_updated_at
      self.model_obj.updated_at = generate_datetime
    end

    def generate_datetime
      DateTime.now.to_s
    end

    def initialize(model)
      self.model_obj = model
      self.dirty_attributes = []
      self
    end

    TRUE_STRING = 'True'.freeze
    FALSE_STRING = 'False'.freeze
    def self.boolean_to_string(b)
      return TRUE_STRING if b
      return FALSE_STRING
    end

    def self.string_to_boolean(s)
      return true if s == TRUE_STRING
      return false
    end

    def attribute_dirty?(col)
      self.model_obj.dirty_attributes.include?(col)
    end

  end
  module_function :keys,:db_exist?,:create_db
end

class Class
    def sql_model_attr_accessor(method_name)
      inst_variable_name = "@#{method_name}".to_sym
      key = inst_variable_name
      define_method method_name do
        self.instance_variable_get inst_variable_name
      end
      define_method "#{method_name}=" do |new_value|
        self.instance_variable_set inst_variable_name, new_value
        self.dirty_attributes << inst_variable_name unless [:@id,:@dirty_attributes].include?(key)
      end
		end
end
