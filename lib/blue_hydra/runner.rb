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
                  :discovery_command_queue,
                  :result_thread


    def start(command="btmon -T")
      begin
        BlueHydra.logger.info("Runner starting with '#{command}' ...")
        self.command      = command
        self.raw_queue    = Queue.new
        self.chunk_queue  = Queue.new
        self.result_queue = Queue.new

        self.discovery_command_queue = Queue.new

        start_btmon_thread
        start_discovery_thread
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
      self.raw_queue    = nil
      self.chunk_queue  = nil
      self.result_queue = nil

      self.btmon_thread.kill
      self.discovery_thread.kill
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
          discovery_command = File.expand_path('../../../bin/test-discovery', __FILE__)
          loop do
            # TODO 1. handle any output / edge cases from commands
            # TODO 2. use BlueHydra.config[:bt_device] or whatever
            begin

              # do a discovery
              discovery_errors = BlueHydra::Command.execute3(discovery_command)[:stderr]

              if discovery_errors
                raise discovery_errors
              end

              # clear queue
              until discovery_command_queue.empty?
                command = discovery_command_queue.pop
                case command[:command]
                when :info
                  BlueHydra::Command.execute3("hcitool info #{command[:address]}")
                when :leinfo
                  BlueHydra::Command.execute3("hcitool leinfo #{command[:address]}")
                when :l2ping
                  BlueHydra::Command.execute3("l2ping -c 3 #{command[:address]}")
                else
                  BlueHydra.logger.error("Invalid command detected... #{command.inspect}")
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
          while chunk = chunk_queue.pop do
            p = BlueHydra::Parser.new(chunk)
            p.parse
            BlueHydra.logger.info("Parser thread pushing results")
            result_queue.push(p.attributes)
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
          loop do
            # if their last_seen value is > 15 minutes ago and not > 1 hour ago
            #   l2ping them :  "l2ping -c 3 result[:address]"

            BlueHydra::Device.all.select{|x|
              x.last_seen < (60 * 15) && x.last_seen > (60*60)
            }.each{|x|
              discovery_command_queue.push({
                command: :l2ping,
                address: device.address
              })
            }

            until result_queue.empty?
              result = result_queue.pop
              if result[:address]
                BlueHydra.logger.debug("Result thread got result")
                device = BlueHydra::Device.update_or_create_from_result(result)

                query_history[device.address] ||= {}
                if device.le_mode
                  # device.le_mode - this is a le device which has not been queried for >=15m
                  #   if true, add to active_queue to "hcitool leinfo result[:address]"
                  if (Time.now.to_i - (15 * 60)) >= query_history[device.address][:le].to_i
                    discovery_command_queue.push({command: :leinfo, address: device.address})
                    query_history[device.address][:le_mode] = Time.now.to_i
                  end
                end

                if device.classic_mode
                  # device.classic_mode - this is a classic device which has not been queried for >=15m
                  #   if true, add to active_queue "hcitool info result[:address]"
                  if (Time.now.to_i - (15 * 60)) >= query_history[device.address][:classic].to_i
                    discovery_command_queue.push({command: :info, address: device.address})
                    query_history[device.address][:classic] = Time.now.to_i
                  end
                end
              else
                BlueHydra.logger.warn("Device without address #{JSON.generate(result)}")
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

    end # def

  end
end
