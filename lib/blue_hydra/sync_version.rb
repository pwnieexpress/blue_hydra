# this is the bluetooth Device model stored in the DB
class BlueHydra::SyncVersion < BlueHydra::DB::SQLModel
  # this is a DataMapper model...
  TABLE_NAME = 'blue_hydra_sync_versions'.freeze
  def table_name
    TABLE_NAME
  end

  BlueHydra::DB.keys(TABLE_NAME).each do |key,table|
    sql_model_attr_accessor key
  end

  def initialize(id=nil)
    super(self)
    load_row(id) if id
    self
  end

  def self.create_new
    newobj = BlueHydra::SyncVersion.new
    newobj.id = newobj.create_new_row
    BlueHydra.logger.info("new sync version created #{newobj.id}")
    return newobj
  end

  def load_row(id=nil)
    id = self.id if id.nil?
    return nil if id.nil?
    BlueHydra.logger.info("load sync version row #{id}")
    self.sql_to_model_conversion(BlueHydra::DB.query("select * from #{TABLE_NAME} where id = #{id} limit 1;").map{|r| r.to_h}.first)
    return nil
  end

  def save
    self.generate_version
    BlueHydra.logger.info("sync version save #{self.id}")
    BlueHydra::DB.query("update #{TABLE_NAME} set #{self.model_to_sql_conversion} where id = #{self.id} limit 1;")
    BlueHydra::DB.query("commit;") if self.transaction_open
    self.new_row = false
    self.transaction_open = false if self.transaction_open
  end

  def self.first
    model = BlueHydra::SyncVersion.new(false)
    model.sql_to_model_conversion(BlueHydra::DB.query("select * from #{TABLE_NAME} order by id asc limit 1;").map{|r| r.to_h}.first)
    return model
  end

  def self.count
    self.table_count(TABLE_NAME)
  end

  def self.last
    BlueHydra::SyncVersion.new(false).sql_to_model_conversion(BlueHydra::DB.query("select * from #{TABLE_NAME} order by id desc limit 1;").map{|r| r.to_h}.first)
  end

  def self.get(id)
    return nil unless BlueHydra::SyncVersion.id_exist?(id)
    self.new(id)
  end

  def self.id_exist?(id)
    row_ids = BlueHydra::DB.query("select id from #{TABLE_NAME} where id = #{id} limit 1;")
    return false if row_ids.nil? || row_ids.first.nil?
    return true
  end

  def self.all(query={},nots={})
    basequery = "select * from #{TABLE_NAME}"
    unless query.empty?
      statement = " WHERE "
      endstatement = ""
      endstatement << " order by #{query.delete(:order)}" if query.keys.include?(:order)
      endstatement << " limit #{query.delete(:limit)}" if query.keys.include?(:limit)
      query.each do |key, val|
        val = self.boolean_to_string(val) if BlueHydra::DB.keys(TABLE_NAME)[key.to_sym] == :boolean
        statement << "#{key.to_s} = "
        statement << "'"
        statement << "#{val}"
        statement << "'"
        statement << " AND " unless key == query.keys.last
      end
      basequery << statement
    end
    records = []
    row_hashes = BlueHydra::DB.query("#{basequery};").map{|r| r.to_h}
    row_hashes.each do |row|
      obj = BlueHydra::SyncVersion.new(false)
      obj.sql_to_model_conversion(row)
      records << obj
    end
    records
  end

  def generate_version
    self.version = SecureRandom.uuid
  end

end


