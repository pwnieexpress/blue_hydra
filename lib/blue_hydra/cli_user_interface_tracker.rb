require 'securerandom'

module BlueHydra
  class CliUserInterfaceTracker
    attr_accessor :runner, :chunk, :attrs, :address, :uuid

    # This method initializes with a runner and some data and then handles
    # updating the cui_status to track the devices for the CUI
    #
    # == Parameters:
    #   run ::
    #     BlueHydra::Runner instance
    #   attrs ::
    #     record attributes to update with
    #   addr ::
    #     device addr
    def initialize(run, chnk, attrs, addr)
      @runner = run
      @chunk = chnk #todo, rm, deprecated
      @attrs = attrs
      @address = addr

      cui_k = cui_status.keys
      cui_v = cui_status.values

      match1 = cui_v.select{|x|
        x[:address] == @address
      }.first

      # if there is already a key with this address get the uuid from the
      # keys
      if match1
        @uuid = cui_k[cui_v.index(match1)]
      end

      # if we don't have uuid attempt a second match using le meta info
      unless @uuid
        @lpu  = attrs[:le_proximity_uuid].first if attrs[:le_proximity_uuid]
        @lmn  = attrs[:le_major_num].first      if attrs[:le_major_num]
        @lmn2 = attrs[:le_minor_num].first      if attrs[:le_minor_num]

        match2 = cui_v.select{|x|
          x[:le_proximity_uuid] && x[:le_proximity_uuid] == @lpu &&
          x[:le_major_num]      && x[:le_major_num]      == @lmn &&
          x[:le_minor_num]      && x[:le_minor_num]      == @lmn2
        }.first

        if match2
          @uuid = cui_k[cui_v.index(match2)]
        end
      end

      # if we don't have a uuid attempt a third match using company meta info
      unless @uuid
        @c = attrs[:company].first.split('(').first if attrs[:company]
        @d = attrs[:le_company_data].first          if attrs[:le_company_data]

        match3 = cui_v.select{|x|
          x[:company]          && x[:company] == @c &&
          x[:le_company_data]  && x[:le_company_data] == @d
        }.first

        if match3
          @uuid = cui_k[cui_v.index(match3)]
        end
      end

      # if still no uuid, generate a random one
      unless @uuid
        @uuid = SecureRandom.uuid
      end
    end

    # alias for cui status blob from the runner object
    def cui_status
      runner.cui_status
    end

    # update the cui_status in the runner
    def update_cui_status
      # initialize with a created timestampe or leave alone if uuid already exits
      cui_status[@uuid] ||= {created: Time.now.to_i}

      # update lap unless we have one
      cui_status[@uuid][:lap] = address.split(":")[3,3].join(":") unless cui_status[@uuid][:lap]

      # test to see if the data chunk is le or classic
      if chunk[0] && chunk[0][0]
        bt_mode = chunk[0][0] =~ /^\s+LE/ ? "le" : "classic"
      end

      # use lmp version to make a simplified copy of the version for table
      # display, set as :vers under the uuid key
      if bt_mode == "le"
        if attrs[:lmp_version] && attrs[:lmp_version].first !~ /0x(00|FF|ff)/
          cui_status[@uuid][:vers] = "LE#{attrs[:lmp_version].first.split(" ")[1]}"
        elsif !cui_status[@uuid][:vers]
          cui_status[@uuid][:vers] = "BTLE"
        end
      else
        if attrs[:lmp_version] && attrs[:lmp_version].first !~ /0x(00|ff|FF)/
          cui_status[@uuid][:vers] = "CL#{attrs[:lmp_version].first.split(" ")[1]}"
        elsif !cui_status[@uuid][:vers]
          cui_status[@uuid][:vers] = "CL/BR"
        end
      end

      # update the following attributes with a little of massaging to get the
      # attributes more presentable for human consumption
      [
        :last_seen, :name, :address, :classic_rssi, :le_rssi,
        :le_proximity_uuid, :le_major_num, :le_minor_num, :ibeacon_range,
        :company, :le_company_data
      ].each do |key|
        if attrs[key] && attrs[key].first
          if cui_status[@uuid][key] != attrs[key].first
            if key == :le_rssi || key == :classic_rssi
              cui_status[@uuid][:rssi] = attrs[key].first[:rssi].gsub('dBm','')
            elsif key == :ibeacon_range
              cui_status[@uuid][:range] = "#{attrs[key].first}m"
            elsif key == :company
              cui_status[@uuid][:company] = attrs[key].first.split('(').first
            else
              cui_status[@uuid][key] = attrs[key].first
            end
          end
        end
      end

      # simplified copy of internal tracking uuid
      cui_status[@uuid][:uuid] = @uuid.split('-')[0]

      # if we have a short name set it as the name attribute
      if attrs[:short_name]
        unless attrs[:short_name] == [nil] || cui_status[@uuid][:name]
          cui_status[@uuid][:name] = attrs[:short_name].first
          BlueHydra.logger.warn("short name found: #{attrs[:short_name]}")
        end
      end

      # set appearance
      if attrs[:appearance]
        cui_status[@uuid][:type] = attrs[:appearance].first.split('(').first
      end

      # set minor class or as uncategorized as appropriate
      if attrs[:classic_minor_class]
        if attrs[:classic_minor_class].first =~ /Uncategorized/i
          cui_status[@uuid][:type] = "Uncategorized"
        else
          cui_status[@uuid][:type] = attrs[:classic_minor_class].first.split('(').first
        end
      end

      # set :manuf key from a few different fields or Louis gem depending on a
      # few conditions, we are overloading this field so its populated
      if [nil, "Unknown"].include?(cui_status[@uuid][:manuf])
        if bt_mode == "classic" || (attrs[:le_address_type] && attrs[:le_address_type].first =~ /public/i)
            cui_status[@uuid][:manuf] = "Not set"
        else
          cmp = nil

          if attrs[:company_type] && attrs[:company_type].first !~ /unknown/i
            cmp = attrs[:company_type].first
          elsif attrs[:company] && attrs[:company].first !~ /not assigned/i
            cmp = attrs[:company].first
          elsif attrs[:manufacturer] && attrs[:manufacturer].first !~ /\(65535\)/
            cmp = attrs[:manufacturer].first
          else
            cmp = "Unknown"
          end

          if cmp
            cui_status[@uuid][:manuf] = cmp.split('(').first
          end
        end
      end
    end
  end
end
