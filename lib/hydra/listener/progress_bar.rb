module Hydra #:nodoc:
  module Listener #:nodoc:
    # Output a progress bar as files are completed
    class ProgressBar < Hydra::Listener::Abstract
      # Store the total number of files
      def testing_begin(files)
        @total_files = files.size
        @files_completed = 0
        @test_output = ""
        @errors = false
        render_progress_bar
      end

      # Increment completed files count and update bar
      def file_end(file, output)
        unless output == '.'
          write "\r#{' '*60}\r#{output}\n"
          @errors = true
        end
        @files_completed += 1
        render_progress_bar
      end

      # Break the line
      def testing_end
        render_progress_bar
        write "\n"
      end

      private

      def render_progress_bar
        width = 30
        complete = ((@files_completed.to_f / @total_files.to_f) * width).to_i
        str = ""
        str << "\r" # move to beginning
        str << 'Hydra Testing ['
        str << (@errors ? "\033[0;31m" : "\033[0;32m")
        complete.times { str << '#' }
        str << '>'
        (width-complete).times { str << ' ' }
        str << "\033[0m"
        str << "] #{@files_completed}/#{@total_files}"
        Hydra::WRITE_LOCK.synchronize do
          write str
          @output.flush
        end
      end
      
      def write(str)
        Hydra::WRITE_LOCK.synchronize do
          @output.write str
        end
      end
    end
  end
end

