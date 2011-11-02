require 'system_timer'
module Hydra #:nodoc:
  # Module that implemets methods that auto-serialize and deserialize messaging
  # objects.
  module MessagingIO
    def initialize(options = {})
      @verbose = options[:verbose]
    end
    
    # Read a Message from the input IO object. Automatically build
    # a message from the response and return it.
    #
    #  IO.gets
    #    => Hydra::Message # or subclass
    def gets
      while true
        begin
          raise IOError unless @reader
#           trace "About to gets reader"
#           message = nil
#           begin
#             SystemTimer.timeout_after(300) do
              message = @reader.gets
#             end
#           rescue Timeout::Error => e
#             trace "reader timeout: #{@reader.inspect} #{@reader.fileno} #{@reader.closed?.inspect}"
#           end
#           trace "Just gets'ed reader #{message.inspect}"
#           trace message if message.include?(Hydra::Trace::REMOTE_IDENTIFIER)
#           puts "#{Process.pid} GOT MESSAGE #{@verbose.inspect}: #{message}"
          return nil unless message
          trace message if message.include?(Hydra::Trace::REMOTE_IDENTIFIER)
#           return nil if message !~ /^\s*(\{|\.)/ # must start with { or .
          next if message !~ /^\s*(\{|\.)/ # must start with { or .
          return Message.build(eval(message.chomp))
        rescue SyntaxError, NameError
          # uncomment to help catch remote errors by seeing all traffic
          trace "Not a message: [#{message.inspect}]\n"
        end
      end
    end

    # Write a Message to the output IO object. It will automatically
    # serialize a Message object.
    #  IO.write Hydra::Message.new
    def write(message)
      raise IOError unless @writer
      raise UnprocessableMessage unless message.is_a?(Hydra::Message)
      Hydra::WRITE_LOCK.synchronize do
        @writer.write(message.serialize+"\n")
      end
    rescue Errno::EPIPE
      raise IOError
    end

    # Closes the IO object.
    def close
#       trace "About to close reader and writer: #{@reader.inspect} #{@reader.fileno}, #{@writer.inspect} #{@writer.fileno}"
      @reader.close if @reader
      @writer.close if @writer
#       [@parent_read, @child_write, @child_read, @parent_write].each do |io|
#         io.close if io && !io.closed?
#       end
    end

    # IO will return this error if it cannot process a message.
    # For example, if you tried to write a string, it would fail,
    # because the string is not a message.
    class UnprocessableMessage < RuntimeError
      # Custom error message
      attr_accessor :message
    end
  end
end
