require 'pty'
require 'logger'
require 'json'

$:.unshift(File.dirname(__FILE__))

module BlueHydra
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

