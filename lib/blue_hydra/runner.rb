module BlueHydra
  class Runner

    attr_accessor :command,
                  :raw_queue,
                  :chunk_queue,
                  :result_queue,
                  :btmon_thread,
                  :discovery_thread,
                  :chunker_thread,
                  :parser_thread,
                  :info_scan_queue,
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
        self.command         = command
        self.raw_queue       = Queue.new
        self.chunk_queue     = Queue.new
        self.result_queue    = Queue.new
        self.info_scan_queue = Queue.new
        self.l2ping_queue    = Queue.new

        start_btmon_thread
        start_discovery_thread unless BlueHydra.config[:file]
        start_chunker_thread
        start_parser_thread
        start_result_thread

      rescue => e
        BlueHydra.logger.error("Runner master thread: #{e.message}")
        e.backtrace.each do |x|
          BlueHydra.logger.error("#{x}")
        end
      end
    end

    def stop
      BlueHydra.logger.info("Runner exiting...")
      self.raw_queue       = nil
      self.chunk_queue     = nil
      self.result_queue    = nil
      self.info_scan_queue = nil
      self.l2ping_queue    = nil

      self.btmon_thread.kill
      self.discovery_thread.kill unless BlueHydra.config[:file]
      self.chunker_thread.kill
      self.parser_thread.kill
      self.result_thread.kill
    end

    def start_btmon_thread
      BlueHydra.logger.info("Btmon thread starting")
      self.btmon_thread = Thread.new do
        begin
          spawner = BlueHydra::BtmonHandler.new(
            self.command,
            self.raw_queue
          )
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
          last_discover_time = 0
          discovery_command = "#{File.expand_path('../../../bin/test-discovery', __FILE__)} -i #{BlueHydra.config[:bt_device]}"
          loop do
            begin
              if ( Time.now.to_i - last_discover_time ) > 30
                # do a discovery
                interface_reset = BlueHydra::Command.execute3("hciconfig #{BlueHydra.config[:bt_device]} reset")
                discovery_errors = BlueHydra::Command.execute3(discovery_command)[:stderr]
                last_discover_time = Time.now.to_i

                if discovery_errors
                  BlueHydra.logger.error("Error with test-discovery script..")
                  discovery_errors.split("\n").each do |ln|
                    BlueHydra.logger.error(ln)
                  end
                end
              end

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

            rescue => e
              BlueHydra.logger.error("Discovery loop crashed: #{e.message}")
              e.backtrace.each do |x|
                BlueHydra.logger.error("#{x}")
              end
              BlueHydra.logger.error("Sleeping 20s...")
              sleep 20
            end

            # sleep
            sleep 1
          end
        rescue => e
          BlueHydra.logger.error("Discovery thread #{e.message}")
          e.backtrace.each do |x|
            BlueHydra.logger.error("#{x}")
          end
        end
      end
    end

    def start_chunker_thread
      BlueHydra.logger.info("Chunker thread starting")
      self.chunker_thread = Thread.new do
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
        end
      end
    end

    def start_parser_thread
      BlueHydra.logger.info("Parser thread starting")
      self.parser_thread = Thread.new do
        begin

          scan_results = {}

          while chunk = chunk_queue.pop do
            p = BlueHydra::Parser.new(chunk)
            p.parse

            attrs = p.attributes
            address = (attrs[:address]||[]).uniq.first

            if address
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
                        # BlueHydra.logger.debug("syncing #{k} for #{address} last sync was #{attrs[k].first - scan_results[address][k].first}s ago...")
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
          query_history = {}

          #debugging
          maxdepth = 0

          loop do

            unless BlueHydra.config[:file]
              # if their last_seen value is > 15 minutes ago and not > 1 hour ago
              #   l2ping them :  "l2ping -c 3 result[:address]"
              BlueHydra::Device.all.select{|x|
                x.last_seen < (Time.now.to_i - (60 * 15)) && x.last_seen > (Time.now.to_i - (60*60))
              }.each{|device|
                query_history[device.address] ||= {}
                if (Time.now.to_i - (15 * 60)) >= query_history[device.address][:l2ping].to_i
                  # BlueHydra.logger.debug("device l2ping scan triggered")
                  l2ping_queue.push({
                    command: :l2ping,
                    address: device.address
                  })
                  query_history[device.address][:l2ping] = Time.now.to_i
                end
              }
            end

            until result_queue.empty?
              queue_depth = result_queue.length
              if queue_depth > 250
                if (maxdepth < queue_depth)
                  BlueHydra.logger.warn("Popping off result queue. Max Depth: #{maxdepth} and rising")
                  maxdepth = result_queue.length
                else
                  BlueHydra.logger.warn("Popping off result queue. Max Depth: #{maxdepth} Currently: #{queue_depth}")
                end
              end

              result = result_queue.pop
              if result[:address]
                device = BlueHydra::Device.update_or_create_from_result(result)

                query_history[device.address] ||= {}

                unless BlueHydra.config[:file]
                  # BlueHydra.logger.debug("#{device.address} | le: #{device.le_mode.inspect}| classic: #{device.classic_mode.inspect} | hist: #{query_history[device.address]}")

                  if device.le_mode
                    # device.le_mode - this is a le device which has not been queried for >=15m
                    #   if true, add to active_queue to "hcitool leinfo result[:address]"
                    if (Time.now.to_i - (15 * 60)) >= query_history[device.address][:le].to_i
                      #BlueHydra.logger.debug("device le scan triggered")
                      info_scan_queue.push({command: :leinfo, address: device.address})
                      query_history[device.address][:le] = Time.now.to_i
                    end
                  end

                  if device.classic_mode
                    # device.classic_mode - this is a classic device which has not been queried for >=15m
                    #   if true, add to active_queue "hcitool info result[:address]"
                    if (Time.now.to_i - (15 * 60)) >= query_history[device.address][:classic].to_i
                      #BlueHydra.logger.debug("device classic scan triggered")
                      info_scan_queue.push({command: :info, address: device.address})
                      query_history[device.address][:classic] = Time.now.to_i
                    end
                  end
                end

              else
                BlueHydra.logger.warn("Device without address #{JSON.generate(result)}")
              end
            end

            # mark hosts as 'offline' if we haven't seen for a while
            BlueHydra::Device.all(status: "online").select{|x|
              x.last_seen < (Time.now.to_i - (60*60))
            }.each{|device|
              device.status = 'offline'
              device.save
            }

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
