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

        current_msg << "last_seen: #{Time.now.to_i}"
        working_set << current_msg
      end
    end

    def starting_chunk?(chunk=[])
      key_line = chunk.first

      if key_line =~ /Connect Complete|Role Change|Extended Inqu|LE Meta Event|Inquiry Result/
        true
      else
        false
      end
    end
  end
end
