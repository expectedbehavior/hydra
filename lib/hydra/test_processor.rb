module Hydra
  class TestProcessor
    traceable('RUNNER')

    attr_accessor :file, :verbose, :runner_num, :test_opts, :test_failure_guard_regexp, :exit_status, :hydra_output, :stdout

    def initialize(file, options = {})
      self.verbose = options[:verbose]
      self.runner_num = options[:runner_num]
      self.test_opts = options[:test_opts]
      self.test_failure_guard_regexp = options[:test_failure_guard_regexp]
      self.file = file
    end

    def process!
      run_test_command
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
      @log_file ||= temp_output.path
    end

    def run_completed_normally?
      hydra_output =~ /TEST_COMPLETED/
    end

    def hydra_output_is_clean?
      hydra_output.gsub(/Run options.*?$/, '').
        gsub("\n","").
        gsub('TEST_COMPLETED', '').
        gsub(/Randomized with seed \d+/, '') =~ /^\.*$/
    end

    def stdout_is_clean?
      trace "stdout_is_clean? test_failure_guard_regexp: #{test_failure_guard_regexp}, include?: #{stdout.include?(test_failure_guard_regexp)}"
      return true if test_failure_guard_regexp.empty?
      not stdout.match(/#{test_failure_guard_regexp}/)
    end

    def run_succeeded?
      exit_status.success? and
        hydra_output_is_clean? and
        stdout_is_clean?
    end

    def process_output
      if not run_completed_normally?
        failure_message
      elsif run_succeeded?
        ""
      else
        # hydra_output
        failure_message
      end
    end

    def failure_message
      <<-STR
      FAILURE: command:
        #{command}
      run_completed_normally?: #{!!run_completed_normally?}
      exit_status: #{exit_status.inspect}
      hydra_output_is_clean?: #{!!hydra_output_is_clean?}
      stdout_is_clean?: #{!!stdout_is_clean?}
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
