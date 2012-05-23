module Hydra
  class TestProcessor
    traceable('RUNNER')

    attr_accessor :file, :verbose, :runner_num, :runner_opts, :exit_status, :hydra_output, :stdout

    def initialize(file, options = {})
      self.verbose = options[:verbose]
      self.runner_num = options[:runner_num]
      self.runner_opts = options[:runner_opts]
      self.file = file
    end

    def log_file_name
      "#{Dir.pwd}/log/spec_runner_#{@runner_num.to_s}.log"
    end

    def tee_flags
      @verbose ? "-a" : ""
    end

    def temp_output
      @temp_output ||= Tempfile.new("hydra")
    end

    def log_file
      temp_output.path
    end

    def failure_message
      <<-STR
      FAILURE: command:
        #{command}
      failed to complete, exiting with #{exit_status.inspect}, but produced:
      HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT
        #{hydra_output}
      HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT HYDRA OUTPUT

      with stdout:
      STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT
        #{stdout}
      STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT STDOUT
      STR
    end

    def run_test_command
      old_env = ENV['RAILS_ENV']
      ENV.delete('RAILS_ENV')

      trace "================================================================================================================================================================================================================================================================running: #{command}"
      self.stdout = `#{command}`
      self.exit_status = $?
      trace "test exited with #{exit_status.inspect}, command: #{command}, stdout: #{stdout}"
      ENV['RAILS_ENV'] = old_env


      temp_output.rewind
      self.hydra_output = temp_output.read.chomp
      trace "raw hydra output for '#{command}': #{hydra_output}"
      temp_output.close
      temp_output.unlink

      output = process_output
      trace "processed hydra output for '#{command}': #{output}"

      return output
    end

  end
end
