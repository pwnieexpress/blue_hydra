module BtMon
  class Parser
    attr_accessor :attributes

    def initialize(chunks=[])
      @chunks     = chunks
      @attributes = {}
    end

    def parse
      @chunks.each do |chunk|
        chunk.shift # discard first line

        grouped_chunk = group_by_depth(chunk)
        handle_grouped_chunk(grouped_chunk)
      end
    end

    def handle_grouped_chunk(grouped_chunk)
      grouped_chunk.each do |grp|
        if grp.count == 1
          line = grp[0]

          # next line is not nested, treat as single line
          parse_single_line(line)
        else
          case
          when grp[0] =~ /^\s+(LE|ATT|L2CAP)/
            grp.shift
            grp = group_by_depth(grp)
            grp.each do |entry|
              if entry.count == 1
                line = entry[0]
                parse_single_line(line)
              else
                handle_grouped_chunk(grp)
              end
            end

          when grp[0] =~ /^\s+Features/
            header = grp.shift.split(':')[1].strip
            vals = grp.map(&:strip)
            vals.unshift(header)
            set_attr(:features, vals.join(", "))

          when grp[0] =~ /^\s+Channels/
            header = grp.shift.split(':')[1].strip
            vals = grp.map(&:strip)
            vals.unshift(header)
            set_attr(:channels, vals.join(", "))

            # not in spec fixtures...
            # "        128-bit Service UUIDs (complete): 2 entries\r\n",
            # "          00000000-deca-fade-deca-deafdecacafe\r\n",
            # "          2d8d2466-e14d-451c-88bc-7301abea291a\r\n",
           when grp[0] =~ /128-bit Service UUIDs \(complete\):/
             grp.shift # header line
             vals = grp.map(&:strip)
             vals.each do |uuid|
               set_attr(:'128_bit_service_uuids', uuid)
             end

           # not in spec fixtures...
           # "        16-bit Service UUIDs (complete): 7 entries\r\n",
           # "          PnP Information (0x1200)\r\n",
           # "          Handsfree Audio Gateway (0x111f)\r\n",
           # "          Phonebook Access Server (0x112f)\r\n",
           # "          Audio Source (0x110a)\r\n",
           # "          A/V Remote Control Target (0x110c)\r\n",
           # "          NAP (0x1116)\r\n",
           # "          Message Access Server (0x1132)\r\n",
           when grp[0] =~ /16-bit Service UUIDs \(complete\):/
             grp.shift # header line
             vals = grp.map(&:strip)
             vals.each do |uuid|
               set_attr(:'16_bit_service_uuids', uuid)
             end

           # not in spec fixtures...
           # "        Class: 0x7a020c\r\n",
           # "          Major class: Phone (cellular, cordless, payphone, modem)\r\n",
           # "          Minor class: Smart phone\r\n",
           # "          Networking (LAN, Ad hoc)\r\n",
           # "          Capturing (Scanner, Microphone)\r\n",
           # "          Object Transfer (v-Inbox, v-Folder)\r\n",
           # "          Audio (Speaker, Microphone, Headset)\r\n",
           # "          Telephony (Cordless telephony, Modem, Headset)\r\n",

           when grp[0] =~ /Class:/
             grp = grp.map(&:strip)
             vals = []

             grp.each do |line|
               case
               when line =~ /^Class:/
                 vals << line.split(':')[1].strip
               when line =~ /^Major class:/
                 set_attr(:major_class, line.split(':')[1].strip)
               when line =~ /^Minor class:/
                 set_attr(:minor_class, line.split(':')[1].strip)
               else
                 vals << line
               end
             end

             set_attr(:class, vals) unless vals.empty?

           when grp[0] =~ /^\s+Manufacturer/
             grp.map do |line|
              parse_single_line(line)
            end


          else
            set_attr(:unknown, grp.inspect)
          end
        end
      end
    end

    def line_depth(line)
      whitespace = line.scan(/^([\s]+)/).flatten.first
      if whitespace
        whitespace.length
      else
        0
      end
    end

    # TODO dry this sucker up
    def parse_single_line(line)
      line = line.strip
      case
      when line =~ /^Status:/
        set_attr(:status, line.split(': ')[1])

      when line =~ /^Handle:/
        set_attr(:handle, line.split(': ')[1])

      when line =~ /^Address:/
        addr, *oui = line.split(': ')[1].split(" ")
        set_attr(:address, addr)
        set_attr(:oui, oui.join(' '))

      when line =~ /^Encryption:/
        set_attr(:encryption, line.split(': ')[1])

      when line =~ /^Link type:/
        set_attr(:link_type, line.split(': ')[1])

      when line =~ /^Role:/
        set_attr(:role, line.split(': ')[1])

      when line =~ /^Peer address type:/
        set_attr(:peer_address_type, line.split(': ')[1])

      when line =~ /^Peer address:/
        addr, *oui = line.split(': ')[1].split(" ")
        set_attr(:peer_address, addr)
        set_attr(:peer_address_oui, oui.join(' '))

      when line =~ /^Connection interval:/
        set_attr(:connection_interval, line.split(': ')[1])

      when line =~ /^Connection latency:/
        set_attr(:connection_latency, line.split(': ')[1])

      when line =~ /^Supervision timeout:/
        set_attr(:supervision_timeout, line.split(': ')[1])

      when line =~ /^Master clock accuracy:/
        set_attr(:master_clock_accuracy, line.split(': ')[1])

      when line =~ /^Master clock accuracy:/
        set_attr(:master_clock_accuracy, line.split(': ')[1])

      when line =~ /^LMP version:/
        set_attr(:lmp_version, line.split(': ')[1])

      when line =~ /^Manufacturer:/
        set_attr(:manufacturer, line.split(': ')[1])

      when line =~ /^Server RX MTU:/
        set_attr(:server_rx_mtu, line.split(': ')[1])

      when line =~ /^Handle range:/
        set_attr(:handle_range, line.split(': ')[1])

      when line =~ /^UUID:/
        set_attr(:uuid, line.split(': ')[1])

      when line =~ /^Min interval:/
        set_attr(:min_interval, line.split(': ')[1])

      when line =~ /^Max interval:/
        set_attr(:max_interval, line.split(': ')[1])

      when line =~ /^Slave latency:/
        set_attr(:slave_latency, line.split(': ')[1])

      when line =~ /^Timeout multiplier:/
        set_attr(:timeout_multiplier, line.split(': ')[1])

      when line =~ /^Attribute group type:/
        set_attr(:attribute_group_type, line.split(': ')[1])

      when line =~ /^Max slots:/
        set_attr(:max_slots, line.split(': ')[1])

      when line =~ /^Page:/
        set_attr(:page, line.split(': ')[1])

      when line =~ /^Type:/
        set_attr(:type, line.split(': ')[1])

      when line =~ /^Name:/ || line =~ /^Name \(complete\):/
        set_attr(:name, line.split(': ')[1])

      when line =~ /^Firmware:/
        set_attr(:firmware, line.split(': ')[1])

      when line =~ /^Error:/
        set_attr(:error, line.split(': ')[1])

      when line =~ /^Attribute type:/
        set_attr(:attribute_type, line.split(': ')[1])

      when line =~ /^Read By Group Type Request/
        set_attr(:read_by_group_type_request, line.split(': ')[1])

      when line =~ /^Read By Type Request/
        set_attr(:read_by_type_request, line.split(': ')[1])

      when line =~ /^Num responses/
        set_attr(:num_responses, line.split(': ')[1])

      when line =~ /^Page scan repetition mode:/
        set_attr(:page_scan_repetition_mode, line.split(': ')[1])

      when line =~ /^Page period mode:/
        set_attr(:page_period_mode, line.split(': ')[1])

      when line =~ /^Clock offset:/
        set_attr(:clock_offset, line.split(': ')[1])

      when line =~ /^RSSI:/
        set_attr(:rssi, line.split(': ')[1])

      when line =~ /^(Attribute (data length|group list)|Reason|Result):/
        # do nothing

      else
        set_attr(:unknown, line) #catch all
      end
    end

    def group_by_depth(arr)
      output = []

      nested = false
      arr.each do |x|
        if output.last

          last_line = output.last[-1]

          if line_depth(last_line) == line_depth(x)

            if nested
              output.last << x
            else
              output << [x]
            end

          elsif line_depth(last_line) > line_depth(x)
            # we are outdenting
            nested = false
            output << [x]

          elsif line_depth(last_line) < line_depth(x)
            # we are indenting further
            nested = true
            output.last << x
          end
        else
          output << [x]
        end
      end

      output
    end

    def set_attr(key, val)
      @attributes[key] ||= []
      @attributes[key] << val
    end
  end
end
