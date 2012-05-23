module Hydra
  class TestProcessor
    class Spec < Hydra::TestProcessor

      def process!
        run_test_command
      end

      def command
        "bundle exec rspec -b #{@runner_opts} --require hydra/spec/hydra_formatter --format Spec::Runner::Formatter::HydraFormatter --out #{log_file} #{file} 2>&1 | tee #{tee_flags} #{log_file_name}"
      end

      def run_completed_normally?
        stdout =~ /Finished in/ and
          hydra_output =~ /TEST_COMPLETED/ and
          (stdout =~ /Failed examples:/ or
           stdout =~ /0 failures/)
      end

      def hydra_output_is_clean?
        hydra_output.gsub(/Run options.*?$/, '').gsub("\n","").gsub('TEST_COMPLETED', '') =~ /^\.*$/
      end

      def run_succeeded?
        exit_status.success? and
          hydra_output_is_clean?
      end

      def process_output
        if not run_completed_normally?
          failure_message
        elsif run_succeeded?
          ""
        else
          hydra_output
        end
      end

    end
  end
end
