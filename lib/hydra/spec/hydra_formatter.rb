# require 'rspec/core/formatters/progress_formatter'
require 'spec/runner/formatter/progress_bar_formatter'
module Spec
  module Runner
    module Formatter
      class HydraFormatter < ProgressBarFormatter
        def example_passed(*args)
          @output.print '.'
          @output.flush
        end

        def example_pending(*args)
        end

        def example_failed(*args)
        end

        # Stifle the post-test summary
        def dump_summary(*args)
          @output.print 'TEST_COMPLETED'
          @output.flush
        end

        # Stifle pending specs
        def dump_pending
        end
      end
    end
  end
end

