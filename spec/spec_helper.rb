# encoding: UTF-8
require 'rubygems'
require 'rspec'
require 'pry'

$:.unshift(File.dirname(File.expand_path('../../lib/blue_hydra.rb',__FILE__)))

require 'blue_hydra'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
end

