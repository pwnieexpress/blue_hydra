module BlueHydra

  # class responsible for parsing a group of message chunks into a serialized
  # hash appropriate to generate or update a device record.
  class Parser
    attr_accessor :attributes

    # initializer which takes an Array of chunks to be parsed
    #
    # == Parameters :
    #   chunks ::
    #     Array of message chunks which are arrays of lines of btmon output
    def initialize(chunks=[])
      @chunks     = chunks
      @attributes = {}

      # the first chunk  will determine the mode (le/classic) these message
      # fall into. This mode will be used to differentiate between setting
      # le or classic attributes during the parsing of this batch of chunks
      if @chunks[0] && @chunks[0][1]
        @bt_mode = @chunks[0][1] =~ /^\s+LE/ ? "le" : "classic"
      end
    end

    # this ithe main work method which processes the @chunks Array
    # and populates the @attributes
    def parse
      @chunks.each do |chunk|

        # the first line is no longer useful as we ahve extracted the mode and
        # timestamp at other points in the pipeline. Time to discard it
        chunk.shift

        # the last message will always be a timestamp from the chunker, this
        # value is used throughout during this parsing process but should
        # also be set to last_seen
        timestamp = chunk.pop
        set_attr(:last_seen, timestamp.split(': ')[1].to_i)

        # group the chunk of lines into nested / related groups of data
        # containing 1 or more lines
        grouped_chunk = group_by_depth(chunk)

        # handle each chunk of grouped data individually
        handle_grouped_chunk(grouped_chunk, @bt_mode, timestamp)
      end
    end

    # The main parser case statement to handle grouped message data from a
    # given chunk
    #
    # == Parameters
    #   grouped_chunk ::
    #     Array of lines to be processed
    #   bt_mode ::
    #     String of "le" or "classic"
    #   timestamp ::
    #     Unix timestamp for when this message data was created
    def handle_grouped_chunk(grouped_chunk, bt_mode, timestamp)
      grouped_chunk.each do |grp|

        # when we only have a single line in a group we can handle simply
        if grp.count == 1
          line = grp[0]

          # next line was not nested, treat as single line
          parse_single_line(line, bt_mode, timestamp)

        # if we have multiple lines in our group of lines determine how to
        # process and set
        else
          case

          # these special messags had effectively duplicate header lines
          # which is be shifted off and then re-grouped
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
            set_attr("#{bt_mode}_service_uuids".to_sym, uuid.split(': ')[1])

          when grp[0] =~ /^\s+Flags:/
            grp.shift
            vals = grp.map(&:strip)
            set_attr("#{bt_mode}_flags".to_sym, vals.join(", "))


          # Page: 1/1
          # Features: 0x07 0x00 0x00 0x00 0x00 0x00 0x00 0x00
          #   Secure Simple Pairing (Host Support)
          #   LE Supported (Host)
          #   Simultaneous LE and BR/EDR (Host)
          when grp[0] =~ /^\s+Page/
            page   = grp.shift.split(':')[1].strip.split('/')[0]
            bitmap = grp.shift.split(':')[1].strip
            vals = grp.map(&:strip)
            set_attr("#{bt_mode}_features_bitmap".to_sym, [page, bitmap])
            set_attr("#{bt_mode}_features".to_sym, vals.join(", "))

          # Features: 0x07 0x00 0x00 0x00 0x00 0x00 0x00 0x00
          #   Secure Simple Pairing (Host Support)
          #   LE Supported (Host)
          #   Simultaneous LE and BR/EDR (Host)
          when grp[0] =~ /^\s+Features/
            bitmap = grp.shift.split(':')[1].strip
            vals = grp.map(&:strip)

            # default page value is here set to '0'
            set_attr("#{bt_mode}_features_bitmap".to_sym, ['0',bitmap])
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
               set_attr("#{bt_mode}_service_uuids".to_sym, uuid)
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
                 set_attr("#{bt_mode}_service_uuids".to_sym, line.split(': ')[1])
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
               set_attr("#{bt_mode}_uuids".to_sym, uuid)
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

    # Determine the depth of the whitespace characters in a line
    #
    # == Parameters
    #   line ::
    #     the line to test]
    # == Returns
    #   Integer value for number of whitespace chars
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

      # TODO make use of handle
      when line =~ /^Handle:/
        set_attr("#{bt_mode}_handle".to_sym, line.split(': ')[1])

      when line =~ /^Address:/ || line =~ /^Peer address:/
        addr, *addr_type = line.split(': ')[1].split(" ")
        set_attr("address".to_sym, addr)

        if bt_mode == "le"
          set_attr("le_random_address_type".to_sym, addr_type.join(' '))
        end

      when line =~ /^LMP version:/
        set_attr("lmp_version".to_sym, line.split(': ')[1])

      when line =~ /^Manufacturer:/
        set_attr("manufacturer".to_sym, line.split(': ')[1])

      when line =~ /^UUID:/
        set_attr("#{bt_mode}_service_uuids".to_sym, line.split(': ')[1])

      when line =~ /^Address type:/
        set_attr("#{bt_mode}_address_type".to_sym, line.split(': ')[1])

      when line =~ /^TX power:/
        set_attr("#{bt_mode}_tx_power".to_sym, line.split(': ')[1])

      when line =~ /^Name \(short\):/
        set_attr("short_name".to_sym, line.split(': ')[1])

      when line =~ /^Name:/ || line =~ /^Name \(complete\):/
        set_attr("name".to_sym, line.split(': ')[1])

      when line =~ /^Firmware:/
        set_attr(:firmware, line.split(': ')[1])

      when line =~ /^Service Data \(/
        set_attr("#{bt_mode}_service_uuids".to_sym, line.split('Service Data ')[1])

      #  "Appearance: Watch (0x00c0)"
      when line =~ /^Appearance:/
        set_attr(:appearance, line.split(': ')[1])

      when line =~ /^RSSI:/
        set_attr("#{bt_mode}_rssi".to_sym, {
          t: timestamp.split(': ')[1].to_i,
          rssi: line.split(': ')[1].split(' ')[0,2].join(' ')
        })

      else
        set_attr("#{bt_mode}_unknown".to_sym, line)
      end
    end

    # group the lines of an array of lines in a chunk together by there depth
    #
    # == Parameters:
    #   arr ::
    #     Array of lines
    # == Returns:
    #   Array of arrays of grouped lines
    def group_by_depth(arr)
      output = []

      nested = false
      arr.each do |x|

        if output.last

          last_line = output.last[-1]

          if line_depth(last_line) == line_depth(x)

            if x =~ /Features:/ && last_line =~ /Page: \d/
              nested = true
            end

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

    # set an attribute key with a value in the @attributes hash
    #
    # This defaults the values in the @attributes to be an array of (ideally 1)
    # value so that we can test for mismatched messages
    #
    # == Parameters:
    #   key ::
    #     key to set
    #   val ::
    #     value to inject into the key in @attributes
    def set_attr(key, val)
      @attributes[key] ||= []
      @attributes[key] << val
    end
  end
end
