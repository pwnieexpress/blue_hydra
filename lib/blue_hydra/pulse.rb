module BlueHydra
  module Pulse
    def reset
      if BlueHydra.pulse == false && BlueHydra.pulse_debug == false
        return
      end

      BlueHydra.logger.info("Sending db reset to pulse")

      json_msg = JSON.generate({
        type:    "reset",
        source:  "blue-hydra",
        version: BlueHydra::VERSION,
      })

      BlueHydra::Pulse.do_debug(json_msg) if BlueHydra.pulse_debug
      BlueHydra::Pulse.do_send(json_msg) if BlueHydra.pulse
    end

    def do_send(json)
      if BlueHydra.pulse_debug
        BlueHydra::Pulse.do_debug(json)
      end
      return unless BlueHydra.pulse
      # write json data to result socket
      TCPSocket.open('127.0.0.1', 8244) do |sock|
        sock.write(json)
        sock.write("\n")
        sock.flush
      end
    rescue => e
      BlueHydra.logger.warn "Unable to connect to Hermes (#{e.message}), unable to send to pulse"
    end

    def do_debug(json)
      File.open("pulse_debug.log", 'a') { |file| file.write(json) }
    end

    module_function :do_send, :reset
  end
end

