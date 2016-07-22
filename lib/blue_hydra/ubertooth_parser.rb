module BlueHydra
  module UbertoothParser

    def parse(output)
      raw_data = {}
      uaplaps = []
      parsed_data = []

      output.each_line do |ln|
        # TODO get better regex
        if ln =~ /^\?\?:\?\?:[a-f0-9]/i
          uaplaps << ln.chomp
        elsif  ln =~ /^systime/
          raw_hsh = Hash[*ln.split(/\s/).map{|x| x.split("=")}.flatten]
          lap = raw_hsh['LAP']
          raw_data[lap] ||= []
          # {
          #   "systime"=>"1469198646",
          #   "ch"=>"9",
          #   "LAP"=>"00024c",
          #   "err"=>"0",
          #   "clk100ns"=>"390478983",
          #   "clk1"=>"62477",
          #   "s"=>"-50",
          #   "n"=>"-73",
          #   "snr"=>"23"
          # }
          hsh = {
            last_seen: raw_hsh["systime"],
            classic_rssi: raw_hsh["s"]
          }
          raw_data[lap] << hsh
        end
      end # each_line

      # TODO: fix nested each :(
      raw_data.keys.each do |lap|
        matters = false
        match = nil
        clean_uaplap = nil
        match_uaplap = nil

        uaplaps.each do |uaplap|
          unless match
            clean_uaplap = uaplap.split(/\s+/)[0]
            match_uaplap = clean_uaplap.gsub(':','')
            if match_uaplap =~ /#{lap}$/i
              matters = true
              match = uaplap
            end
          end
        end

        if matters && match
          raw_data[lap].each do |d|
            d[:address] = clean_uaplap

            parsed_data << d
          end
        end
      end

      parsed_data
    end

    module_function :parse
  end
end
