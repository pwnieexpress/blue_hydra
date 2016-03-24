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

        BlueHydra.logger.info("Marking older devices as 'offline'...")
        BlueHydra::Device.mark_old_devices_offline

        BlueHydra.logger.info("Syncing all hosts to Pulse...")
        BlueHydra::Device.sync_all_to_pulse

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
          if system("ubertooth-util -v > /dev/null 2>&1")
            if ::File.executable?("/usr/bin/ubertooth-rx") && `ubertooth-rx -h | grep -q Survey`
              @ubertooth_command = "ubertooth-rx -z -t 40"
            elsif ::File.executable?("/usr/bin/ubertooth-scan")
              @ubertooth_command = "ubertooth-scan -t 40"
            end
            start_ubertooth_thread if @ubertooth_command
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
        x[:ubertooth_thread] = self.ubertooth_thread.status if self.ubertooth_thread
      end

      x[:cui_thread] = self.cui_thread.status unless BlueHydra.daemon_mode

      x
    end

    def stop
      BlueHydra.logger.info("Runner stopped. Exiting after clearing queue...")
      self.btmon_thread.kill # stop this first thread so data stops flowing ...

      stop_condition = Proc.new do
        [nil, false].include?(result_thread.status) ||
        [nil, false].include?(parser_thread.status) ||
        self.result_queue.empty?
      end

      # clear queue...
      until stop_condition.call
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

    def hci_reset
      # interface reset
      interface_reset = BlueHydra::Command.execute3("hciconfig #{BlueHydra.config[:bt_device]} reset")[:stderr]
      if interface_reset
        BlueHydra.logger.error("Error with hciconfig #{BlueHydra.config[:bt_device]} reset..")
        interface_reset.split("\n").each do |ln|
          BlueHydra.logger.error(ln)
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
                  hci_reset
                  BlueHydra.logger.debug("Popping off info scan queue. Depth: #{ info_scan_queue.length}")
                  command = info_scan_queue.pop
                  case command[:command]
                  when :info
                    info_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config[:bt_device]} info #{command[:address]}",3)[:stderr]
                  when :leinfo
                    info_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config[:bt_device]} leinfo --random #{command[:address]}",3)[:stderr]
                    if info_errors == "Could not create connection: Input/output error"
                      info_errors = nil
                      BlueHydra.logger.debug("Random leinfo failed against #{command[:address]}")
                      hci_reset
                      info2_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config[:bt_device]} leinfo --static #{command[:address]}",3)[:stderr]
                      if info2_errors == "Could not create connection: Input/output error"
                        BlueHydra.logger.debug("Static leinfo failed against #{command[:address]}")
                        hci_reset
                        info3_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config[:bt_device]} leinfo #{command[:address]}",3)[:stderr]
                        if info3_errors == "Could not create connection: Input/output error"
                          BlueHydra.logger.debug("Default leinfo failed against #{command[:address]}")
                          BlueHydra.logger.debug("Default leinfo failed against #{command[:address]}")
                          BlueHydra.logger.debug("Default leinfo failed against #{command[:address]}")
                        end
                      end
                    end
                  else
                    BlueHydra.logger.error("Invalid command detected... #{command.inspect}")
                    info_errors = nil
                  end
                  if info_errors
                    if info_errors.chomp =~ /connect: No route to host/i
                      # We could handle this as negative feedback if we want
                    elsif info_errors.chomp =~ /create connection: Input\/output error/i
                      # We failed to connect, not sure why, not sure we care
                    else
                      BlueHydra.logger.error("Error with info command... #{command.inspect}")
                      info_errors.split("\n").each do |ln|
                        BlueHydra.logger.error(ln)
                      end
                    end
                  end
                end
                # run 1 l2ping a time while still checking if info scan queue
                # is empty
                unless l2ping_queue.empty?
                  hci_reset
                  BlueHydra.logger.debug("Popping off l2ping queue. Depth: #{ l2ping_queue.length}")
                  command = l2ping_queue.pop
                  l2ping_errors = BlueHydra::Command.execute3("l2ping -c 3 -i #{BlueHydra.config[:bt_device]} #{command[:address]}",5)[:stderr]
                  if l2ping_errors
                    if l2ping_errors.chomp =~ /connect: No route to host/i
                      # We could handle this as negative feedback if we want
                    elsif l2ping_errors.chomp =~ /connect: Host is down/i
                      # Same as above
                    elsif l2ping_errors.chomp =~ /create connection: Input\/output error/i
                      # We failed to connect, not sure why, not sure we care
                    else
                      BlueHydra.logger.error("Error with l2ping command... #{command.inspect}")
                      l2ping_errors.split("\n").each do |ln|
                        BlueHydra.logger.error(ln)
                      end
                    end
                  end
                end
              end

              hci_reset

              # hot loop avoidance, but run right before discovery to avoid any delay between discovery and info scan
              sleep 1

              # run test-discovery
              # do a discovery
              self.scanner_status[:test_discovery] = Time.now.to_i unless BlueHydra.daemon_mode
              discovery_errors = BlueHydra::Command.execute3(discovery_command,45)[:stderr]
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
              ubertooth_output = BlueHydra::Command.execute3(@ubertooth_command,60)
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
        cui  = BlueHydra::CliUserInterface.new(self)
        cui.help_message
        cui.cui_loop
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

            attrs = p.attributes.dup

            address = (attrs[:address]||[]).uniq.first

            if address

              unless BlueHydra.daemon_mode
                tracker = CliUserInterfaceTracker.new(self, chunk, attrs, address)
                tracker.update_cui_status
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
                      current_time = attrs[k].sort.last
                      last_seen = scan_results[address][k].sort.last

                      # update this value no more than 1 x / minute to avoid
                      # flooding pulse with too much noise.
                      if (current_time - last_seen) > 60
                        attrs[k] = [current_time]
                        scan_results[address][k] = attrs[k]
                        needs_push = true
                      else
                        attrs[k] = [last_seen]
                      end

                    when [:le_rssi, :classic_rssi].include?(k)
                      current_time = attrs[k][0][:t]
                      last_seen_time = (scan_results[address][k][0][:t] rescue 0)

                      # update this value no more than 1 x / minute to avoid
                      # flooding pulse with too much noise.
                      if (current_time - last_seen_time) > 60
                        # BlueHydra.logger.debug("syncing #{k} for #{address} last sync was #{attrs[k][0][:t] - last_seen_time}s ago...")
                        scan_results[address][k] = attrs[k]
                        needs_push = true
                      else
                        attrs.delete(k)
                      end
                    end
                  end
                end

                if needs_push
                  result_queue.push(attrs)
                end
              else
                scan_results[address] = attrs
                result_queue.push(attrs)
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

            BlueHydra::Device.mark_old_devices_offline

            if (Time.now.to_i - BlueHydra.config[:status_sync_rate]) > last_status_sync
              BlueHydra.logger.info("Syncing all host statuses to Pulse...")
              BlueHydra::Device.sync_statuses_to_pulse
              last_status_sync = Time.now.to_i
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
