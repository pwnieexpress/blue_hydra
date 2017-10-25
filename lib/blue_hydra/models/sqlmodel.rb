class Class
    def sql_model_attr_accessor(method_name)
      at_name = "@#{method_name}"
      inst_variable_name = at_name.to_sym
      key = inst_variable_name
      define_method method_name do
        self.instance_variable_get inst_variable_name
      end
      define_method "#{method_name}=" do |new_value|
        self.instance_variable_set inst_variable_name, new_value
        self.dirty_attributes << method_name.to_sym unless [:@id,:@dirty_attributes].include?(inst_variable_name)
      end
		end
end
module BlueHydra
class SQLModel
  attr_accessor :dirty_attributes,:new_row,:transaction_open

  def valid?
    self.validation_map.each do |key,value|
      val = self[key].to_s =~ value
      return false unless val
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

  def destroy!
#TODO
  end

  def load_row(id=nil)
    id = self.id if id.nil?
    return nil if id.nil?
    sql_to_model_conversion(BlueHydra::DB.query("select * from #{self.table_name} where id = #{id} limit 1;").first)
    return nil
  end

  def save_subset(rows)
    #update without entire row
  end

  def save
     return false unless self.valid?
     self.set_updated_at
     self.set_created_at if self.new_row
     statement = "update #{self.table_name} set #{self.model_to_sql_conversion} where id = #{self.id} limit 1;"
     BlueHydra::DB.query(statement)
     statement = nil
     BlueHydra::DB.query("commit;") if self.transaction_open
     self.new_row = false
     self.transaction_open = false if self.transaction_open
     return nil
  end

  def attributes
    attrs = {}
    BlueHydra::DB.schema[self.table_name].each do |key,metadata|
      attrs[key] = self[key]
    end
    return attrs
  end

  def self.attributes
    puts BlueHydra::DB.schema[self.table_name].keys
  end

  def self.id_exist?(id)
    row_ids = BlueHydra::DB.query("select id from #{self::TABLE_NAME} where id = #{id} limit 1;")
    return false if row_ids.nil? || row_ids.first.nil?
    return true
  end

  def self.first
    model = self.new
    model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{self::TABLE_NAME} order by id asc limit 1;").map{|r| r.to_h}.first)
    return model
  end

  def self.get(id)
    return nil unless self.id_exist?(id)
    return self.new(id)
  end

  def self.last
    model = self.new
    model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{self::TABLE_NAME} order by id desc limit 1;").map{|r| r.to_h}.first)
    return model
  end

  def self.create_new
    newobj = self.new
    newobj.id = self.create_new_row
    newobj.new_row = true
    return newobj
  end

  def self.all(query={})
    basequery = "select * from #{self::TABLE_NAME}"
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
        val = self.boolean_to_string(val) if BlueHydra::DB.keys(self::TABLE_NAME)[key][:type] == :boolean
        statement << "#{key} = '#{val}'"
        statement << " AND " unless key == query.keys.last
      end
      basequery << statement
      basequery << endstatement unless endstatement.empty?
    end
    records = []
    row_hashes = BlueHydra::DB.query("#{basequery};").map{|r| r.to_h}
    row_hashes.each do |row|
      obj = self.new(false)
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

  def self.create_new_row
    BlueHydra::DB.query("begin transaction;")
#TODO optimize one call
    BlueHydra::DB.query("insert into #{self::TABLE_NAME} default values;")
    newid = BlueHydra::DB.query("select id from #{self::TABLE_NAME} order by id desc limit 1;").first[:id]
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
    result = BlueHydra::DB.query("select #{statement} from #{self.table_name} where id = #{self.id} limit 1;").first
    statement = nil
    keys = nil
    return result
  end

  def model_to_sql_conversion
    statement = ""
    excluded = ['created_at','id']
    excluded.shift if self.new_row
    BlueHydra::DB.keys(self.table_name).each do |key, type|
      next if excluded.include?(key)
      type = type[:type]
      if type == :json
        data = self.instance_variable_get("@#{key}")
        next if data.nil? || data.empty?
        data.gsub!("'","\'\'")
        #jsondata = JSON.generate(data)
        jsondata = data
        statement << "#{key} = '#{jsondata}'"
        data = nil
      elsif type == :string
        data = self.instance_variable_get("@#{key}").to_s
        if data.nil? || data.empty?
          data = nil
          next
        end
        data.gsub!("'","\'\'")
        statement << "#{key} = '#{data}'"
        data = nil
      elsif type == :integer
        data = self.instance_variable_get("@#{key}")
        next if data.nil?
        statement << "#{key} = #{data.to_i}"
        data = nil
      elsif type == :boolean
        data = self.instance_variable_get("@#{key}")
        next if data.nil?
        sqlbool = BlueHydra::SQLModel.boolean_to_string(data)
        statement << "#{key} = '#{sqlbool}'"
        data = nil
        sqlbool = nil
      elsif type == :datetime
        data = self.instance_variable_get("@#{key}")
        next if data.nil?
        statement << "#{key} = '#{data}'"
        data = nil
      end
      statement << ","
    end
    instance_variables = nil
    statement = statement[0..statement.length-2]
    #GC.start(immedaite_sweep: true, full_mark:false)
    return statement
  end

  THROWOUT = [nil,[],'',{},'[]','{}']
  def sql_to_model_conversion(results={})
    return nil if results.nil? || results.empty?
    BlueHydra::DB.keys(self.table_name).each do |key, type|
      model_key = "@#{key}"
      type = type[:type]
      if type == :json
        unless results[key].nil? || results[key].empty?
          new_data = results.delete(key)
          #jsondata = JSON.parse(new_data)
          jsondata = new_data
          unless THROWOUT.include?(jsondata)
            self.instance_variable_set(model_key,jsondata)
          end
          jsondata = nil
          new_data = nil
        end
      elsif type == :string
        self.instance_variable_set(model_key, results.delete(key).to_s) unless results[key].nil? || results[key].empty?
      elsif type == :integer
        self.instance_variable_set(model_key, results.delete(key).to_i) unless results[key].nil?
      elsif type == :boolean
        unless results[key].nil?
          data = results.delete(key)
          mdata = BlueHydra::SQLModel.string_to_boolean(data)
          self.instance_variable_set(model_key, mdata)
          data = nil
          mdata = nil
        end
      elsif type == :datetime
        self.instance_variable_set(model_key, results.delete(key)) unless results[key].nil?
      end
      model_key = nil
    end
    results = nil
  end

  def set_created_at
    self.created_at = generate_datetime
  end

  def set_updated_at
    self.updated_at = generate_datetime
  end

  def generate_datetime
    DateTime.now.to_s
  end

  def setup
    self.dirty_attributes = []
  end

  TRUE_STRING = 'True'
  FALSE_STRING = 'False'
  def self.boolean_to_string(b)
    return TRUE_STRING if b
    return FALSE_STRING
  end

  def self.string_to_boolean(s)
    return true if s == TRUE_STRING
    return false
  end

  def attribute_dirty?(col)
    self.dirty_attributes.include?(col)
  end

end
end
