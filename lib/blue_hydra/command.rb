module BlueHydra::Command
  # execute a command using Open3
  #
  # == Parameters
  #   command ::
  #     the command to execute
  #
  # == Returns
  #   Hash containing :stdout, :stderr, :exit_code from the command
  def execute3(command, timeout=false, timeout_signal="SIGKILL")
    begin
    BlueHydra.logger.debug("Executing Command: #{command}")
    output = {}
    if timeout
      stop_time = Time.now.to_i + timeout.to_i
    end

    stdin, stdout, stderr, thread = Open3.popen3(command)
    stdin.close

    if timeout
      until Time.now.to_i > stop_time || thread.status == false
        sleep 1
      end

      begin
        Process.kill(timeout_signal, thread.pid) unless thread.status == false
      rescue Errno::ESRCH
        BlueHydra.logger.warn("Command: #{command} exited unnaturally.")
        BlueHydra::Pulse.send_event("blue_hydra",
        {key:'blue_hydra_command_error',
        title:'Blue Hydra subprocess exited unnaturally',
        message:"Command: #{command} exited unnaturally.",
        severity:'WARN'
        })
      end
    end

    if (out = stdout.read.chomp) != ""
      output[:stdout]    = out
    end

    if (err = stderr.read.chomp) != ""
      output[:stderr]    = err
    end

    output[:exit_code] = thread.value.exitstatus

    output
    rescue Errno::ENOMEM, NoMemoryError
      BlueHydra::Pulse.send_event('blue_hydra',
      {
        key: "bluehydra_oom",
        title: "BlueHydra couldnt allocate enough memory to run external command. Sensor OOM.",
        message: "BlueHydra couldnt allocate enough memory to run external command. Sensor OOM.",
        severity: "FATAL"
      })
      exit 1
    end
  end

  module_function :execute3
end
