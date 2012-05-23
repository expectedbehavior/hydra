require 'rspec/core/formatters/progress_formatter'
module Spec
  module Runner
    module Formatter
      class HydraFormatter < RSpec::Core::Formatters::ProgressFormatter
        def example_passed(*args)
          @output.print '.'
          @output.flush
        end

        def example_pending(*args)
        end

        def example_failed(example)
          output.puts failure_output(example, example.execution_result[:exception])

          pending_fixed?(example) ? nil : dump_failure(example, @next_failure_index - 1)
          dump_backtrace(example)
        end

        def failure_output(example, exception)
          red("#{example.full_description.strip} (FAILED - #{next_failure_index})")
        end

        def next_failure_index
          @next_failure_index ||= 0
          @next_failure_index += 1
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

