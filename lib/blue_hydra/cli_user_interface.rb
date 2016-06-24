module BlueHydra
  class CliUserInterface
    attr_accessor :runner, :cui_timeout, :l2ping_threshold

    def initialize(runner, cui_timeout=300)
      @runner = runner
      @cui_timeout = cui_timeout
      @l2ping_threshold = (@cui_timeout - 45)
    end

    def cui_status
      @runner.cui_status
    end

    def scanner_status
      @runner.scanner_status
    end

    def ubertooth_thread
      @runner.ubertooth_thread
    end

    def result_queue
      @runner.result_queue
    end

    def info_scan_queue
      @runner.info_scan_queue
    end

    def l2ping_queue
      @runner.l2ping_queue
    end

    def query_history
      @runner.query_history
    end

    def help_message
      puts "\e[H\e[2J"

      msg =  <<HELP
Welcome to \e[34;1mBlue Hydra\e[0m

This will display live information about Bluetooth devices seen in the area.
Devices in this display will time out after #{cui_timeout}s but will still be
available in the BlueHydra Database or synced to pulse if you chose that
option.  #{ BlueHydra.config[:file] ? "\n\nReading data from " + BlueHydra.config[:file]  + '.' : '' }

The "VERS" column in the following table shows mode and version if available.
        CL/BR = Classic mode
        CL4.0 = Classic mode, version 4.0
        BTLE = Bluetooth Low Energy mode
        LE4.1 = Bluetooth Low Energy mode, version 4.1

The "RANGE" column shows distance in meters from the device if known.

press [Enter] key to continue....
HELP

puts msg

gets.chomp
    end

    def cui_loop
      reset = false
      max_height = `tput lines`.chomp.to_i

      until reset do
        trap("SIGWINCH") do
          reset = true
        end

        render_cui(max_height)
        sleep 0.1
      end

      cui_loop
    end

    def render_cui(max_height)
      begin

        unless BlueHydra.config[:file]
          if scanner_status[:test_discovery]
            discovery_time = Time.now.to_i - scanner_status[:test_discovery]
          else
            discovery_time = "not started"
          end

          if ubertooth_thread
            if scanner_status[:ubertooth]
              ubertooth_time = Time.now.to_i - scanner_status[:ubertooth]
            else
              ubertooth_time = "not started"
            end
          else
            ubertooth_time = "not enabled"
          end
        end

        pbuff = ""
        lines = 1

        pbuff << "\e[H\e[2J"

        pbuff << "\e[34;1mBlue Hydra\e[0m :"
        unless BlueHydra.config[:file]
          pbuff <<  " Devices Seen in last #{cui_timeout}s"
        end
        pbuff << "\n"
        lines += 1

        pbuff << "Queue status: result_queue: #{result_queue.length}, info_scan_queue: #{info_scan_queue.length}, l2ping_queue: #{l2ping_queue.length}\n"
        lines += 1

        unless BlueHydra.config[:file]
          pbuff <<  "Discovery status timers: #{discovery_time}, ubertooth status: #{ubertooth_time}\n"
          lines += 1
        end

        max_lengths = Hash.new(0)

        printable_keys = [
          :_seen, :vers, :address, :rssi, :name, :manuf, :type, :range
        ]
        if BlueHydra.config[:log_level] == 'debug'
          printable_keys += [
            :le_proximity_uuid, :le_major_num, :le_minor_num
          ]
          #printable_keys += [ :company, :le_company_data ]
          printable_keys.unshift :uuid
        end

        justifications = {
          _seen: :right,
          rssi:  :right,
          range: :right
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
          make_pretty = Proc.new do |key|
            k = case key
              when :le_major_num
                :major
              when :le_minor_num
                :minor
              else
                key
            end
            k.to_s.ljust(max_lengths[key]).gsub("_"," ")
          end
          header = keys.map{|k| make_pretty.call(k)}.join(' | ').upcase

          pbuff << "\e[0;4m#{header}\e[0m\n"
          lines += 1

          #this is a good sort value but so much harder to read
          #d = cui_status.values.sort_by{|x| x[:last_seen]}.reverse
          #sort rssi by default
          d = cui_status.values.sort_by{|x| x[:rssi]}
          d.each do |data|

            #prevent classic devices from expiring by forcing them onto the l2ping queue
            unless BlueHydra.config[:file]
              if data[:vers] =~ /cl/i
                ping_time = (Time.now.to_i - l2ping_threshold)
                query_history[data[:address]] ||= {}
                if (query_history[data[:address]][:l2ping].to_i < ping_time) && (data[:last_seen] < ping_time)
                  l2ping_queue.push({
                    command: :l2ping,
                    address: data[:address]
                  })

                  query_history[data[:address]][:l2ping] = Time.now.to_i
                end
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

      rescue => e
        BlueHydra.logger.error("CUI thread #{e.message}")
        e.backtrace.each do |x|
          BlueHydra.logger.error("#{x}")
        end
      end
    end
  end
end
