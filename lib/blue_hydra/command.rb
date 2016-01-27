module BlueHydra::Command
  # execute a command using Open3
  #
  # == Parameters
  #   command ::
  #     the command to execute
  #
  # == Returns
  #   Hash containing :stdout, :stderr, :exit_code from the command
  def execute3(command)
    BlueHydra.logger.debug("Executing Command: #{command}")
    output = {}

    Open3.popen3(command) do |stdin, stdout, stderr, thread|
      stdin.close
      if (out = stdout.read.chomp) != ""
        output[:stdout]    = out
      end

      if (err = stderr.read.chomp) != ""
        output[:stderr]    = err
      end

      output[:exit_code] = thread.value.exitstatus
    end

    output
  end

  module_function :execute3
end
