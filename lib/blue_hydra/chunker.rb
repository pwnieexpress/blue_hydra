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
          @outgoing_q.push working_set
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

      chunk_zero_strings =[
        "Connect Complete",
        "Role Change",
        "Extended Inqu",
        "Inquiry Result",
        "Remote Name Req",
        "Remote Host Supported",
        "Connect Request"
      ]

      # if the first line of the message chunk matches one of these patterns
      # it indicates a start chunk
      if chunk[0] =~ /#{chunk_zero_strings.join('|')}/
        true

      # LE start chunks are identified by patterns in their first and second
      # lines
      elsif chunk[0] =~ /LE Meta Event/ &&
            chunk[1] =~ /LE Connection Complete|LE Advertising Report/
        true

      # otherwise this will get grouped with the current working set in the
      # chunk it up method
      else
        false
      end
    end
  end
end
