module Hydra
  class TestProcessor
    class Cucumber < Hydra::TestProcessor

      def process!
        run_test_command
      end

      def command
        "bundle exec cucumber -b #{@runner_opts} --require hydra/cucumber/formatter --format Hydra::Cucumber::Formatter --out #{log_file} #{file} 2>&1 | tee #{tee_flags} #{log_file_name}"
      end

      def run_completed_normally?
        hydra_output =~ /TEST_COMPLETED/ and
          (stdout =~ /^\d+ scenarios? \(\d+ passed\)$/ or
           stdout =~ /^0 scenarios$/) # some files might have only @wip scenarios
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
