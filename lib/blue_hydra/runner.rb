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
          discovery_command = File.expand_path('../../bin/test-discovery', __FILE__)
          loop do
            # do a discovery
            discovery_command_output = BlueHydra::Command.execute3(discovery_command)

            # check output for errors
            if discovery_command_output[:stderr] || discovery_command_output[:exit_code] != 0
              # TODO DO SOMETHING
            end

            # clear command queue
            until discovery_command_queue.empty?
              command = discovery_command_queue
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
          while result = result_queue.pop do
            BlueHydra.logger.info("Result thread got result")
            if result[:address]
              BlueHydra::Device.update_or_create_from_result(result)

              # TODO: REMOVE THIS -- START
              # TODO: REMOVE THIS -- START
              # TODO: REMOVE THIS -- START
              address = result[:address].first

              file_path = File.expand_path(
                "../../../devices/#{address.gsub(':', '-')}_device_info.json", __FILE__
              )

              BlueHydra.logger.info("Result thread preparing for #{file_path}")

              base = if File.exists?(file_path)
                       JSON.parse(
                         File.read(file_path),
                         symbolize_names: true
                       )
                     else
                       {}
                     end

              result.each do |key, values|
                if base[key]
                  base[key] = (base[key] + values).uniq
                else
                  base[key] = values.uniq
                end
              end

              BlueHydra.logger.info("Result thread writing to #{file_path}")
              File.write(file_path, JSON.pretty_generate(base))
              # TODO: REMOVE THIS -- END
              # TODO: REMOVE THIS -- END
              # TODO: REMOVE THIS -- END

            else
              BlueHydra.logger.warn("Device without address #{JSON.generate(result)}")
            end
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
