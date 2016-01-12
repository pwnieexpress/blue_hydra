# Core Libs
require 'pty'
require 'logger'
require 'json'

# Gems
require 'data_mapper'
require 'dm-timestamps'
require 'dm-validations'
require 'louis'

$:.unshift(File.dirname(__FILE__))

# set all String properties to have a default length of 255.. we learned this
# less from PwnScan
DataMapper::Property::String.length(255)

# The database will be stored in /opt/pwnix/blue_hydra.db if we are on a system
# which the Pwnie chef scripts have been run. Otherwise it will attempt to
# create a sqlite db whereever the run was initiated.
DataMapper.setup(
  :default,
  Dir.exist?('/opt/pwnix/') ?  "sqlite:/opt/pwnix/blue_hydra.db" : "sqlite:blue_hydra.db"
)

module BlueHydra
  # 0.0.1 -- initial build out using
  VERSION = '0.0.1'

  LOGFILE = if Dir.exists?('/var/log/pwnix')
              File.expand_path('/var/log/pwnix/blue_hydra.log', __FILE__)
            else
              File.expand_path('../../blue_hydra.log', __FILE__)
            end

  @@logger = Logger.new(LOGFILE)
  @@logger.level = Logger::DEBUG

  def logger
    @@logger
  end

  module_function :logger
end

require 'blue_hydra/pty_spawner'
require 'blue_hydra/parser'
require 'blue_hydra/chunker'
require 'blue_hydra/runner'
require 'blue_hydra/device'

DataMapper.auto_upgrade!
DataMapper.finalize
