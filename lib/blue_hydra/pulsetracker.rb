class BlueHydra::PulseTracker
  include DataMapper::Resource

  property :id,                          Serial
  property :synced_at,                   Integer
  property :hard_reset_at,               Integer
  property :reset_at,                    Integer

  def init
    self.synced_at = 0
    self.hard_reset_at = 0
    self.reset_at = 0
    self.save
  end

  def update_synced_at
    self.synced_at = Time.now.to_i
    self.save
  end

  def update_reset_at
    self.reset_at = Time.now.to_i
    self.save
  end

  def update_hard_reset_at
    self.hard_reset_at = Time.now.to_i
    self.save
  end

# 12 hour flush throttle
  def allowed_to_ship_data?
    return false if (Time.now.to_i - self.synced_at) < 43200
    return true
  end

# hour reset throttle
  def allowed_to_ship_reset?
    return false if (Time.now.to_i - self.reset_at) < 3600
    return true
  end

  def allowed_to_ship_hard_reset?
    return false if (Time.now.to_i - self.hard_reset_at) < 3600
    return true
  end

end


