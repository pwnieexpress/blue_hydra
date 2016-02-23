# encoding: UTF-8
require 'rubygems'
require 'rspec'
require 'pry'

$:.unshift(File.dirname(File.expand_path('../../lib/blue_hydra.rb',__FILE__)))

ENV["BLUE_HYDRA"] = "test"

require 'blue_hydra'

BlueHydra.daemon_mode = true
BlueHydra.no_pulse = true

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
end

