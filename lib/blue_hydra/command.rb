module BlueHydra::Command

  # execute a command using Open3
  def execute3(command)
    BlueHydra.logger.info("Executing Command: #{command}")
    output = {}

    Open3.popen3(command) do |stdin, stdout, stderr, thread|
      stdin.close
      output[:stdout]    = stdout.read.chomp
      output[:stderr]    = stderr.read.chomp
      output[:exit_code] = thread.value.exitstatus
    end

    output
  end

  module_function :execute3
end
