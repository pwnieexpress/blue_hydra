module BlueHydra

  # This class is a wrapper for all the core functionality of  Blue Hydra. It
  # is responsible for managing all the threads for device interaction, data
  # processing and, when not in daemon mode, the CLI UI trhead and tracker.
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

    # if we have been passed the 'file' option in the config we should try to
    # read out the file as our data source. This allows for btmon captures to
    # be replayed and post-processed.
    #
    # Supported filetypes are .xz, .gz or plaintext
    if BlueHydra.config["file"]
      if BlueHydra.config["file"] =~ /\.xz$/
        @@command = "xzcat #{BlueHydra.config["file"]}"
      elsif BlueHydra.config["file"] =~ /\.gz$/
        @@command = "zcat #{BlueHydra.config["file"]}"
      else
        @@command = "cat #{BlueHydra.config["file"]}"
      end
    else
      @@command = "btmon -T -i #{BlueHydra.config["bt_device"]}"
    end

    # Start the runner after being initialized
    #
    # == Parameters
    #   command ::
    #     the command to run, typically btmon -T -i hci0 but will be different
    #     if running in file mode
    def start(command=@@command)
      begin
        BlueHydra.logger.info("Runner starting with '#{command}' ...")

        # We should have marked everything offline at shutdown, but just in case
        # our shutdown was unclean, make sure it's all offline now.
        BlueHydra.logger.info("Marking old devices as 'offline'...")
        BlueHydra::Device.mark_all_devices_offline

        # Sync everything to pwnpulse if the system is connected to the Pwnie
        # Express cloud
        BlueHydra.logger.info("Syncing all hosts to Pulse...") if BlueHydra.pulse
        BlueHydra::Device.sync_all_to_pulse

        # Query History is used to track what addresses have been pinged
        self.query_history   = {}

        # the command used to capture data
        self.command         = command

        # various queues used for thread intercommunication, could be replaced
        # by true IPC sockets at some point but these work prety damn well
        self.raw_queue       = Queue.new # btmon thread   -> chunker thread
        self.chunk_queue     = Queue.new # chunker thread -> parser thread
        self.result_queue    = Queue.new # parser thread  -> result thread
        self.info_scan_queue = Queue.new # result thread  -> discovery thread
        self.l2ping_queue    = Queue.new # result thread  -> discovery thread

        # start the thrad which runs the command, typically btmon so this is
        # the btmon thread but this thread will also run the xzcat, zcat or cat
        # commands for files
        start_btmon_thread

        # helper hashes for tracking status of the scanners and also the in
        # memory copy of data for the CUI
        self.scanner_status  = {}
        self.cui_status      = {}

        # another thread which operates the actual device discovery, not needed
        # if reading from a file since btmon will just be getting replayed
        start_discovery_thread unless BlueHydra.config["file"]

        # start the thread responsibly for breaking the filtered btmon output
        # into chunks by device, basically a pre-parser
        start_chunker_thread

        # start the thread responsible for parsing the chunks into little data
        # blobs to be sotred in teh db
        start_parser_thread

        # start the result processing thread
        start_result_thread

        # start the thread responsible for printing the CUI to screen unless
        # we are in daemon mode
        start_cui_thread unless BlueHydra.daemon_mode

        # unless we are reading from a file we need to determine if we have an
        # ubertooth available and then initialize a thread to manage that
        # device as needed
        unless BlueHydra.config["file"]
          # Handle ubertooth
          self.scanner_status[:ubertooth] = "Detecting"
          if system("ubertooth-util -v > /dev/null 2>&1")
            self.scanner_status[:ubertooth] = "Found hardware"
            BlueHydra.logger.debug("Found ubertooth hardware")
            sleep 1
            if system("ubertooth-util -r > /dev/null 2>&1")
              self.scanner_status[:ubertooth] = "hardware responsive"
              BlueHydra.logger.debug("hardware is responsive")
              sleep 1
              if system("ubertooth-rx -h 2>&1 | grep -q Survey")
                @ubertooth_command = "ubertooth-rx -z -t 40"
                BlueHydra.logger.debug("Found working ubertooth-rx -z")
                self.scanner_status[:ubertooth] = "ubertooth-rx"
              end
              unless @ubertooth_command
                sleep 1
                if system("ubertooth-scan -t 1 > /dev/null 2>&1")
                  @ubertooth_command = "ubertooth-scan -t 40"
                  BlueHydra.logger.debug("Found working ubertooth-scan")
                  self.scanner_status[:ubertooth] = "ubertooth-scan"
                else
                  BlueHydra.logger.error("Unable to find ubertooth-scan or ubertooth-rx -z, ubertooth disabled.")
                  self.scanner_status[:ubertooth] = "Unable to find ubertooth-scan or ubertooth-rx -z"
                end
              end
            else
              self.scanner_status[:ubertooth] = "hardware unresponsive"
              BlueHydra.logger.error("hardware is present but ubertooth-util -r fails")
            end
            start_ubertooth_thread if @ubertooth_command
          else
            self.scanner_status[:ubertooth] = "No hardware detected"
            BlueHydra.logger.debug("No ubertooth hardware detected")
          end
        end

      rescue => e
        BlueHydra.logger.error("Runner master thread: #{e.message}")
        e.backtrace.each do |x|
          BlueHydra.logger.error("#{x}")
        end
      end
    end

    # this is a helper method which resports status of queue depth and thread
    # health. Mainly used from bin/blue_hydra work loop to make sure everything
    # is alive or to exit gracefully
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

      unless BlueHydra.config["file"]
        x[:discovery_thread] = self.discovery_thread.status
        x[:ubertooth_thread] = self.ubertooth_thread.status if self.ubertooth_thread
      end

      x[:cui_thread] = self.cui_thread.status unless BlueHydra.daemon_mode

      x
    end

    # stop method this stops the threads but attempts to allow the result queue
    # to drain before fully exiting to prevent data loss
    def stop
      BlueHydra.logger.info("Runner stopped. Exiting after clearing queue...")
      self.btmon_thread.kill if self.btmon_thread # stop this first thread so data stops flowing ...

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

      # Mark all devices offline while shutting down
      # If we aren't online to see it then we cannot pretend things are online.
      BlueHydra::Device.mark_all_devices_offline

      BlueHydra.logger.info("Queue clear! Exiting.")

      self.raw_queue       = nil
      self.chunk_queue     = nil
      self.result_queue    = nil
      self.info_scan_queue = nil
      self.l2ping_queue    = nil

      unless BlueHydra.config["file"]
        self.discovery_thread.kill if self.discovery_thread
        self.ubertooth_thread.kill if self.ubertooth_thread
      end

      self.chunker_thread.kill if self.chunker_thread
      self.parser_thread.kill  if self.parser_thread
      self.result_thread.kill  if self.result_thread
      self.cui_thread.kill     if self.cui_thread
    end

    # Start the thread which runs the specified command
    def start_btmon_thread
      BlueHydra.logger.info("Btmon thread starting")
      self.btmon_thread = Thread.new do
        begin
          # spawn the handler for btmon and pass in the shared raw queue as a
          # param so that it can feed data back into the runner threads
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

    # helper method to reset the interface as needed
    def hci_reset
      # interface reset
      interface_reset = BlueHydra::Command.execute3("hciconfig #{BlueHydra.config["bt_device"]} reset")[:stderr]
      if interface_reset
        BlueHydra.logger.error("Error with hciconfig #{BlueHydra.config["bt_device"]} reset..")
        interface_reset.split("\n").each do |ln|
          BlueHydra.logger.error(ln)
        end
        if interface_reset =~ /Connection timed out/i || interface_reset =~ /Operation not possible due to RF-kill/i
          ## TODO: check error number not description
          ## TODO: check for interface name "Can't init device hci0: Connection timed out (110)"
          ## TODO: check for interface name "Can't init device hci0: Operation not possible due to RF-kill (132)"
          raise BluezNotReadyError
        end
      end
    end

    # thread responsible for sending interesting commands to the hci device so
    # that interesting things show up in the btmon ouput
    def start_discovery_thread
      BlueHydra.logger.info("Discovery thread starting")
      self.discovery_thread = Thread.new do
        begin

          discovery_command = "#{File.expand_path('../../../bin/test-discovery', __FILE__)} -i #{BlueHydra.config["bt_device"]}"

          loop do
            begin

              # set once here so if it fails on the first loop we don't get nil
              bluez_errors      ||= 0
              bluetoothd_errors ||= 0

              # clear the queues
              until info_scan_queue.empty? && l2ping_queue.empty?
                # clear out entire info scan queue first
                until info_scan_queue.empty?

                  # reset interface first to get to a good base state
                  hci_reset

                  BlueHydra.logger.debug("Popping off info scan queue. Depth: #{ info_scan_queue.length}")

                  # grab a command out of the queue to run
                  command = info_scan_queue.pop
                  case command[:command]
                  when :info # classic mode devices
                    # run hcitool info against the specified address, capture
                    # errors, no need to capture stdout because the interesting
                    # stuff is gonna be in btmon anyway
                    info_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config["bt_device"]} info #{command[:address]}",3)[:stderr]

                  when :leinfo # low energy devices
                    # run hcitool leinfo, capture errors
                    info_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config["bt_device"]} leinfo --random #{command[:address]}",3)[:stderr]

                    # if we have errors fro le info scan attempt some
                    # additional trickery to grab the data in a few other ways
                    if info_errors == "Could not create connection: Input/output error"
                      info_errors = nil
                      BlueHydra.logger.debug("Random leinfo failed against #{command[:address]}")
                      hci_reset
                      info2_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config["bt_device"]} leinfo --static #{command[:address]}",3)[:stderr]
                      if info2_errors == "Could not create connection: Input/output error"
                        BlueHydra.logger.debug("Static leinfo failed against #{command[:address]}")
                        hci_reset
                        info3_errors = BlueHydra::Command.execute3("hcitool -i #{BlueHydra.config["bt_device"]} leinfo #{command[:address]}",3)[:stderr]
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

                  # handle and log error output as needed
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
                  l2ping_errors = BlueHydra::Command.execute3("l2ping -c 3 -i #{BlueHydra.config["bt_device"]} #{command[:address]}",5)[:stderr]
                  if l2ping_errors
                    if l2ping_errors.chomp =~ /connect: No route to host/i
                      # We could handle this as negative feedback if we want
                    elsif l2ping_errors.chomp =~ /connect: Host is down/i
                      # Same as above
                    elsif l2ping_errors.chomp =~ /create connection: Input\/output error/i
                      # We failed to connect, not sure why, not sure we care
                    elsif l2ping_errors.chomp =~ /connect: Connection refused/i
                      #maybe we do care about this one? if it refused, it was there
                    elsif l2ping_errors.chomp =~ /connect: Permission denied/i
                      #this appears when we aren't root, but it also gets sent back from the remote host sometimes
                    elsif l2ping_errors.chomp =~ /connect: Function not implemented/i
                      # this isn't in the bluez code at all so it must be coming back from the remote host
                    else
                      BlueHydra.logger.error("Error with l2ping command... #{command.inspect}")
                      l2ping_errors.split("\n").each do |ln|
                        BlueHydra.logger.error(ln)
                      end
                    end
                  end
                end
              end

              # another reset before going back to discovery
              hci_reset

              # hot loop avoidance, but run right before discovery to avoid any delay between discovery and info scan
              sleep 1

              # run test-discovery
              # do a discovery
              self.scanner_status[:test_discovery] = Time.now.to_i unless BlueHydra.daemon_mode
              discovery_errors = BlueHydra::Command.execute3(discovery_command,45)[:stderr]
              if discovery_errors
                BlueHydra.logger.error("Error with test-discovery script..")
                discovery_errors.split("\n").each do |ln|
                  BlueHydra.logger.error(ln)
                end
                if discovery_errors =~ /org.bluez.Error.NotReady/
                  raise BluezNotReadyError
                elsif discovery_errors =~ /dbus.exceptions.DBusException/i
                  # This happens when bluetoothd isn't running or otherwise broken off the dbus
                  # systemd
                  #  dbus.exceptions.DBusException: org.freedesktop.systemd1.NoSuchUnit: Unit dbus-org.bluez.service not found.
                  #  dbus.exceptions.DBusException: org.freedesktop.DBus.Error.ServiceUnknown: The name :1.[0-9]{5} was not provided by any .service files
                  # gentoo (not systemd)
                  #  dbus.exceptions.DBusException: org.freedesktop.DBus.Error.ServiceUnknown: The name org.bluez was not provided by any .service files
                  #  dbus.exceptions.DBusException: org.freedesktop.DBus.Error.ServiceUnknown: The name :1.[0-9]{3} was not provided by any .service files
                  raise BluetoothdDbusError
                end
              end

              bluez_errors = 0
              bluetoothd_errors = 0

            rescue BluetoothdDbusError
              bluetoothd_errors += 1
              if bluetoothd_errors == 1
                # Is bluetoothd running?
                bluetoothd_pid = `pgrep bluetoothd`.chomp
                unless bluetoothd_pid == ""
                  # Does init own bluetoothd?
                  if `ps -o ppid= #{bluetoothd_pid}`.chomp =~ /\s1/
                    bluetoothd_restart = BlueHydra::Command.execute3("service bluetooth restart")
                    sleep 3
                  else
                    # not controled by init, bail
                    unless BlueHydra.daemon_mode
                      self.cui_thread.kill if self.cui_thread
                      puts "Bluetoothd is running but not controlled by init or functioning, please restart it manually."
                    end
                    BlueHydra.logger.error("Bluetoothd is running but not controlled by init or functioning, please restart it manually.")
                    exit 1
                  end
                else
                  # bluetoothd isn't running at all, attempt to restart through init
                  bluetoothd_restart = BlueHydra::Command.execute3("service bluetooth restart")
                  sleep 3
                end
                unless bluetoothd_restart[:exit_code] == 0
                  bluetoothd_errors += 1
                end
              end
              if bluetoothd_errors > 1
                unless BlueHydra.daemon_mode
                  self.cui_thread.kill if self.cui_thread
                  puts "Bluetoothd is not functioning as expected and auto-restart failed."
                  puts "Please restart bluetoothd and try again."
                end
                if bluetoothd_restart[:stderr]
                  BlueHydra.logger.error("Failed to restart bluetoothd: #{bluetoothd_restart[:stderr]}")
                end
                BlueHydra.logger.error("Bluetoothd is not functioning as expected")
                exit 1
              end
            rescue BluezNotReadyError
              bluez_errors += 1
              if bluez_errors == 1
                BlueHydra.logger.error("Bluez reported #{BlueHydra.config["bt_device"]} not ready, attempting to reset with rfkill")
                rfkillreset_command = "#{File.expand_path('../../../bin/rfkill-reset', __FILE__)} #{BlueHydra.config["bt_device"]}"
                rfkillreset_errors = BlueHydra::Command.execute3(rfkillreset_command,45)[:stdout] #no output means no errors, all output to stdout
                if rfkillreset_errors
                  bluez_errors += 1
                end
              end
              if bluez_errors > 1
                unless BlueHydra.daemon_mode
                  self.cui_thread.kill if self.cui_thread
                  puts "Bluez reported #{BlueHydra.config["bt_device"]} not ready and failed to auto-reset with rfkill"
                  puts "Try removing and replugging the card, or toggling rfkill on and off"
                end
                BlueHydra.logger.error("Bluez reported #{BlueHydra.config["bt_device"]} not ready and failed to reset with rfkill")
                exit 1
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

    # thread to manage the ubertooth device where available
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
              if ubertooth_output[:stderr]
                BlueHydra.logger.error("Error with ubertooth_{scan,rx}..")
                ubertooth_output[:stderr].split("\n").each do |ln|
                  BlueHydra.logger.error(ln)
                end
              else
                ubertooth_output[:stdout].each_line do |line|
                  if line =~ /^[\?:]{6}[0-9a-f:]{11}/i
                    address = line.scan(/^((\?\?:){2}([0-9a-f:]*))/i).flatten.first.gsub('?', '0')

                    # note that things here are being manually [array] wrapped
                    # so that they follow the data patterns set by the parser
                    result_queue.push({
                      address:      [address],
                      last_seen:    [Time.now.to_i],
                      classic_mode: [true]
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

    # thread to manage the CUI output where availalbe
    def start_cui_thread
      BlueHydra.logger.info("Command Line UI thread starting")
      self.cui_thread = Thread.new do
        cui  = BlueHydra::CliUserInterface.new(self)
        cui.help_message
        cui.cui_loop
      end
    end

    # helper method to push addresses intothe scan queues with a little
    # pre-processing
    def push_to_queue(mode, address)
      case mode
      when :classic
        command = :info
        # use uap_lap for tracking classic devices
        track_addr = address.split(":")[2,4].join(":")

        # do not send local adapter to be scanned y(>_<)y
        return if track_addr == BlueHydra::LOCAL_ADAPTER_ADDRESS.split(":")[2,4].join(":")
      when :le
        command = :leinfo
        track_addr = address

        # do not send local adapter to be scanned y(>_<)y
        return if address == BlueHydra::LOCAL_ADAPTER_ADDRESS
      end

      # only scan if the info scan rate timeframe has elapsed
      self.query_history[track_addr] ||= {}
      last_info = self.query_history[track_addr][mode].to_i
      if (Time.now.to_i - (BlueHydra.config["info_scan_rate"].to_i * 60)) >= last_info
        info_scan_queue.push({command: command, address: address})
        self.query_history[track_addr][mode] = Time.now.to_i
      end
    end

    # thread responsible for chunking up btmon output to be parsed
    def start_chunker_thread
      BlueHydra.logger.info("Chunker thread starting")
      self.chunker_thread = Thread.new do
        loop do
          begin
            # handler, pass in chunk queue for data to be fed back out
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

    # thread responsible for parsed chunked up btmon output
    def start_parser_thread
      BlueHydra.logger.info("Parser thread starting")
      self.parser_thread = Thread.new do
        begin

          scan_results = {}

          # get the chunks and parse them, track history, update CUI and push
          # to data processing thread
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

                      # if log_rssi is set log all values
                      if BlueHydra.config["rssi_log"]
                        attrs[k].each do |x|
                          # unix timestamp from btmon
                          ts = x[:t]

                          # LE / CL for classic mode
                          type = k.to_s.gsub('_rssi', '').upcase[0,2]

                          # '-90 dBm' ->  -90
                          rssi = x[:rssi].split(' ')[0]
                          msg = [ts, type, address, rssi].join(' ')
                          BlueHydra.rssi_logger.info(msg)
                        end
                      end

                      # if aggressive_rssi is set send all rssis to pulse
                      # this should not be set where avoidable
                      if BlueHydra.config["aggressive_rssi"] && BlueHydra.pulse
                        attrs[k].each do |x|
                          send_data = {
                            type:   "bluetooth",
                            source: "blue-hydra",
                            version: BlueHydra::VERSION,
                            data: {}
                          }
                          send_data[:data][:status] = "online"
                          send_data[:data][:address] = address
                          send_data[:data][k] = [x]

                          begin
                            # create the json
                            json = JSON.generate(send_data)

                            # write json data to result socket
                            TCPSocket.open('127.0.0.1', 8244) do |sock|
                              sock.write(json)
                              sock.write("\n")
                              sock.flush
                            end
                          rescue => e
                            BlueHydra.logger.warn "Unable to connect to Hermes (#{e.message}), unable to send to pulse"
                          end
                        end
                      end

                      # update this value no more than 1 x / minute to avoid
                      # flooding pulse with too much noise.
                      if (current_time - last_seen_time) > 60
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

          last_sync = Time.now

          last_status_sync = Time.now.to_i

          loop do
            # 1 day in seconds == 24 * 60 * 60 == 86400
            # daily sync
            if Time.now.to_i - 86400 >=  last_sync.to_i
              BlueHydra::Device.sync_all_to_pulse(last_sync)
              last_sync = Time.now
            end

            unless BlueHydra.config["file"]
              # if their last_seen value is > 7 minutes ago and not > 15 minutes ago
              #   l2ping them :  "l2ping -c 3 result[:address]"
              BlueHydra::Device.all(classic_mode: true).select{|x|
                x.last_seen < (Time.now.to_i - (60 * 7)) && x.last_seen > (Time.now.to_i - (60*15))
              }.each do |device|
                self.query_history[device.address] ||= {}
                if (Time.now.to_i - (60 * 7)) >= self.query_history[device.address][:l2ping].to_i

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

                unless BlueHydra.config["file"]
                  if device.le_mode
                    #do not info scan beacon type devices, they do not respond while in advertising mode
                    if device.company_type !~ /iBeacon/i && device.company !~ /Gimbal/i
                      push_to_queue(:le, device.address)
                    end
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

            if (Time.now.to_i - BlueHydra.config["status_sync_rate"]) > last_status_sync && BlueHydra.pulse
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
