module Hydra #:nodoc:
  module Listener #:nodoc:
    # Output a textual report at the end of testing
    class ReportGenerator < Hydra::Listener::Abstract
      # Initialize a new report
      def testing_begin(files)
        @report = { }
      end

      # Log the start time of a file
      def file_begin(file)
        file = file[:file] if file.is_a?(Hash)
        @report[file] ||= { }
        @report[file]['start'] = Time.now.to_f
      end

      # Log the end time of a file and compute the file's testing
      # duration
      def file_end(file, output)
        file = file[:file] if file.is_a?(Hash)
        @report[file]['end'] = Time.now.to_f
        @report[file]['duration'] = @report[file]['end'] - @report[file]['start']
      end

      # output the report
      def testing_end
        @output.rewind
        old_report = YAML.load(@output) || {}
        new_report = old_report.merge(@report)
        @output.truncate(0)
        @output.rewind
        YAML.dump(new_report, @output)
        @output.close
      end
    end
  end
end
