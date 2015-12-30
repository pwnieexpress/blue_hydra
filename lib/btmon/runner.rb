module BtMon
  class Runner

    attr_accessor :command,
                  :raw_queue,
                  :chunk_queue,
                  :result_queue,
                  :pty_thread,
                  :chunker_thread,
                  :parser_thread,
                  :result_thread


    def start(command="btmon -T")
      begin
        BtMon.logger.info("Runner starting with '#{command}' ...")
        self.command      = command
        self.raw_queue    = Queue.new
        self.chunk_queue  = Queue.new
        self.result_queue = Queue.new

        start_pty_thread
        start_chunker_thread
        start_parser_thread
        start_result_thread

      rescue => e
        BtMon.logger.error("Runner master thread: #{e.message}")
        e.backtrace.each do |x|
          BtMon.logger.error("#{x}")
        end

      ensure
        stop

      end
    end

    def stop
      BtMon.logger.info("Runner exiting...")
      self.raw_queue    = nil
      self.chunk_queue  = nil
      self.result_queue = nil

      self.pty_thread.kill
      self.chunker_thread.kill
      self.parser_thread.kill
      self.result_thread.kill
    end

    def start_pty_thread
      BtMon.logger.info("PTY thread starting")
      pty_thread = Thread.new do
        begin
          spawner = BtMon::PtySpawner.new(
            self.command,
            self.raw_queue
          )
        rescue => e
          BtMon.logger.error("PTY thread #{e.message}")
          e.backtrace.each do |x|
            BtMon.logger.error("#{x}")
          end
        end
      end
    end

    def start_chunker_thread
      BtMon.logger.info("Chunker thread starting")
      chunker_thread = Thread.new do
        begin
          chunker = BtMon::Chunker.new(
            self.raw_queue,
            self.chunk_queue
          )
          chunker.chunk_it_up
        rescue => e
          BtMon.logger.error("Chunker thread #{e.message}")
          e.backtrace.each do |x|
            BtMon.logger.error("#{x}")
          end
        end
      end
    end

    def start_parser_thread
      BtMon.logger.info("Parser thread starting")
      parser_thread = Thread.new do
        begin
          while chunk = chunk_queue.pop do
            p = BtMon::Parser.new(chunk)
            p.parse
            BtMon.logger.info("Parser thread pushing results")
            result_queue.push(p.attributes)
          end
        rescue => e
          BtMon.logger.error("Parser thread #{e.message}")
          e.backtrace.each do |x|
            BtMon.logger.error("#{x}")
          end
        end
      end
    end

    def start_result_thread
      BtMon.logger.info("Result thread starting")
      result_thread = Thread.new do
        begin
          while result = result_q.pop do
            BtMon.logger.info("Result thread got result")
            if result[:address]
              address = result[:address].first

              file_path = File.expand_path(
                "../../../devices/#{address.gsub(':', '-')}_device_info.json", __FILE__
              )

              BtMon.logger.info("Result thread preparing for #{file_path}")

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
                  base[key] = values
                end
              end

              BtMon.logger.info("Result thread writing to #{file_path}")
              File.write(file_path, JSON.pretty_generate(base))
            else
              BtMon.logger.warn("Device without address #{JSON.generate(result)}")
            end
          end
        rescue => e
          BtMon.logger.error("Result thread #{e.message}")
          e.backtrace.each do |x|
            BtMon.logger.error("#{x}")
          end
        end
      end

    end
  end
end
