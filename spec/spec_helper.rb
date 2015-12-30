# encoding: UTF-8
require 'rubygems'
require 'rspec'
require 'pry'

$:.unshift(File.dirname(File.expand_path('../../lib/px_realtime_bluetooth.rb',__FILE__)))

require 'px_realtime_bluetooth'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
end

