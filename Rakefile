$:.unshift(File.dirname(File.expand_path('../lib/blue_hydra.rb',__FILE__)))
require 'blue_hydra'
require 'pry'

desc "Print the version."
task "version" do
  puts BlueHydra::VERSION
end

desc "Sync all records to pulse"
task "sync_all" do 
  BlueHydra::Device.all.each do |dev|
    puts "Syncing #{dev.address}" 
    dev.sync_to_pulse(true)
  end
end

desc "BlueHydra Console"
task "console" do 
  binding.pry
end

desc "Summarize Devices"
task "summary" do
  BlueHydra::Device.all.each do |dev|
    puts "Device -- #{dev.address}"
    dev.attributes.each do |name, val|
      next if [:address, :classic_rssi, :le_rssi].include?(name)
      if %w{ 
          classic_features le_features le_flags classic_channels
          le_16_bit_service_uuids classic_16_bit_service_uuids
          le_128_bit_service_uuids classic_128_bit_service_uuids classic_class
          le_rssi classic_rssi primary_services
        }.map(&:to_sym).include?(name)
          unless val == '[]' || val == nil
            puts "  #{name}:"
            JSON.parse(val).each do |v|
              puts "    #{v}"
            end
          end
      else
        unless val == nil
          puts "  #{name}: #{val}"
        end
      end
    end
  end
end

