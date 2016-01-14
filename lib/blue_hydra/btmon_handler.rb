module BlueHydra
  class BtmonHandler
    def initialize(command, parse_queue)
      @command = command
      @parse_queue = parse_queue
      spawn
    end

    def spawn
      PTY.spawn(@command) do |stdout, stdin, pid|
        buffer = []
        begin
          stdout.each do |line|
            line = line.gsub("\e[0;37m", "")
            line = line.gsub("\e[0;36m", "")
            line = line.gsub("\e[0;35m", "")
            line = line.gsub("\e[0;34m", "")
            line = line.gsub("\e[0;33m", "")
            line = line.gsub("\e[0;32m", "")
            line = line.gsub("\e[0m",    "")


            # \s == whitespace
            # \S == non whitespace
            if line =~ /^\S/
              if buffer.size > 0
                enqueue(buffer)
              end
              buffer = []
            end

            buffer << line
          end
        rescue Errno::EIO
          enqueue(buffer)
          # puts "Errno:EIO error, but this probably just means " +
          #   "that the process has finished giving output"
        end
      end
    end

    def enqueue(buffer)
      # discard anything which we sent to the modem as those lines
      # will start with <
      # also discard anything prefixed with @ (local events)
      # drop command complete messages and similar messages that do not seem to be useful
      unless(
          buffer.first =~ /^</ ||
          buffer.first =~ /^@/ ||
          buffer.first =~ /^> HCI Event: Command Complete \(0x0e\)/ ||
          buffer.first =~ /^> HCI Event: Command Status \(0x0f\)/ ||
          buffer.first =~ /^> HCI Event: Number of Completed Pa.. \(0x13\)/ ||
          buffer.first =~ /^Bluetooth monitor ver/ ||
          buffer.first =~ /^= New Index:/
        )
        @parse_queue.push(buffer)
      end
    end
  end
end
