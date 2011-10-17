require 'hydra/messaging_io'
module Hydra #:nodoc:
  # Read and write via stdout and stdin.
  class Stdio
    traceable('STDIO')
    include Hydra::MessagingIO

    # Initialize new Stdio
    def initialize(options = {})
      @reader = $stdin
      @writer = $stdout
      @reader.sync = true
      @writer.sync = true
      super
    end
  end
end

