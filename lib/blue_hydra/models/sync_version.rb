# this is the bluetooth Device model stored in the DB
class BlueHydra::SyncVersion < BlueHydra::SQLModel
  TABLE_NAME = 'blue_hydra_sync_versions'.freeze
  def table_name
    TABLE_NAME
  end
  SCHEMA = { id:       {type: :integer, sqldef: ID},
             version:  {type: :string, sqldef: VARCHAR50}
            }.freeze
  def self.schema
    SCHEMA
  end
  # setup properties
  SCHEMA.each do |property,metadata|
    sql_model_attr_accessor property
  end
  def initialize(id=nil)
    setup
    load_row(id) if id
    self
  end

  def save
    generate_version
    super
  end

  def generate_version
    self.version = SecureRandom.uuid
  end

  def self.count
    self.table_count(TABLE_NAME)
  end

end


