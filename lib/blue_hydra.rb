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

# Add to Load Path
$:.unshift(File.dirname(__FILE__))

# set all String properties to have a default length of 255.. we learned this
# lesson from PwnScan
DataMapper::Property::String.length(255)

# The database will be stored in /opt/pwnix/blue_hydra.db if we are on a system
# which the Pwnie chef scripts have been run. Otherwise it will attempt to
# create a sqlite db whereever the run was initiated.
db_path = if ENV["BLUE_HYDRA"] == "test"
            'sqlite::memory:?cache=shared'
          elsif  Dir.exist?('/opt/pwnix/')
            "sqlite:/opt/pwnix/blue_hydra.db"
          else
            "sqlite:blue_hydra.db"
          end

DataMapper.setup(:default, db_path)

# Helpful Errors to raise in specific cased.
# TODO perhaps extend and move into another file
class FailedThreadError < StandardError; end
class BtmonExitedError < StandardError; end

# Primary
module BlueHydra
  # 0.0.1 first stable verison
  # 0.0.2 timestamps, feedback loop for info scans, l2ping
  # 0.1.0 first working version with frozen models for pulse
  # 1.0.0 many refactors, already in stable sensor release as per 1.7.2
  VERSION = '1.0.0'

  # Config file located in /opt/pwnix/pwnix-config/blue_hydra.json on sensors
  # or in the local directory if run on a non-Pwnie device.
  CONFIG_FILE = if Dir.exists?('/opt/pwnix/pwnix-config')
              '/opt/pwnix/pwnix-config/blue_hydra.json'
            else
              File.expand_path('../../blue_hydra.json', __FILE__)
            end

  # Default configuration values
  #
  # Note: "file" can also be set but has no default value
  DEFAULT_CONFIG = {
    log_level:         "info",
    bt_device:         "hci0",       # change for external ud100
    info_scan_rate:    60,           # 1 minute in seconds
    file:              false         # if set will read from file, not hci dev
  }

  # Create config file with defaults if missing or load and update.
  @@config = if File.exists?(CONFIG_FILE)
               DEFAULT_CONFIG.merge(JSON.parse(
                 File.read(CONFIG_FILE),
                 symbolize_names: true
               ))
             else
               File.write(CONFIG_FILE, JSON.generate(DEFAULT_CONFIG))
               DEFAULT_CONFIG
             end

  # Logs will be written to /var/log/pwnix/blue_hydra.log on a sensor or
  # in the local directory as blue_hydra.log if on a non-Pwnie system
  LOGFILE = if Dir.exists?('/var/log/pwnix')
              File.expand_path('/var/log/pwnix/blue_hydra.log', __FILE__)
            else
              File.expand_path('../../blue_hydra.log', __FILE__)
            end

  # TODO convert to safe logger
  #
  # set log level from config
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

  # expose the logger as a module function
  def logger
    @@logger
  end

  # expose the config as  module function
  def config
    @@config
  end

  def daemon_mode
    @@daemon_mode ||= false
  end

  def no_pulse
    @@no_pulse ||= false
  end

  def daemon_mode=(setting)
    @@daemon_mode = setting
  end

  def no_pulse=(setting)
    @@no_pulse = setting
  end

  module_function :logger, :config, :daemon_mode, :daemon_mode=, :no_pulse,
                  :no_pulse=
end

# require the code
require 'blue_hydra/btmon_handler'
require 'blue_hydra/parser'
require 'blue_hydra/chunker'
require 'blue_hydra/runner'
require 'blue_hydra/command'
require 'blue_hydra/device'
require 'blue_hydra/cli_user_interface'
require 'blue_hydra/cli_user_interface_tracker'

BlueHydra::LOCAL_ADAPTER_ADDRESS = BlueHydra::Command.execute3(
  "hciconfig #{BlueHydra.config[:bt_device]}")[:stdout].scan(
    /((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})/i
  ).flatten.first

# DB Migration and upgrade logic
begin
  begin
    # Upgrade the db..
    DataMapper.auto_upgrade!
  rescue DataObjects::ConnectionError
    # in the case of an invalid / blank/ corrupt DB file we will back up the old
    # file and then create a new db to proceed.
    db_file = Dir.exist?('/opt/pwnix/') ?  "/opt/pwnix/blue_hydra.db" : "blue_hydra.db"
    BlueHydra.logger.error("#{db_file} is not valid. Backing up to #{db_file}.corrupt and recreating...")
    File.rename(db_file, "#{db_file}.corrupt")   #=> 0

    # TODO send message to pulse offline all clients if the above scenario
    # happened.
    DataMapper.auto_upgrade!
  end

  DataMapper.finalize

  # massive speed up of sqlite by using in memory journal, this results in an
  # increased potential of corrupted DBs so the above code is used to protect
  # against that.
  DataMapper.repository.adapter.select('PRAGMA synchronous = OFF')
  DataMapper.repository.adapter.select('PRAGMA journal_mode = MEMORY')
rescue => e
  BlueHydra.logger.error("#{e.class}: #{e.message}")
  e.backtrace.each do |line|
    BlueHydra.logger.error(line)
  end
  exit 1
end
