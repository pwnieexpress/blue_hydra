
module BlueHydra
  class Parser
    attr_accessor :attributes

    def initialize(chunks=[])
      @chunks     = chunks
      @attributes = {}
      if @chunks[0] && @chunks[0][1]
        @bt_mode = @chunks[0][1] =~ /^\s+LE/ ? "le" : "classic"
      end
    end

    def parse
      @chunks.each do |chunk|
        chunk.shift # discard first line
        timestamp = chunk.pop

        set_attr(:last_seen, timestamp.split(': ')[1].to_i)

        grouped_chunk = group_by_depth(chunk)
        handle_grouped_chunk(grouped_chunk, @bt_mode, timestamp)
      end
    end

    def handle_grouped_chunk(grouped_chunk, bt_mode, timestamp)
      grouped_chunk.each do |grp|
        if grp.count == 1
          line = grp[0]

          # next line is not nested, treat as single line
          parse_single_line(line, bt_mode, timestamp)
        else
          case
          when grp[0] =~ /^\s+(LE|ATT|L2CAP)/
            grp.shift
            grp = group_by_depth(grp)
            grp.each do |entry|
              if entry.count == 1
                line = entry[0]
                parse_single_line(line, bt_mode, timestamp)
              else
                handle_grouped_chunk(grp, bt_mode, timestamp)
              end
            end

          # Attribute type: Primary Service (0x2800)
          #  UUID: Unknown (7905f431-b5ce-4e99-a40f-4b1e122d00d0)
          when grp[0] =~ /^\s+Attribute type: Primary Service/
            vals = grp.map(&:strip)
            uuid = vals.select{|x| x =~ /^UUID/}[0]

            set_attr(:primary_service, uuid.split(': ')[1])

          when grp[0] =~ /^\s+Flags:/
            grp.shift
            vals = grp.map(&:strip)
            set_attr("#{bt_mode}_flags".to_sym, vals.join(", "))

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
           when grp[0] =~ /128-bit Service UUIDs \((complete|partial)\):/
             grp.shift # header line
             vals = grp.map(&:strip)
             vals.each do |uuid|
               set_attr("#{bt_mode}_128_bit_service_uuids".to_sym, uuid)
             end

           # Company: Apple, Inc. (76)
           #   Type: iBeacon (2)
           #   UUID: 7988f2b6-dc41-1291-8746-ecf83cc7a06c
           #   Version: 15104.61591
           #   TX power: -56 dB
           when grp[0] =~ /Company:/
             vals = grp.map(&:strip)

             set_attr(:company, vals.shift.split(': ')[1])

             vals.each do |line|
               case
               when line =~ /^Type:/
                 set_attr(:company_type, line.split(': ')[1])
               when line =~ /^UUID:/
                 set_attr(:company_uuid, line.split(': ')[1])
               when line =~ /^TX power:/
                 set_attr("#{bt_mode}_tx_power".to_sym, line.split(': ')[1])
               end
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
              parse_single_line(line, bt_mode, timestamp)
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

    def parse_single_line(line, bt_mode, timestamp)
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

      when line =~ /^Role:/
        set_attr("#{bt_mode}_role".to_sym, line.split(': ')[1])

      #  Peer Adress is when our device connects to this device so treat as
      #  the device address
      when line =~ /^Peer address type:/
        set_attr("#{bt_mode}_address_type".to_sym, line.split(': ')[1])

      when line =~ /^Peer address:/
        addr, *oui = line.split(': ')[1].split(" ")
        set_attr("address".to_sym, addr)
        set_attr("oui".to_sym, oui.join(' '))

      when line =~ /^LMP version:/
        set_attr("#{bt_mode}_lmp_version".to_sym, line.split(': ')[1])

      when line =~ /^Manufacturer:/
        set_attr("#{bt_mode}_manufacturer".to_sym, line.split(': ')[1])

      when line =~ /^Handle range:/
        set_attr("#{bt_mode}_handle_range".to_sym, line.split(': ')[1])

      when line =~ /^UUID:/
        set_attr("#{bt_mode}_uuid".to_sym, line.split(': ')[1])

      when line =~ /^Address type:/
        set_attr("#{bt_mode}_address_type".to_sym, line.split(': ')[1])

      when line =~ /^TX power:/
        set_attr("#{bt_mode}_tx_power".to_sym, line.split(': ')[1])

      when line =~ /^Name \(short\):/
        set_attr("short_name".to_sym, line.split(': ')[1])

      when line =~ /^Name:/ || line =~ /^Name \(complete\):/
        set_attr("name".to_sym, line.split(': ')[1])

      when line =~ /^Firmware:/
        set_attr("#{bt_mode}_firmware".to_sym, line.split(': ')[1])

      when line =~ /^Service Data \(/
        set_attr(:service_data, line.split('Service Data ')[1])

      #  "Appearance: Watch (0x00c0)"
      when line =~ /^Appearance:/
        set_attr(:appearance, line.split(': ')[1])

      when line =~ /^RSSI:/
        set_attr("#{bt_mode}_rssi".to_sym, {
          t: timestamp.split(': ')[1].to_i,
          rssi: line.split(': ')[1].split(' ')[0,2].join(' ')
        })

      # TODO review and remove unused keys...
      when line =~ /^(Attribute (data length|group list)|Reason|Result):/
      when line =~ /^Num responses/
      when line =~ /^Error:/
      when line =~ /^Read By Group Type Request/
      when line =~ /^Read By Type Request/
      when line =~ /^Attribute type:/
      when line =~ /^Min interval:/
      when line =~ /^Max interval:/
      when line =~ /^Slave latency:/
      when line =~ /^Timeout multiplier:/
      when line =~ /^Attribute group type:/
      when line =~ /^Max slots:/
      when line =~ /^Page period mode:/
      when line =~ /^Page scan repetition mode:/
      when line =~ /^Type:/
      when line =~ /^Connection interval:/
      when line =~ /^Connection latency:/
      when line =~ /^Supervision timeout:/
      when line =~ /^Master clock accuracy:/
      when line =~ /^Server RX MTU:/
      when line =~ /^Page:/
      when line =~ /^Link type:/
      when line =~ /^Clock offset:/
      when line =~ /^Num reports:/
      when line =~ /^Event type:/
      when line =~ /^Data length:/
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
