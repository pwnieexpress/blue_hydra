module BlueHydra
  # this class take incoming and outgoing queues and batches messages coming
  # out of the btmon handler
  class Chunker

    # initialize with incoming (from btmon) and outgoing (to parser) queues
    def initialize(incoming_q, outgoing_q)
      @incoming_q = incoming_q
      @outgoing_q = outgoing_q
    end

    # Worker method which takes in  batches of data from the incoming queue,
    # treating the messages as chunks of a set of data this method will
    # group the chunked messages into a bigger set and then flush to the
    # parser when a new device starts to appear
    def chunk_it_up

      # start with an empty working set before any messages have been received
      working_set = []

      # pop a chunk (array of lines of filtered btmon output) off the
      # incoming queue
      while current_msg = @incoming_q.pop

        # test if the message indicates the start of a new message
        #
        # also bypass if our working set is empty as this indicates we are
        # receiving our first device of the run
        if starting_chunk?(current_msg) && !working_set.empty?

          # if we just got a new message shovel the working set into the
          # outgoing queue and reset it
          address_count = working_set.join("").scan(/^\s*.*ddress: ((?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2})/).flatten.uniq.count
          if address_count == 1
            @outgoing_q.push working_set
          elsif address_count < 1
            if BlueHydra.config["chunker_debug"]
              working_set.flatten.each{|msg| BlueHydra.chunk_logger.info(msg.chomp) }
              BlueHydra.chunk_logger.info("-------------------------------------------------------------------------------")
            else
              BlueHydra.logger.warn("Got a chunk with no addresses, dazed and confused, discarding...")
            end
            BlueHydra::Pulse.send_event('blue_hydra',
            {
              key: 'bluehydra_chunk_0_address',
              title: 'BlueHydra chunked a chunk with 0 addresses.',
              message: 'BlueHydra chunked a chunk with 0 addresses',
              severity: 'FATAL'
            })
          else
            if BlueHydra.config["chunker_debug"]
              working_set.flatten.each{|msg| BlueHydra.chunk_logger.info(msg.chomp) }
              BlueHydra.chunk_logger.info("-------------------------------------------------------------------------------")
            else
              BlueHydra.logger.warn("Got a chunk with multiple addresss, missing a start block. Discarding corrupted data...")
            end
            BlueHydra::Pulse.send_event('blue_hydra',
            {
              key: 'bluehydra_chunk_2_address',
              title: 'BlueHydra chunked a chunk with more than 1 uniq address.',
              message: 'BlueHydra chunked a chunk with more than 1 uniq address.',
              severity: 'FATAL'
            })
          end
          #always clear the working set
          working_set = []
        end

        # inject a timestamp onto the message parsed out of the first line of
        # btmon output
        ts = Time.parse(current_msg.first.strip.scan(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}.\d*$/)[0]).to_i
        current_msg << "last_seen: #{ts}"

        # add the current message to the working set
        working_set << current_msg
      end
    end

    # test if the message indicates the start of a new message
    def starting_chunk?(chunk=[])

      # numbers from bluez monitor/packet.c static const struct event_data event_table
      chunk_zero_strings =[
        "03", # Connect Complete
        "12", # Role Change
        "2f", # Extended Inquiry Result
        "22", # Inquiry Result with RSSI
        "07", # Remote Name Req Complete
        "3d", # Remote Host Supported Features
        "04", # Connect Request
        "0e"  # Command Complete
      ]

      # if the first line of the message chunk matches one of these patterns
      # it indicates a start chunk
      if chunk[0] =~ / \(0x(#{chunk_zero_strings.join('|')})\)/
        true

      # LE start chunks are identified by patterns in their first and second
      # lines
      elsif chunk[0] =~ / \(0x3e\)/ && # LE Meta Event
        # Numbers from bluez monitor/packet.h static const struct subevent_data le_meta_event_table
            chunk[1] =~ / \(0x0[12]\)/ # LE Connection Complete / LE Advertising Report
        true

      # otherwise this will get grouped with the current working set in the
      # chunk it up method
      else
        false
      end
    end
  end
end
