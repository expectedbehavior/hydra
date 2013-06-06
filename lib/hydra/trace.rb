require 'thread'
require 'timeout'
require 'syslog/logger'
module Hydra #:nodoc:
  # Trace output when in verbose mode.
  module Trace
    REMOTE_IDENTIFIER = 'REMOTE'
    
    TRACE_LOGGER = Syslog::Logger.new("hydra")

    module ClassMethods
      # Make a class traceable. Takes one parameter,
      # which is the prefix for the trace to identify this class
      def traceable(prefix = self.class.to_s)
        include Hydra::Trace::InstanceMethods
        class << self; attr_accessor :_traceable_prefix; end
        self._traceable_prefix = prefix
        $stdout.sync = true
      end
    end

    module InstanceMethods
      # Trace some output with the class's prefix and a newline.
      # Checks to ensure we're running verbosely.
      def trace(str = nil, &block)
        str ||= yield if block_given?
        return unless @verbose
        Timeout.timeout(300) do
          Hydra::WRITE_LOCK.synchronize do
            remote_info = @remote ? "#{REMOTE_IDENTIFIER} #{@remote} " : ''
            str = str.to_s.gsub /\n/, "\n#{remote_info}"
            more_info = ""
            more_info << " test env number: #{ENV['TEST_ENV_NUMBER']}" if ENV['TEST_ENV_NUMBER']
            more_info << " runner num: #{@runner_num}" if @runner_num
            more_info << " thread: #{Thread.current.inspect}"
            str = "#{Time.now.to_f} #{Time.now.to_s} pid: #{Process.pid} #{remote_info}#{self.class._traceable_prefix}#{more_info}| #{str}"
            $stdout.puts str
            TRACE_LOGGER.unknown str
          end
        end
      end
    end
  end
end
Object.extend(Hydra::Trace::ClassMethods)
