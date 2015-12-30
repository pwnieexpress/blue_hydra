require 'pty'
require 'logger'
require 'json'

$:.unshift(File.dirname(__FILE__))

module PxRealtimeBluetooth
  VERSION = '0.0.1'
  LOGFILE = File.expand_path('../../px_realtime_bluetooth.log', __FILE__)

  @@logger = Logger.new(LOGFILE)
  @@logger.level = Logger::DEBUG

  def logger
    @@logger
  end

  module_function :logger
end

require 'px_realtime_bluetooth/pty_spawner'
require 'px_realtime_bluetooth/parser'
require 'px_realtime_bluetooth/chunker'
require 'px_realtime_bluetooth/runner'

