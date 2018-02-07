module BlueHydra

  # This class is responsible for running the Bluetooth monitor. It can also be
  # passed other commands such as "cat btmonoutput.txt" to allow replaying of
  # recorded bluetooth scans.
  class BtmonHandler

    # initialize an instance of the class to run a command and push filtered
    # output into the parsing and processing pipeline
    #
    # == Parameters:
    #   command ::
    #     the command to get data from, in most cases this is `btmon -T`
    #   parse_queue ::
    #     Queue object to push results into
    def initialize(command, parse_queue)
      @command = command
      @parse_queue = parse_queue

      # # log used btmon output for review if requested
      if BlueHydra.config["btmon_log"]
        @log_file = File.open("btmon_#{Time.now.to_i}.log.gz",'w+')
        @log_writer = Zlib::GzipWriter.wrap(@log_file)
      end
      # # log raw btmon output for review if requested
      if BlueHydra.config["btmon_rawlog"]
        @rawlog_file = File.open("btmon_raw_#{Time.now.to_i}.log.gz",'w+')
        @rawlog_writer = Zlib::GzipWriter.wrap(@rawlog_file)
      end

      # initialize itself calls the method that spanws the PTY which runs the
      # command
      begin
        spawn
      ensure
        @log_writer.close if @log_writer
        @rawlog_writer.close if @rawlog_writer
      end
    end

    # spawn a PTY to run @command
    def spawn
      PTY.spawn(@command) do |stdout, stdin, pid|

        # lines of output will be stacked up here until a message is complete
        # and pushed into @parse_queue
        buffer = []

        begin
          # handle the streaming output line by line
          stdout.each do |line|

            # log used btmon output for review if we are in debug mode
            if BlueHydra.config["btmon_rawlog"] && !BlueHydra.config["file"]
              @rawlog_writer.puts(line.chomp)
            end

            # strip out color codes
            known_colors = [
              "\e[0;30m", "\e[1;30m",
              "\e[0;31m", "\e[1;31m",
              "\e[0;32m", "\e[1;32m",
              "\e[0;33m", "\e[1;33m",
              "\e[0;34m", "\e[1;34m",
              "\e[0;35m", "\e[1;35m",
              "\e[0;36m", "\e[1;36m",
              "\e[0;37m", "\e[1;37m",
              "\e[0m",
            ]

            begin
              known_colors.each do |c|
                line = line.gsub(c, "")
              end
            rescue ArgumentError
              BlueHydra.logger.warn("Non UTF-8 encoding in line: #{line.chomp}")
              next
            end

            # Messages are indented under a header as follows
            #
            #   Message A
            #     Data A1
            #     Data A2
            #   Message B
            #     Data B1
            #       Data B1a
            #     Data B2
            #
            # If the line starts with whitespace we are still in a nested
            # message otherwise we hit a new message and should empy the buffer
            #
            # \s == whitespace
            # \S == non whitespace
            #
            # When we get a line that starts with non-whitespace we are dealing
            # with a new message starting
            if line =~ /^\S/

              # if we have nothing in the buffer its our first message of the
              # run so we dont need to do anything but if we have a non-zero
              # sized buffer we push the contents of the buffer into the
              # @parse_queue
              if buffer.size > 0
                enqueue(buffer)
              end

              # reset the buffer
              buffer = []
            end

            buffer << line
          end
        rescue Errno::EIO
          # File has completed or command has crashed, either way flush last
          # chunks to buffer
          enqueue(buffer)

          raise BtmonExitedError
        end
      end
    end

    # filter and then push an array of lines into the @parse_queue
    def enqueue(buffer)

      # discard anything which we sent to the modem as those lines
      # will start with <
      # also discard anything prefixed with @ (local events)
      # drop command complete messages and similar messages that do not seem to be useful
      #
      # numbers from bluez monitor/packet.c static const struct event_data event_table
      return if buffer.first =~ /^</
      return if buffer.first =~ /^@/
      return if buffer.first =~ /^> HCI Event: .* \(0x0f\)/ # "Command Status"
      return if buffer.first =~ /^> HCI Event: .* \(0x13\)/ # "Number of Completed Packets"
      return if buffer.first =~ /^> HCI Event: Unknown \(0x00\)/ 
      return if buffer.first =~ /^Bluetooth monitor ver/
      return if (buffer[0] =~ /^> HCI Event: .* \(0x0e\)/ && buffer[1] !~ /Remote/ ) # "Command Complete" this filters out local stuff
      return if buffer.first =~ /^= bluetoothd: Unable to/
      return if buffer.first =~ /^= New Index:/
      return if buffer.first =~ /^= Delete Index:/
      return if buffer.first =~ /^= Open Index:/
      return if buffer.first =~ /^= Close Index:/
      return if buffer.first =~ /^= Index Info:/
      return if buffer.first =~ /^= Note:/

      # l2ping against a host that is gone will result in a good connect
      # complete message with a timed out status indicating the ping failed
      # do not send this to the parser as it will 'online' the record
      # when we actually want to let it time out.
      #
      # TODO add a positive feed back loop to indicate we have attempted
      # and failed to ping a device, for now, throw out everything that isn't Success
      # (l2pinging a down host results in "Page Timeout")
      # additional observed values include "ACL Connection Already Exists", "Command Disallowed"
      # "LMP Response Timeout / LL Response Timeout", "Connection Accept Timeout Exceeded"
      # "Connection Timeout"
      #                                                                        This breaks if it starts with ^, no clue why
      return if (buffer[0] =~ /^> HCI Event: .* \(0x(03|07)\)/ && buffer[1] !~ /\sStatus: Success \(0x00\)/ ) # "Connect Complete|Remote Name Req Complete"

      # log used btmon output for review
      if BlueHydra.config["btmon_log"] && !BlueHydra.config["file"] && !BlueHydra.config["btmon_rawlog"]
        buffer.each do |line|
          @log_writer.puts(line.chomp)
        end
      end

      # unless this is a filtered message enqueue the buffer for realz.
      @parse_queue.push(buffer)
    end
  end
end
