module Hydra
  class TestProcessor
    class Spec < Hydra::TestProcessor

      def command
        "bundle exec rspec -b #{@test_opts} --require hydra/spec/hydra_formatter --format Spec::Runner::Formatter::HydraFormatter --out #{log_file} #{file} 2>&1 | tee #{tee_flags} #{log_file_name}"
      end

      def run_completed_normally?
        super and
          stdout =~ /Finished in/ and
          (stdout =~ /Failed examples:/ or
           stdout =~ /0 failures/)
      end

    end
  end
end
