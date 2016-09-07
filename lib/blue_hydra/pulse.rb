module BlueHydra
  module Pulse
    def reset
      return unless BlueHydra.pulse
      BlueHydra.logger.info("Sending db reset to pulse")

      json_msg = JSON.generate({
        type:    "reset",
        source:  "blue-hydra",
        version: BlueHydra::VERSION,
      })
      BlueHydra::Pulse.do_send(json_msg)
    end

    def do_send(json)
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

    module_function :do_send, :reset
  end
end

