$:.unshift(File.dirname(File.expand_path('../lib/blue_hydra.rb',__FILE__)))
require 'blue_hydra'
require 'pry'

desc "Print the version."
task "version" do
  puts BlueHydra::VERSION
end

desc "Summarize Devices"
task "summary" do
  BlueHydra::Device.all.each do |dev|
    puts "Device -- #{dev.address}"
    dev.attributes.each do |name, val|
      next if name == :address
      if %w{ 
          classic_16_bit_service_uuids
          le_16_bit_service_uuids 
          classic_class 
        }.map(&:to_sym).include?(name)
          unless val == '[]'
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

