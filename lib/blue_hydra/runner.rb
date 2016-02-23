module BlueHydra
  class Runner

    attr_accessor :command,
                  :raw_queue,
                  :chunk_queue,
                  :result_queue,
                  :btmon_thread,
                  :discovery_thread,
                  :ubertooth_thread,
                  :chunker_thread,
                  :parser_thread,
                  :cui_status,
                  :cui_thread,
                  :info_scan_queue,
                  :query_history,
                  :scanner_status,
                  :l2ping_queue,
                  :result_thread

    if BlueHydra.config[:file]
      if BlueHydra.config[:file] =~ /\.xz$/
        @@command = "xzcat #{BlueHydra.config[:file]}"
      else
        @@command = "cat #{BlueHydra.config[:file]}"
      end
    else
      @@command = "btmon -T -i #{BlueHydra.config[:bt_device]}"
    end

    def start(command=@@command)
      begin
        BlueHydra.logger.info("Runner starting with '#{command}' ...")

        # mark hosts as 'offline' if we haven't seen for a while
        BlueHydra.logger.info("Marking older devices as 'offline'...")
        BlueHydra::Device.all(classic_mode: true, status: "online").select{|x|
          x.last_seen < (Time.now.to_i - (15*60))
        }.each{|device|
          device.status = 'offline'
          device.save
        }
        BlueHydra::Device.all(le_mode: true, status: "online").select{|x|
          x.last_seen < (Time.now.to_i - (60*3))
        }.each{|device|
          device.status = 'offline'
          device.save
        }

        BlueHydra.logger.info("Syncing all hosts to Pulse...")
        BlueHydra::Device.all.each do |dev|
          dev.sync_to_pulse(true)
        end

        self.query_history   = {}
        self.command         = command
        self.raw_queue       = Queue.new
        self.chunk_queue     = Queue.new
        self.result_queue    = Queue.new
        self.info_scan_queue = Queue.new
        self.l2ping_queue    = Queue.new

        start_btmon_thread
        self.scanner_status  = {}
        self.cui_status      = {}
        start_discovery_thread unless BlueHydra.config[:file]
        start_chunker_thread
        start_parser_thread
        start_result_thread

        unless BlueHydra.config[:file]
          # Handle ubertooth
          @ubertooth_supported = false
          if system("ubertooth-util -v > /dev/null 2>&1") && ::File.executable?("/usr/bin/ubertooth-scan")
            @ubertooth_supported = true
            start_ubertooth_thread
          end
        end

        start_cui_thread unless BlueHydra.daemon_mode

        sleep 5 # allow it start up

      rescue => e
        BlueHydra.logger.error("Runner master thread: #{e.message}")
        e.backtrace.each do |x|
          BlueHydra.logger.error("#{x}")
        end
      end
    end

    def status
      x = {
        raw_queue:         self.raw_queue.length,
        chunk_queue:       self.chunk_queue.length,
        result_queue:      self.result_queue.length,
        info_scan_queue:   self.info_scan_queue.length,
        l2ping_queue:      self.l2ping_queue.length,
        btmon_thread:      self.btmon_thread.status,
        chunker_thread:    self.chunker_thread.status,
        parser_thread:     self.parser_thread.status,
        result_thread:     self.result_thread.status
      }

      unless BlueHydra.config[:file]
        x[:discovery_thread] = self.discovery_thread.status
        x[:ubertooth_thread] = self.ubertooth_thread.status if @ubertooth_supported
      end

      x[:cui_thread] = self.cui_thread.status unless BlueHydra.daemon_mode

      x
    end

    def stop
      BlueHydra.logger.info("Runner stopped. Exiting after clearing queue...")
      self.btmon_thread.kill # stop this first thread so data stops flowing ...

      # clear queue...
      until [nil, false].include?(result_thread.status) || [nil, false].include?(parser_thread.status) || self.result_queue.empty?
        BlueHydra.logger.info("Remaining queue depth: #{self.result_queue.length}")
        sleep 15
      end

      BlueHydra.logger.info("Queue clear! Exiting.")

      self.raw_queue       = nil
      self.chunk_queue     = nil
      self.result_queue    = nil
      self.info_scan_queue = nil
      self.l2ping_queue    = nil

      unless BlueHydra.config[:file]
        self.discovery_thread.kill
        self.ubertooth_thread.kill if self.ubertooth_thread
      end
      self.chunker_thread.kill
      self.parser_thread.kill
      self.result_thread.kill
      self.cui_thread.kill if self.cui_thread
    end

    def start_btmon_thread
      BlueHydra.logger.info("Btmon thread starting")
      self.btmon_thread = Thread.new do
        begin
          spawner = BlueHydra::BtmonHandler.new(
            self.command,
            self.raw_queue
          )
        rescue BtmonExitedError
          BlueHydra.logger.error("Btmon thread exiting...")
        rescue => e
          BlueHydra.logger.error("Btmon thread #{e.message}")
          e.backtrace.each do |x|
            BlueHydra.logger.error("#{x}")
          end
        end
      end
    end

    def start_discovery_thread
      BlueHydra.logger.info("Discovery thread starting")
      self.discovery_thread = Thread.new do
        begin

          discovery_command = "#{File.expand_path('../../../bin/test-discovery', __FILE__)} -i #{BlueHydra.config[:bt_device]}"

          loop do
            begin

              # clear queues
              until info_scan_queue.empty? && l2ping_queue.empty?
                # clear out entire info scan queue
                until info_scan_queue.empty?
                  BlueHydra.logger.debug("Popping off info scan queue. Depth: #{ info_scan_queue.length}")
                  BlueHydra::Command.execute3("hciconfig #{BlueHydra.config[:bt_device]} reset")
                  command = info_scan_queue.pop
                  case command[:command]
                  when :info
                    BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config[:bt_device]} info #{command[:address]}")
                  when :leinfo
                    BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config[:bt_device]} leinfo #{command[:address]}")
                  else
                    BlueHydra.logger.error("Invalid command detected... #{command.inspect}")
                  end
                end
                # run 1 l2ping a time while still checking if info scan queue
                # is empty
                unless l2ping_queue.empty?
                  command = l2ping_queue.pop
                  BlueHydra::Command.execute3("l2ping -c 3 -i #{BlueHydra.config[:bt_device]} #{command[:address]}")
                end
              end

              # interface reset
              interface_reset = BlueHydra::Command.execute3("hciconfig #{BlueHydra.config[:bt_device]} reset")[:stderr]
              if interface_reset
                BlueHydra.logger.error("Error with hciconfig #{BlueHydra.config[:bt_device]} reset..")
                interface_reset.split("\n").each do |ln|
                  BlueHydra.logger.error(ln)
                end
              end

              # hot loop avoidance, but run right before discovery to avoid any delay between discovery and info scan
              sleep 1

              # run test-discovery
              # do a discovery
              self.scanner_status[:test_discovery] = Time.now.to_i unless BlueHydra.daemon_mode
              discovery_errors = BlueHydra::Command.execute3(discovery_command)[:stderr]
              last_discover_time = Time.now.to_i
              if discovery_errors
                BlueHydra.logger.error("Error with test-discovery script..")
                discovery_errors.split("\n").each do |ln|
                  BlueHydra.logger.error(ln)
                end
              end

            rescue => e
              BlueHydra.logger.error("Discovery loop crashed: #{e.message}")
              e.backtrace.each do |x|
                BlueHydra.logger.error("#{x}")
              end
              BlueHydra.logger.error("Sleeping 20s...")
              sleep 20
            end
          end
        rescue => e
          BlueHydra.logger.error("Discovery thread #{e.message}")
          e.backtrace.each do |x|
            BlueHydra.logger.error("#{x}")
          end
        end
      end
    end

    def start_ubertooth_thread
      BlueHydra.logger.info("Ubertooth thread starting")
      self.ubertooth_thread = Thread.new do
        begin
          loop do
            begin
              # Do a scan with ubertooth
              ubertooth_reset = BlueHydra::Command.execute3("ubertooth-util -r")
              if ubertooth_reset[:stderr]
                BlueHydra.logger.error("Error with ubertooth-util -r...")
                ubertooth_reset.split("\n").each do |ln|
                  BlueHydra.logger.error(ln)
                end
              end

              self.scanner_status[:ubertooth] = Time.now.to_i unless BlueHydra.daemon_mode
              ubertooth_output = BlueHydra::Command.execute3("ubertooth-scan -t 40",60)
              last_ubertooth_time = Time.now.to_i
              if ubertooth_output[:stderr]
                BlueHydra.logger.error("Error with ubertooth_scan..")
                ubertooth_output[:stderr].split("\n").each do |ln|
                  BlueHydra.logger.error(ln)
                end
              else
                ubertooth_output[:stdout].each_line do |line|
                  if line =~ /^[\?:]{6}[0-9a-f:]{11}/i
                    address = line.scan(/^((\?\?:){2}([0-9a-f:]*))/i).flatten.first.gsub('?', '0')

                    result_queue.push({
                      address: [address],
                      last_seen: [Time.now.to_i]
                    })

                    push_to_queue(:classic, address)
                  end
                end
              end

              # scan with ubertooth for 40 seconds, sleep for 1, reset, repeat
              sleep 1
            end
          end
        end
      end
    end

    def start_cui_thread
      BlueHydra.logger.info("Command Line UI thread starting")
      self.cui_thread = Thread.new do
        #this is only to cut down on ram usage really, so 5 minutes seems reasonably sane
        cui_timeout = 300
        l2ping_threshold = (cui_timeout - 45)

        puts "\e[H\e[2J"

        help =  <<HELP
Welcome to \e[34;1mBlue Hydra\e[0m

This will display live information about Bluetooth devices seen in the area.
Devices in this display will time out after #{cui_timeout}s but will still be
available in the BlueHydra Database or synced to pulse if you chose that
option.  #{ BlueHydra.config[:file] ? "\n\nReading data from " + BlueHydra.config[:file]  + '.' : '' }

The "VERS" column in the following table shows mode and version if available
	C/BR = Classic mode
        4.0C = Classic mode, version 4.0
        btle = Bluetooth Low Energy mode (4.0 and higher only)

press [Enter] key to continue....
HELP

        puts help

        gets.chomp

        loop do
          begin

            unless BlueHydra.config[:file]
              if self.scanner_status[:test_discovery]
                discovery_time = Time.now.to_i - self.scanner_status[:test_discovery]
             else
                discovery_time = "not started"
              end

              if self.ubertooth_thread
                if self.scanner_status[:ubertooth]
                  ubertooth_time = Time.now.to_i - self.scanner_status[:ubertooth]
                else
                  ubertooth_time = "not started"
                end
              else
                ubertooth_time = "not enabled"
              end
            end

            pbuff = ""
            max_height = `tput lines`.chomp.to_i
            lines = 1

            pbuff << "\e[H\e[2J"

            pbuff << "\e[34;1mBlue Hydra\e[0m :"
            if BlueHydra.config[:file]
              pbuff <<  " Devices Seen in last #{cui_timeout}s"
            end
            pbuff << "\n"
            lines += 1

            pbuff << "Queue status: result_queue: #{self.result_queue.length}, info_scan_queue: #{self.info_scan_queue.length}, l2ping_queue: #{self.l2ping_queue.length}\n"
            lines += 1

            unless BlueHydra.config[:file]
              pbuff <<  "Discovery status timers: #{discovery_time}, ubertooth status: #{ubertooth_time}\n"
              lines += 1
            end

            max_lengths = Hash.new(0)

            printable_keys = [
              :_seen, :vers, :address, :rssi, :name, :manuf, :type
            ]

            justifications = {
              _seen: :right,
              rssi:  :right
            }

            cui_status.keys.select{|x| cui_status[x][:last_seen] < (Time.now.to_i - cui_timeout)}.each{|x| cui_status.delete(x)} unless BlueHydra.config[:file]

            unless cui_status.empty?
              cui_status.values.each do |hsh|
                hsh[:_seen] = " +#{Time.now.to_i - hsh[:last_seen]}s"
                printable_keys.each do |key|
                  key_length = key.to_s.length
                  if v = hsh[key].to_s
                    if v.length > max_lengths[key]
                      if v.length > key_length
                        max_lengths[key] = v.length
                      else
                        max_lengths[key] = key_length
                      end
                    end
                  end
                end
              end

              keys = printable_keys.select{|k| max_lengths[k] > 0}
              header = keys.map{|k| k.to_s.ljust(max_lengths[k]).gsub("_"," ")}.join(' | ').upcase

              pbuff << "\e[0;4m#{header}\e[0m\n"
              lines += 1

              d = cui_status.values.sort_by{|x| x[:last_seen]}.reverse
              d.each do |data|

                #prevent classic devices from expiring by forcing them onto the l2ping queue
                unless  data[:vers] == "btle"
                  ping_time = (Time.now.to_i - l2ping_threshold)
                  self.query_history[data[:address]] ||= {}
                  if (self.query_history[data[:address]][:l2ping].to_i < ping_time) && (data[:last_seen] < ping_time)
                    l2ping_queue.push({
                      command: :l2ping,
                      address: data[:address]
                    })

                    self.query_history[data[:address]][:l2ping] = Time.now.to_i
                  end
                end

                next if lines >= max_height

                color = case
                        when data[:created] > Time.now.to_i - 10  # in last 10 seconds
                          "\e[0;32m" # green
                        when data[:created] > Time.now.to_i - 30  # in last 30 seconds
                          "\e[0;33m" # yellow
                        when data[:last_seen] < (Time.now.to_i - cui_timeout + 20) # within 20 seconds expiring
                          "\e[0;31m" # red
                        else
                          ""
                        end

                x = keys.map do |k|
                  if data[k]
                    if justifications[k] == :right
                      data[k].to_s.rjust(max_lengths[k])
                    else
                      data[k].to_s.ljust(max_lengths[k])
                    end
                  else
                    ''.ljust(max_lengths[k])
                  end
                end
                pbuff <<  "#{color}#{x.join(' | ')}\e[0m\n"
                lines += 1
              end
            else
              pbuff <<  "No recent devices..."
            end

            puts pbuff

            sleep 0.1
          rescue => e
            BlueHydra.logger.error("CUI thread #{e.message}")
            e.backtrace.each do |x|
              BlueHydra.logger.error("#{x}")
            end
          end
        end
      end
    end

    def push_to_queue(mode, address)
      case mode
      when :classic
        command = :info
        # use uap_lap for tracking classic devices
        track_addr = address.split(":")[2,4].join(":")

        return if track_addr == BlueHydra::LOCAL_ADAPTER_ADDRESS.split(":")[2,4].join(":")
      when :le
        command = :leinfo
        track_addr = address

        return if address == BlueHydra::LOCAL_ADAPTER_ADDRESS
      end

      self.query_history[track_addr] ||= {}
      last_info = self.query_history[track_addr][mode].to_i
      if (Time.now.to_i - (BlueHydra.config[:info_scan_rate].to_i * 60)) >= last_info
        info_scan_queue.push({command: command, address: address})
        self.query_history[track_addr][mode] = Time.now.to_i
      end
    end

    def start_chunker_thread
      BlueHydra.logger.info("Chunker thread starting")
      self.chunker_thread = Thread.new do
        loop do
          begin
            chunker = BlueHydra::Chunker.new(
              self.raw_queue,
              self.chunk_queue
            )
            chunker.chunk_it_up
          rescue => e
            BlueHydra.logger.error("Chunker thread #{e.message}")
            e.backtrace.each do |x|
              BlueHydra.logger.error("#{x}")
            end
            BlueHydra.logger.warn("Restarting Chunker...")
          end
          sleep 1
        end
      end
    end

    def start_parser_thread
      BlueHydra.logger.info("Parser thread starting")
      self.parser_thread = Thread.new do
        begin

          scan_results = {}

          while chunk = chunk_queue.pop do
            p = BlueHydra::Parser.new(chunk.dup)
            p.parse
            attrs = p.attributes

            address = (attrs[:address]||[]).uniq.first

            if address

              unless BlueHydra.daemon_mode
                cui_status[address] ||= {created: Time.now.to_i}
                cui_status[address][:lap] = address.split(":")[3,3].join(":") unless cui_status[address][:lap]

                if chunk[0] && chunk[0][0]
                  bt_mode = chunk[0][0] =~ /^\s+LE/ ? "le" : "classic"
                end

                if bt_mode == "le"
                  cui_status[address][:vers] = "btle"
                else
                  if attrs[:lmp_version]
                    cui_status[address][:vers] = "#{attrs[:lmp_version].first.split(" ")[1]}C"
                  elsif !cui_status[address][:vers]
                    cui_status[address][:vers] = "C/BR"
                  end
                end

                [
                  :last_seen, :name, :address, :classic_rssi, :le_rssi
                ].each do |key|
                  if attrs[key] && attrs[key].first
                    if cui_status[address][key] != attrs[key].first
                      if key == :le_rssi || key == :classic_rssi
                        cui_status[address][:rssi] = attrs[key].first[:rssi].gsub('dBm','')
                      else
                        cui_status[address][key] = attrs[key].first
                      end
                    end
                  end
                end

                if attrs[:short_name]
                  unless attrs[:short_name] == [nil] || cui_status[address][:name]
                    cui_status[address][:name] = attrs[:short_name]
                    BlueHydra.logger.warn("short name found: #{attrs[:short_name]}")
                  end
                end

                if attrs[:appearance]
                  cui_status[address][:type] = attrs[:appearance].first.split('(').first
                end

                if attrs[:classic_minor_class]
                  if attrs[:classic_minor_class].first =~ /Uncategorized/i
                    cui_status[address][:type] = "Uncategorized"
                  else
                    cui_status[address][:type] = attrs[:classic_minor_class].first.split('(').first
                  end
                end

                if bt_mode == "classic" || (attrs[:le_address_type] && attrs[:le_address_type].first =~ /public/i)
                  unless cui_status[address][:manuf]
                    vendor = Louis.lookup(address)

                    cui_status[address][:manuf] = if vendor["short_vendor"]
                                                    vendor["short_vendor"]
                                                  else
                                                    vendor["long_vendor"]
                                                  end
                  end
                else
                  cmp = nil

                  if attrs[:company_type] && attrs[:company_type].first !~ /unknown/i
                    cmp = attrs[:company_type].first
                  elsif attrs[:company] && attrs[:company].first !~ /not assigned/i
                      cmp = attrs[:company].first
                  else
                      cmp = "Unknown"
                  end

                  if cmp
                    cui_status[address][:manuf] = cmp.split('(').first
                  end
                end
              end

              if scan_results[address]
                needs_push = false

                attrs.each do |k,v|

                  unless [:last_seen, :le_rssi, :classic_rssi].include? k

                    unless attrs[k] == scan_results[address][k]
                      scan_results[address][k] = v
                      needs_push = true
                    end

                  else
                    case
                    when k == :last_seen
                      if (attrs[k].first - 600) >= scan_results[address][k].first
                        scan_results[address][k] = attrs[k]
                        needs_push = true
                      end
                    when [:le_rssi, :classic_rssi].include?(k)
                      #   => [{:t=>1452952885, :rssi=>"-51 dBm"}]
                      threshold_time = attrs[k][0][:t] - 60
                      last_seen_time = (scan_results[address][k][0][:t] rescue 0)

                      if threshold_time > last_seen_time
                        # BlueHydra.logger.debug("syncing #{k} for #{address} last sync was #{attrs[k][0][:t] - last_seen_time}s ago...")
                        scan_results[address][k] = attrs[k]
                        needs_push = true
                      end
                    end
                  end
                end

                if needs_push
                  result_queue.push(p.attributes)
                end
              else
                scan_results[address] = attrs
                result_queue.push(p.attributes)
              end

            end

          end
        rescue => e
          BlueHydra.logger.error("Parser thread #{e.message}")
          e.backtrace.each do |x|
            BlueHydra.logger.error("#{x}")
          end
        end
      end
    end

    def start_result_thread
      BlueHydra.logger.info("Result thread starting")
      self.result_thread = Thread.new do
        begin

          #debugging
          maxdepth = 0

          last_status_sync = Time.now.to_i

          loop do

            unless BlueHydra.config[:file]
              # if their last_seen value is > 7 minutes ago and not > 15 minutes ago
              #   l2ping them :  "l2ping -c 3 result[:address]"
              BlueHydra::Device.all(classic_mode: true).select{|x|
                x.last_seen < (Time.now.to_i - (60 * 7)) && x.last_seen > (Time.now.to_i - (60*15))
              }.each do |device|
                self.query_history[device.address] ||= {}
                if (Time.now.to_i - (60 * 7)) >= self.query_history[device.address][:l2ping].to_i

                  # BlueHydra.logger.debug("device l2ping scan triggered")
                  l2ping_queue.push({
                    command: :l2ping,
                    address: device.address
                  })

                  self.query_history[device.address][:l2ping] = Time.now.to_i
                end
              end
            end

            until result_queue.empty?
              if BlueHydra.daemon_mode
                queue_depth = result_queue.length
                if queue_depth > 250
                  if (maxdepth < queue_depth)
                    maxdepth = result_queue.length
                    BlueHydra.logger.warn("Popping off result queue. Max Depth: #{maxdepth} and rising")
                  else
                    BlueHydra.logger.warn("Popping off result queue. Max Depth: #{maxdepth} Currently: #{queue_depth}")
                  end
                end
              end

              result = result_queue.pop
              if result[:address]
                device = BlueHydra::Device.update_or_create_from_result(result)

                unless BlueHydra.config[:file]
                  if device.le_mode
                    push_to_queue(:le, device.address)
                  end

                  if device.classic_mode
                    push_to_queue(:classic, device.address)
                  end
                end

              else
                BlueHydra.logger.warn("Device without address #{JSON.generate(result)}")
              end
            end

            BlueHydra::Device.all(classic_mode: true, status: "online").select{|x|
              x.last_seen < (Time.now.to_i - (15*60))
            }.each{|device|
              device.status = 'offline'
              device.save
            }

            BlueHydra::Device.all(le_mode: true, status: "online").select{|x|
              x.last_seen < (Time.now.to_i - (60*3))
            }.each{|device|
              device.status = 'offline'
              device.save
            }

            if (Time.now.to_i - BlueHydra.config[:status_sync_rate]) > start_time
              BlueHydra.logger.info("Syncing all hosts to Pulse...")
              BlueHydra::Device.all.each do |dev|
                dev.instance_variable_set(:@filthy_attributes, [:status])
                dev.sync_to_pulse(false)
              end
            end

            sleep 1
          end

        rescue => e
          BlueHydra.logger.error("Result thread #{e.message}")
          e.backtrace.each do |x|
            BlueHydra.logger.error("#{x}")
          end
        end
      end

    end
  end
end
