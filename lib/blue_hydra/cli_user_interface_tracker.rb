module BlueHydra
  class CliUserInterfaceTracker
    def initialize(run, chnk, attrs, addr)
      @runner = run
      @chunk = chnk
      @attrs = attrs
      @address = addr
    end

    def runner
      @runner
    end

    def chunk
      @chunk
    end

    def attrs
      @attrs
    end

    def address
      @address
    end

    def cui_status
      @runner.cui_status
    end

    def update_cui_status
      cui_status[address] ||= {created: Time.now.to_i}
      cui_status[address][:lap] = address.split(":")[3,3].join(":") unless cui_status[address][:lap]

      if chunk[0] && chunk[0][0]
        bt_mode = chunk[0][0] =~ /^\s+LE/ ? "le" : "classic"
      end

      if bt_mode == "le"
        cui_status[address][:vers] = "btle"
      else
        if attrs[:lmp_version]
          cui_status[address][:vers] = "#{attrs[:lmp_version].first.split(" ")[1]}C"
        elsif !cui_status[address][:vers]
          cui_status[address][:vers] = "C/BR"
        end
      end

      [
        :last_seen, :name, :address, :classic_rssi, :le_rssi
      ].each do |key|
        if attrs[key] && attrs[key].first
          if cui_status[address][key] != attrs[key].first
            if key == :le_rssi || key == :classic_rssi
              cui_status[address][:rssi] = attrs[key].first[:rssi].gsub('dBm','')
            else
              cui_status[address][key] = attrs[key].first
            end
          end
        end
      end

      if attrs[:short_name]
        unless attrs[:short_name] == [nil] || cui_status[address][:name]
          cui_status[address][:name] = attrs[:short_name].first
          BlueHydra.logger.warn("short name found: #{attrs[:short_name]}")
        end
      end

      if attrs[:appearance]
        cui_status[address][:type] = attrs[:appearance].first.split('(').first
      end

      if attrs[:classic_minor_class]
        if attrs[:classic_minor_class].first =~ /Uncategorized/i
          cui_status[address][:type] = "Uncategorized"
        else
          cui_status[address][:type] = attrs[:classic_minor_class].first.split('(').first
        end
      end

      if bt_mode == "classic" || (attrs[:le_address_type] && attrs[:le_address_type].first =~ /public/i)
        unless cui_status[address][:manuf]
          vendor = Louis.lookup(address)

          cui_status[address][:manuf] = if vendor["short_vendor"]
                                          vendor["short_vendor"]
                                        else
                                          vendor["long_vendor"]
                                        end
        end
      else
        cmp = nil

        if attrs[:company_type] && attrs[:company_type].first !~ /unknown/i
          cmp = attrs[:company_type].first
        elsif attrs[:company] && attrs[:company].first !~ /not assigned/i
          cmp = attrs[:company].first
        else
          cmp = "Unknown"
        end

        if cmp
          cui_status[address][:manuf] = cmp.split('(').first
        end
      end
    end
  end
end
