require 'pty'
require 'logger'
require 'json'

$:.unshift(File.dirname(__FILE__))

module BtMon
  VERSION = '0.0.1'
  LOGFILE = File.expand_path('../../btmon.log', __FILE__)

  @@logger = Logger.new(LOGFILE)
  @@logger.level = Logger::DEBUG

  def logger
    @@logger
  end

  module_function :logger
end

require 'btmon/pty_spawner'
require 'btmon/parser'
require 'btmon/chunker'
require 'btmon/runner'

