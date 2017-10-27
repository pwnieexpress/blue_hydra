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
        return nil
      end
		end
end

class BlueHydra::SQLModel
  attr_accessor :dirty_attributes,:new_row

  def valid?
    self.validation_map.each do |key,value|
      val = self[key].to_s =~ value
      return false unless val
    end
    return true
  end
  def validation_map
    {}
  end

  def self.table_count(table)
    BlueHydra::DB.query("select id from #{table};").count
  end

  def [](key)
    return self.instance_variable_get("@#{key}")
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
     statement = "delete from #{self.table_name} where id = #{self.id} limit 1;"
     BlueHydra::DB.query(statement)
     statement = nil
     BlueHydra::DB.db.commit if BlueHydra::DB.db.transaction_active?
     return nil
  end

  def load_row(id=nil)
    id = self.id if id.nil?
    return nil if id.nil?
    sql_to_model_conversion(BlueHydra::DB.query("select * from #{self.table_name} where id = #{id} limit 1;").first)
    return nil
  end

  def save_subset(rows)
     return false unless self.valid?
     updatestatement = self.model_to_sql_conversion(BlueHydra::DB.keys(self.table_name).select{|k,v| rows.include?(k)})
     statement = "update #{self.table_name} set #{updatestatement} where id = #{self.id} limit 1;"
     BlueHydra::DB.query(statement)
     statement = nil
     updatestatement = nil
     BlueHydra::DB.db.commit if BlueHydra::DB.db.transaction_active?
     return nil
  end

  def save
     return false unless self.valid?
     # performance shortcut, only update what changes
     # at a minimum this is updated at
     unless self.new_row
      return false if self.dirty_attributes.empty?
      self.save_subset(self.dirty_attributes)
      return nil
     end
     statement = "update #{self.table_name} set #{self.model_to_sql_conversion} where id = #{self.id} limit 1;"
     BlueHydra::DB.query(statement)
     statement = nil
     BlueHydra::DB.db.commit if BlueHydra::DB.db.transaction_active?
     self.new_row = false
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
    return nil
  end

  def self.id_exist?(id)
    row_ids = BlueHydra::DB.query("select id from #{self::TABLE_NAME} where id = #{id} limit 1;")
    return false if row_ids.nil? || row_ids.first.nil?
    return true
  end

  def self.first
    model = self.new
    return nil unless model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{self::TABLE_NAME} order by id asc limit 1;").map{|r| r.to_h}.first)
    return model
  end

  def self.get(id)
    return nil unless self.id_exist?(id)
    return self.new(id)
  end

  def self.last
    model = self.new
    return nil unless model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{self::TABLE_NAME} order by id desc limit 1;").map{|r| r.to_h}.first)
    return model
  end

  def self.create_new
    newobj = self.new
    newobj.id = self.create_new_row
    newobj.new_row = true
    return newobj
  end

  def self.all_not(query={})
    self.all(query,true)
  end

  def self.all(query={},negate=false)
    basequery = "select * from #{self::TABLE_NAME}"
    if negate
      op = "!="
    else
      op = "="
    end
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
        statement << "#{key} #{op} '#{val}'"
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
    BlueHydra::DB.query("insert into #{self::TABLE_NAME} default values;")
    newid = BlueHydra::DB.db.last_insert_row_id
    BlueHydra::DB.db.commit if BlueHydra::DB.db.transaction_active?
    BlueHydra.logger.debug("--DB new row id: #{newid}")
    return newid
  end

  # for eventual lazy loading nightmare
  #def load_row_subset(keys=[])
  #  return nil if keys.empty?
  #  statement = ""
  #  keys.each do |k|
  #    statement << "#{k}"
  #    statement << "," unless k == keys.last
  #  end
  #  self.new_row = true
  #  result = BlueHydra::DB.query("select #{statement} from #{self.table_name} where id = #{self.id} limit 1;").first
  #  statement = nil
  #  keys = nil
  #  return result
  #end

  THROWOUT = [nil,[],'',{},'[]','{}']
  def model_to_sql_conversion(rows=nil)
    rows = BlueHydra::DB.keys(self.table_name) unless rows
    statement = ""
    excluded = ['created_at','id']
    excluded.shift if self.new_row
    rows.each do |key, type|
      next if excluded.include?(key)
      type = type[:type]
      if type == :json
        data = self.instance_variable_get("@#{key}")
        next if THROWOUT.include?(data)
        data.gsub!("'","\'\'")
        #jsondata = JSON.generate(data)
        statement << "#{key} = '#{data}'"
        data = nil
      elsif type == :string
        data = self.instance_variable_get("@#{key}").to_s
        if THROWOUT.include?(data)
          data = nil
          next
        end
        data.gsub!("'","\'\'")
        statement << "#{key} = '#{data}'"
        data = nil
      elsif type == :integer
        data = self.instance_variable_get("@#{key}")
        next if THROWOUT.include?(data)
        statement << "#{key} = #{data.to_i}"
        data = nil
      elsif type == :boolean
        data = self.instance_variable_get("@#{key}")
        next if THROWOUT.include?(data)
        statement << "#{key} = '#{BlueHydra::SQLModel.boolean_to_string(data)}'"
        data = nil
      elsif type == :datetime
        data = self.instance_variable_get("@#{key}")
        next if THROWOUT.include?(data)
        statement << "#{key} = '#{data}'"
        data = nil
      end
      statement << ", "
    end
    instance_variables = nil
    statement = statement.chomp(", ")
    return statement
  end

  def sql_to_model_conversion(results={})
    return nil if THROWOUT.include?(results)
    BlueHydra::DB.keys(self.table_name).each do |key, type|
      model_key = "@#{key}"
      type = type[:type]
      if type == :json
          #jsondata = JSON.parse(new_data)
          # json fields are managed in the setter functions
          # this gives us a lazy, lazy loading since JSON encoding/decoding uses so many intermediate objects
          self.instance_variable_set(model_key,results.delete(key)) unless THROWOUT.include?(results[key])
          next
      elsif type == :string
        self.instance_variable_set(model_key, results.delete(key).to_s) unless THROWOUT.include?(results[key])
        next
      elsif type == :integer
        self.instance_variable_set(model_key, results.delete(key).to_i) unless THROWOUT.include?(results[key])
        next
      elsif type == :boolean
        self.instance_variable_set(model_key,BlueHydra::SQLModel.string_to_boolean(results.delete(key))) unless THROWOUT.include?(results[key])
        next
      elsif type == :datetime
        self.instance_variable_set(model_key, results.delete(key)) unless THROWOUT.include?(results[key])
        next
      end
      model_key = nil
    end
    results = nil
    return true
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
