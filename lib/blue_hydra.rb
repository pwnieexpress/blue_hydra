# Core Libs
require 'pty'
require 'logger'
require 'json'
require 'open3'

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
  # 0.0.1 first stable verison
  # 0.0.2 timestamps, feedback loop for info scans, l2ping
  VERSION = '0.0.2'

  CONFIG_FILE = if Dir.exists?('/var/log/pwnix/pwnix-config')
              File.expand_path('/var/log/pwnix/pwnix-config/blue_hydra.json', __FILE__)
            else
              File.expand_path('../../blue_hydra.json', __FILE__)
            end

  DEFAULT_CONFIG = {
    log_level: "debug",
    bt_device: "hci0" # TODO - make use of...?
  }

  @@config = if File.exists?(CONFIG_FILE)
               DEFAULT_CONFIG.merge(JSON.parse(
                 File.read(CONFIG_FILE),
                 symbolize_names: true
               ))
             else
               # TODO update config with defaults
               DEFAULT_CONFIG
             end

  LOGFILE = if Dir.exists?('/var/log/pwnix')
              File.expand_path('/var/log/pwnix/blue_hydra.log', __FILE__)
            else
              File.expand_path('../../blue_hydra.log', __FILE__)
            end

  @@logger = Logger.new(LOGFILE)
  @@logger.level = case @@config[:log_level]
                   when "fatal"
                     Logger::FATAL
                   when "error"
                     Logger::ERROR
                   when "warn"
                     Logger::WARN
                   when "info"
                     Logger::INFO
                   when "debug"
                     Logger::DEBUG
                   else
                     Logger::INFO
                   end

  def logger
    @@logger
  end

  def config
    @@config
  end

  module_function :logger
end

require 'blue_hydra/btmon_handler'
require 'blue_hydra/parser'
require 'blue_hydra/chunker'
require 'blue_hydra/runner'
require 'blue_hydra/command'
require 'blue_hydra/device'

DataMapper.auto_upgrade!
DataMapper.finalize
