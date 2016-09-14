# this is the bluetooth Device model stored in the DB
class BlueHydra::SyncVersion
  # this is a DataMapper model...
  include DataMapper::Resource

  property :id, Serial
  property :version, String

  before :save, :generate_version

  def generate_version
    self.version = SecureRandom.uuid
  end
end


