module Hydra
  class TestProcessor
    class Cucumber < Hydra::TestProcessor

      def command
        "bundle exec cucumber -b #{@test_opts} --require hydra/cucumber/hydra_formatter --format Hydra::Cucumber::HydraFormatter --out #{log_file} #{file} 2>&1 | tee #{tee_flags} #{log_file_name}"
      end

      def run_completed_normally?
        super and
          (stdout =~ /^\d+ scenarios? \(\d+ passed\)$/ or
           stdout =~ /^0 scenarios$/) # some files might have only @wip scenarios
      end

    end
  end
end
