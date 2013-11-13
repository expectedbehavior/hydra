require 'cucumber/formatter/progress'

module Hydra #:nodoc:
  module Cucumber #:nodoc:
    # Hydra formatter for cucumber.
    # Stifles all output except error messages
    # Based on the
    class HydraFormatter < ::Cucumber::Formatter::Progress
      # Removed the extra newlines here
      def after_features(features)
        print_summary(features)
      end

      private
      
      # Removed the file statistics
      def print_summary(features)
        print_steps(:pending)
        print_steps(:failed)
        print_snippets(@options)
        print_passing_wip(@options)
        @io.print('TEST_COMPLETED')
        @io.flush
      end

      # no color
      def progress(status)
        char = CHARS[status]
        unless [:pending, :skipped].include? status # we don't care about these
          @io.print(char)
          @io.flush
        end
      end
    end
  end
end
