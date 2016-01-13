module BlueHydra
  class Chunker
    def initialize(incoming_q, outgoing_q)
      @incoming_q = incoming_q
      @outgoing_q = outgoing_q
    end

    def chunk_it_up
      working_set = []

      while current_msg = @incoming_q.pop
        if starting_chunk?(current_msg) && !working_set.empty?
            @outgoing_q.push working_set
            working_set = []
        end

        ts = Time.parse(current_msg.first.split(/\[hci[0-9]\] /)[-1]).to_i

        current_msg << "last_seen: #{ts}"
        working_set << current_msg
      end
    end

    def starting_chunk?(chunk=[])
      key_line = chunk[0]

      if chunk[0] =~ /Connect Complete|Role Change|Extended Inqu|Inquiry Result/
        true
      elsif chunk[0] =~ /LE Meta Event/ &&
            chunk[1] =~ /LE Connection Complete|LE Advertising Report/
        true
      else
        false
      end
    end
  end
end
