# Core Libs
require 'pty'
require 'logger'
require 'json'
require 'open3'
require 'securerandom'
require 'zlib'
require 'yaml'
require 'fileutils'
require 'socket'

# Gems
require 'dm-migrations'
require 'dm-timestamps'
require 'dm-validations'

# Add to Load Path
$:.unshift(File.dirname(__FILE__))

# Helpful Errors to raise in specific cased.
class BluetoothdDbusError < StandardError; end
class BluezNotReadyError < StandardError; end
class FailedThreadError < StandardError; end
class BtmonExitedError < StandardError; end

# Primary
module BlueHydra
  # 0.0.1 first stable verison
  # 0.0.2 timestamps, feedback loop for info scans, l2ping
  # 0.1.0 first working version with frozen models for Pwn Pulse
  # 1.0.0 many refactors, already in stable sensor release as per 1.7.2
  # 1.1.0 CUI, readability refactor, many small improvements
  # 1.1.1 Range monitoring based on TX power, OSS cleanup
  # 1.1.2 Add pulse reset
  # 1.2.0 drop status sync, restart will use a reset message to reset statuses if we miss both the original message and the daily changed syncs
  VERSION = '1.2.0'

  # Config file located in /opt/pwnix/pwnix-config/blue_hydra.yml on sensors
  # or in the local directory if run on a non-Pwnie device.
  LEGACY_CONFIG_FILE = if Dir.exists?('/opt/pwnix/pwnix-config')
              '/opt/pwnix/pwnix-config/blue_hydra.json'
            else
              File.expand_path('../../blue_hydra.json', __FILE__)
            end

  # Config file located in /opt/pwnix/pwnix-config/blue_hydra.yml on sensors
  # or in the local directory if run on a non-Pwnie device.
  CONFIG_FILE = if Dir.exists?('/opt/pwnix/data/blue_hydra')
              '/opt/pwnix/data/blue_hydra/blue_hydra.yml'
            else
              File.expand_path('../../blue_hydra.yml', __FILE__)
            end

  # Default configuration values
  #
  # Note: "file" can also be set but has no default value
  DEFAULT_CONFIG = {
    "log_level"          => "info",
    "bt_device"          => "hci0",       # change for external ud100
    "info_scan_rate"     => 240,          # 4 minutes in seconds
    "btmon_log"          => false,        # if set will write used btmon output to a log file
    "btmon_rawlog"       => false,        # if set will write raw btmon output to a log file
    "file"               => false,        # if set will read from file, not hci dev
    "rssi_log"           => false,        # if set will log rssi
    "aggressive_rssi"    => false,        # if set will sync all rssi to pulse
    "ui_filter_mode"     => :disabled,    # default ui filter mode to start in
    "ui_inc_filter_mac"  => [],           # inclusive ui filter by mac
    "ui_inc_filter_prox" => [],           # inclusive ui filter by prox uuid / major /minor
    "signal_spitter"     => false,        # make raw signal strength api available on localhost:1124
    "chunker_debug"      => false
  }

  if File.exists?(LEGACY_CONFIG_FILE)
    old_config = JSON.parse(
      File.read(LEGACY_CONFIG_FILE)
    )
    File.unlink(LEGACY_CONFIG_FILE)
  else
    old_config = {}
  end

  config_base = DEFAULT_CONFIG.merge(old_config)

  # Create config file with defaults if missing or load and update.
  @@config = if File.exists?(CONFIG_FILE)
               config_base.merge(YAML.load(File.read(CONFIG_FILE)))
             else
               config_base
             end

  # update the config file with any new values not present, will leave
  # configured values intact but should allow users to pull code changes with
  # new config options and have them show up in the file after running
  File.write(CONFIG_FILE, @@config.to_yaml.gsub("---\n",''))

  # Logs will be written to /var/log/pwnix/blue_hydra.log on a sensor or
  # in the local directory as blue_hydra.log if on a non-Pwnie system
  LOGFILE = if Dir.exists?('/var/log/pwnix')
              File.expand_path('/var/log/pwnix/blue_hydra.log', __FILE__)
            else
              File.expand_path('../../blue_hydra.log', __FILE__)
            end

  # override logger which does nothing
  class NilLogger
    # nil! :)
    def initialize;     end
    def level=(lvl);    end
    def fatal(msg);     end
    def error(msg);     end
    def warn(msg);      end
    def info(msg);      end
    def debug(msg);     end
    def formatter=(fm); end
  end

  def self.initialize_logger
    # set log level from config
    @@logger = if @@config["log_level"]
                 Logger.new(LOGFILE)
               else
                 NilLogger.new
               end
    @@logger.level = Logger::DEBUG
  end

  def self.update_logger
    @@logger.level = case @@config["log_level"]
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
  end

  initialize_logger
  update_logger


  # the RSSI log will only get used if the appropriate config value is set
  #
  # Logs will be written to /var/log/pwnix/blue_hydra_rssi.log on a sensor or
  # in the local directory as blue_hydra_rssi.log if on a non-Pwnie system
  RSSI_LOGFILE = if Dir.exists?('/var/log/pwnix')
              File.expand_path('/var/log/pwnix/blue_hydra_rssi.log', __FILE__)
            else
              File.expand_path('../../blue_hydra_rssi.log', __FILE__)
            end

  @@rssi_logger = if @@config["log_level"]
                    Logger.new(RSSI_LOGFILE)
                  else
                    NilLogger.new
                  end
  @@rssi_logger.level = Logger::INFO

  # we dont want logger formatting here, the code defines what we want these
  # lines to be
  @@rssi_logger.formatter = proc {|s,d,p,m| "#{m}\n"}

  # the chunk log will only get used if the appropriate config value is set
  #
  # Logs will be written to /var/log/pwnix/blue_hydra_chunk.log on a sensor or
  # in the local directory as blue_hydra_chunk.log if on a non-Pwnie system
  CHUNK_LOGFILE = if Dir.exists?('/var/log/pwnix')
              File.expand_path('/var/log/pwnix/blue_hydra_chunk.log', __FILE__)
            else
              File.expand_path('../../blue_hydra_chunk.log', __FILE__)
            end

  @@chunk_logger = if @@config["log_level"]
                    Logger.new(CHUNK_LOGFILE)
                  else
                    NilLogger.new
                  end
  @@chunk_logger.level = Logger::INFO

  # we dont want logger formatting here, the code defines what we want these
  # lines to be
  @@chunk_logger.formatter = proc {|s,d,p,m| "#{m}\n"}

  # expose the logger as a module function
  def logger
    @@logger
  end

  # expose the logger as a module function
  def rssi_logger
    @@rssi_logger
  end

  # expose the logger as a module function
  def chunk_logger
    @@chunk_logger
  end

  # expose the config as  module function
  def config
    @@config
  end

  # getter for daemon mode option
  def daemon_mode
    @@daemon_mode ||= false
  end

  # setter for daemon mode option
  def daemon_mode=(setting)
    @@daemon_mode = setting
  end

  # getter for demo mode option
  def demo_mode
    @@demo_mode ||= false
  end

  # setter for demo mode option
  def demo_mode=(setting)
    @@demo_mode = setting
  end

  # getter for pulse option
  def pulse
    @@pulse ||= false
  end

  # setter for pulse mode option
  def pulse=(setting)
    @@pulse = setting
  end

  # setter/getter/better
  def pulse_debug
    @@pulse_debug ||= false
  end
  def pulse_debug=(setting)
    @@pulse_debug = setting
  end

  def no_db
    @@no_db ||= false
  end

  def no_db=(setting)
    @@no_db = setting
  end

  def signal_spitter
    @@signal_spitter ||= false
  end

  def signal_spitter=(setting)
    @@signal_spitter = setting
  end

  module_function :logger, :config, :daemon_mode, :daemon_mode=, :pulse,
                  :pulse=, :rssi_logger, :demo_mode, :demo_mode=,
                  :pulse_debug, :pulse_debug=, :no_db, :no_db=,
                  :signal_spitter, :signal_spitter=, :chunk_logger
end

# require the actual code
require 'blue_hydra/btmon_handler'
require 'blue_hydra/parser'
require 'blue_hydra/pulse'
require 'blue_hydra/pulsetracker'
require 'blue_hydra/chunker'
require 'blue_hydra/runner'
require 'blue_hydra/command'
require 'blue_hydra/device'
require 'blue_hydra/sync_version'
require 'blue_hydra/cli_user_interface'
require 'blue_hydra/cli_user_interface_tracker'

# Here we enumerate the local hci adapter hardware address and make it
# available as an internal value

BlueHydra::EnumLocalAddr = Proc.new do
  BlueHydra::Command.execute3(
    "hciconfig #{BlueHydra.config["bt_device"]}")[:stdout].scan(
      /((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})/i
    ).flatten
end

begin
  BlueHydra::LOCAL_ADAPTER_ADDRESS = BlueHydra::EnumLocalAddr.call.first
rescue
  if ENV["BLUE_HYDRA"] == "test"
    BlueHydra::LOCAL_ADAPTER_ADDRESS = "JE:NK:IN:SJ:EN:KI"
    puts "Failed to find mac address for #{BlueHydra.config["bt_device"]}, faking for tests"
  else
    msg = "Unable to read the mac address from #{BlueHydra.config["bt_device"]}"
    BlueHydra::Pulse.send_event("blue_hydra", {
      key:       'blue_hydra_bt_device_mac_read_error',
      title:     "Blue Hydra cant read mac from BT device #{BlueHydra.config["bt_device"]}",
      message:   msg,
      severity:  'FATAL'
    })
    BlueHydra.logger.error(msg)
    puts msg unless BlueHydra.daemon_mode
    exit 1
  end
end


# set all String properties to have a default length of 255
DataMapper::Property::String.length(255)

LEGACY_DB_PATH   = '/opt/pwnix/blue_hydra.db'
DATA_DIR         = '/opt/pwnix/data'
DB_DIR           = File.join(DATA_DIR, 'blue_hydra')
DB_NAME          = 'blue_hydra.db'
DB_PATH          = File.join(DB_DIR, DB_NAME)

if Dir.exists?(DATA_DIR)
  unless Dir.exists?(DB_DIR)
    Dir.mkdir(DB_DIR)
  end
end

if File.exists?(LEGACY_DB_PATH) && Dir.exists?(DB_DIR)
  FileUtils.mv(LEGACY_DB_PATH, DB_PATH) unless File.exists?(DB_PATH)
end


# The database will be stored in /opt/pwnix/blue_hydra.db if we are on a system
# which the Pwnie Express chef scripts have been run. Otherwise it will attempt
# to create a sqlite db whereever the run was initiated.
#
# When running the rspec tets the BLUE_HYDRA environmental value will be set to
# 'test' and all tests should run with an in-memory db.
db_path = if ENV["BLUE_HYDRA"] == "test" || BlueHydra.no_db
            'sqlite::memory:?cache=shared'
          elsif Dir.exist?(DB_DIR)
            "sqlite:#{DB_PATH}"
          else
            "sqlite:#{DB_NAME}"
          end

# create the db file
DataMapper.setup(:default, db_path)

def brains_to_floor
  # in the case of an invalid / blank/ corrupt DB file we will back up the old
  # file and then create a new db to proceed.
  db_file = Dir.exist?('/opt/pwnix/data/blue_hydra/') ?  "/opt/pwnix/data/blue_hydra/blue_hydra.db" : "blue_hydra.db"
  BlueHydra.logger.error("#{db_file} is not valid. Backing up to #{db_file}.corrupt and recreating...")
  BlueHydra::Pulse.send_event("blue_hydra", {
    key:       'blue_hydra_db_corrupt',
    title:     'Blue Hydra DB Corrupt',
    message:   "#{db_file} is not valid. Backing up to #{db_file}.corrupt and recreating...",
    severity:  'ERROR'
  })
  File.rename(db_file, "#{db_file}.corrupt")   #=> 0
  BlueHydra.logger.fatal("Blue_Hydra needs to be restarted for this to take effect.")
  puts("Blue_Hydra needs to be restarted for this to take effect.")
  exit 1
  ## I really wish this works but it doesn't reopen the file and holds the handle on the renamed file
  #DataMapper.setup(:default, db_path)
  #DataMapper.auto_upgrade!
end

# DB Migration and upgrade logic
begin
  begin
    # Upgrade the db..
    DataMapper.auto_upgrade!
  rescue DataObjects::ConnectionError
    brains_to_floor
  end

  #okay, database doesn't appear corrupt at first glance, but let's try a little bit harder...
  we_cool = DataMapper.repository.adapter.select('PRAGMA integrity_check')
  unless we_cool == ["ok"]
    brains_to_floor
  end

  DataMapper.finalize

  # massive speed up of sqlite by using in memory journal, this results in an
  # increased potential of corrupted DBs so the above code is used to recover
  # from that.
  DataMapper.repository.adapter.select('PRAGMA synchronous = OFF')
  DataMapper.repository.adapter.select('PRAGMA journal_mode = MEMORY')
rescue => e
  BlueHydra.logger.error("#{e.class}: #{e.message}")
  log_message = ""
  e.backtrace.each do |line|
    BlueHydra.logger.error(line)
    log_message << line
  end
  BlueHydra::Pulse.send_event("blue_hydra", {
    key:       'blue_hydra_db_error',
    title:     'Blue Hydra Encountered DB Migration Error',
    message:   log_message,
    severity:  'FATAL'
  })
  exit 1
end

if BlueHydra::PulseTracker.count == 0
  BlueHydra::PulseTracker.new.init
end
BlueHydra::PULSE_TRACKER = BlueHydra::PulseTracker.first


if BlueHydra::SyncVersion.count == 0
  BlueHydra::SyncVersion.new.save
end

BlueHydra::SYNC_VERSION = BlueHydra::SyncVersion.first.version
