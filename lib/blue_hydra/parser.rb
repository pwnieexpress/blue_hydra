module BlueHydra
  class Parser
    attr_accessor :attributes

    def initialize(chunks=[])
      @chunks     = chunks
      @attributes = {}
    end

    def parse
      @chunks.each do |chunk|
        chunk.shift # discard first line

        bt_mode = chunk[0] =~ /^\s+LE/ ? "le" : "classic"

        grouped_chunk = group_by_depth(chunk)
        handle_grouped_chunk(grouped_chunk, bt_mode)
      end
    end

    def handle_grouped_chunk(grouped_chunk, bt_mode)
      grouped_chunk.each do |grp|
        if grp.count == 1
          line = grp[0]

          # next line is not nested, treat as single line
          parse_single_line(line, bt_mode)
        else
          case
          when grp[0] =~ /^\s+(LE|ATT|L2CAP)/
            grp.shift
            grp = group_by_depth(grp)
            grp.each do |entry|
              if entry.count == 1
                line = entry[0]
                parse_single_line(line, bt_mode)
              else
                handle_grouped_chunk(grp, bt_mode)
              end
            end

          when grp[0] =~ /^\s+Features/
            header = grp.shift.split(':')[1].strip
            vals = grp.map(&:strip)
            vals.unshift(header)
            set_attr("#{bt_mode}_features".to_sym, vals.join(", "))

          when grp[0] =~ /^\s+Channels/
            header = grp.shift.split(':')[1].strip
            vals = grp.map(&:strip)
            vals.unshift(header)
            set_attr("#{bt_mode}_channels".to_sym, vals.join(", "))

            # not in spec fixtures...
            # "        128-bit Service UUIDs (complete): 2 entries\r\n",
            # "          00000000-deca-fade-deca-deafdecacafe\r\n",
            # "          2d8d2466-e14d-451c-88bc-7301abea291a\r\n",
           when grp[0] =~ /128-bit Service UUIDs \(complete\):/
             grp.shift # header line
             vals = grp.map(&:strip)
             vals.each do |uuid|
               set_attr("#{bt_mode}_128_bit_service_uuids".to_sym, uuid)
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
               set_attr("#{bt_mode}_16_bit_service_uuids".to_sym, uuid)
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
                 set_attr("#{bt_mode}_major_class".to_sym, line.split(':')[1].strip)
               when line =~ /^Minor class:/
                 set_attr("#{bt_mode}_minor_class".to_sym, line.split(':')[1].strip)
               else
                 vals << line
               end
             end

             set_attr("#{bt_mode}_class".to_sym, vals) unless vals.empty?

           when grp[0] =~ /^\s+Manufacturer/
             grp.map do |line|
              parse_single_line(line, bt_mode)
            end

          else
            set_attr("#{bt_mode}_unknown".to_sym, grp.inspect)
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
    def parse_single_line(line, bt_mode)
      line = line.strip
      case
      when line =~ /^Status:/
        set_attr("#{bt_mode}_status".to_sym, line.split(': ')[1])

      when line =~ /^Handle:/
        set_attr("#{bt_mode}_handle".to_sym, line.split(': ')[1])

      when line =~ /^Address:/
        addr, *oui = line.split(': ')[1].split(" ")
        set_attr("address".to_sym, addr)
        set_attr("oui".to_sym, oui.join(' '))

      when line =~ /^Encryption:/
        set_attr("#{bt_mode}_encryption".to_sym, line.split(': ')[1])

      when line =~ /^Link type:/
        set_attr("#{bt_mode}_link_type".to_sym, line.split(': ')[1])

      when line =~ /^Role:/
        set_attr("#{bt_mode}_role".to_sym, line.split(': ')[1])

      when line =~ /^Peer address type:/
        set_attr("#{bt_mode}_peer_address_type".to_sym, line.split(': ')[1])

      when line =~ /^Peer address:/
        addr, *oui = line.split(': ')[1].split(" ")
        set_attr("#{bt_mode}_peer_address".to_sym, addr)
        set_attr("#{bt_mode}_peer_address_oui".to_sym, oui.join(' '))

      when line =~ /^Connection interval:/
        set_attr("#{bt_mode}_connection_interval".to_sym, line.split(': ')[1])

      when line =~ /^Connection latency:/
        set_attr("#{bt_mode}_connection_latency".to_sym, line.split(': ')[1])

      when line =~ /^Supervision timeout:/
        set_attr("#{bt_mode}_supervision_timeout".to_sym, line.split(': ')[1])

      when line =~ /^Master clock accuracy:/
        set_attr("#{bt_mode}_master_clock_accuracy".to_sym, line.split(': ')[1])

      when line =~ /^LMP version:/
        set_attr("#{bt_mode}_lmp_version".to_sym, line.split(': ')[1])

      when line =~ /^Manufacturer:/
        set_attr("#{bt_mode}_manufacturer".to_sym, line.split(': ')[1])

      when line =~ /^Server RX MTU:/
        set_attr("#{bt_mode}_server_rx_mtu".to_sym, line.split(': ')[1])

      when line =~ /^Handle range:/
        set_attr("#{bt_mode}_handle_range".to_sym, line.split(': ')[1])

      when line =~ /^UUID:/
        set_attr("#{bt_mode}_uuid".to_sym, line.split(': ')[1])

      when line =~ /^Min interval:/
        set_attr("#{bt_mode}_mint_interval".to_sym, line.split(': ')[1])

      when line =~ /^Max interval:/
        set_attr("#{bt_mode}_max_interval".to_sym, line.split(': ')[1])

      when line =~ /^Slave latency:/
        set_attr("#{bt_mode}_slave_latency".to_sym, line.split(': ')[1])

      when line =~ /^Timeout multiplier:/
        set_attr("#{bt_mode}_timeout_multiplier".to_sym, line.split(': ')[1])

      when line =~ /^Attribute group type:/
        set_attr("#{bt_mode}_attribute_group_type".to_sym, line.split(': ')[1])

      when line =~ /^Max slots:/
        set_attr("#{bt_mode}_max_slots".to_sym, line.split(': ')[1])

      when line =~ /^Page:/
        set_attr("#{bt_mode}_page".to_sym, line.split(': ')[1])

      when line =~ /^Type:/
        set_attr("#{bt_mode}_type".to_sym, line.split(': ')[1])

      when line =~ /^Name:/ || line =~ /^Name \(complete\):/
        set_attr("name".to_sym, line.split(': ')[1])

      when line =~ /^Firmware:/
        set_attr("#{bt_mode}_firmware".to_sym, line.split(': ')[1])

      when line =~ /^Error:/
        set_attr("#{bt_mode}_error".to_sym, line.split(': ')[1])

      when line =~ /^Attribute type:/
        set_attr("#{bt_mode}_attribute_type".to_sym, line.split(': ')[1])

      when line =~ /^Read By Group Type Request/
        set_attr("#{bt_mode}_read_by_group_type_request".to_sym, line.split(': ')[1])

      when line =~ /^Read By Type Request/
        set_attr("#{bt_mode}_read_by_type_request".to_sym, line.split(': ')[1])

      when line =~ /^Num responses/
        set_attr("#{bt_mode}_num_responses".to_sym, line.split(': ')[1])

      when line =~ /^Page scan repetition mode:/
        set_attr("#{bt_mode}_page_scan_repetition_mode".to_sym, line.split(': ')[1])

      when line =~ /^Page period mode:/
        set_attr("#{bt_mode}_page_period_mode".to_sym, line.split(': ')[1])

      when line =~ /^Clock offset:/
        set_attr("#{bt_mode}_clock_offset".to_sym, line.split(': ')[1])

      when line =~ /^RSSI:/
        set_attr("#{bt_mode}_rssi".to_sym, line.split(': ')[1])

      when line =~ /^last_seen_at:/
        set_attr(:last_seen_at, line.split(': ')[1].to_i)

      when line =~ /^(Attribute (data length|group list)|Reason|Result):/
        # do nothing

      else
        set_attr("#{bt_mode}_unknown".to_sym, line)
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
