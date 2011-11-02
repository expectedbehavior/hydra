require 'open3'
require 'hydra/messaging_io'
module Hydra #:nodoc:
  # Read and write with an ssh connection. For example:
  #   @ssh = Hydra::SSH.new(
  #     'localhost', # connect to this machine
  #     '/home/user', # move to the home directory
  #     "ruby hydra/test/echo_the_dolphin.rb" # run the echo script
  #   )
  #   @message = Hydra::Messages::TestMessage.new("Hey there!")
  #   @ssh.write @message
  #   puts @ssh.gets.text
  #     => "Hey there!"
  #
  # Note that what ever process you run should respond with Hydra messages.
  class SSH
    traceable('SSH')
    include Open3
    include Hydra::MessagingIO

    # Initialize new SSH connection.
    # The first parameter is passed directly to ssh for starting a connection.
    # The second parameter is the directory to CD into once connected.
    # The third parameter is the command to run
    # So you can do:
    #   Hydra::SSH.new('-p 3022 user@server.com', '/home/user/Desktop', 'ls -l')
    # To connect to server.com as user on port 3022, then CD to their desktop, then
    # list all the files.
    def initialize(connection_options, directory, command, options = {})
      super(options)
      trace "sshing..."
      @writer, @reader, @error = popen3("ssh -tt #{connection_options}")
      @writer.write("echo connected\n")
      trace "mkdir..."
      @writer.write("mkdir -p #{directory}\n")
      @writer.write("echo mkdired\n")
      trace "cd..."
      @writer.write("cd #{directory}\n")
      @writer.write("echo cded\n")
      trace "writing command: #{command}"
      res = @writer.write(command+"\n")
      trace "written..."
      res
    end

    # Close the SSH connection
    def close
      @writer.write "exit\n"
#       @writer.flush
#       puts @reader.read
#       @reader.read
      super
    end
  end
end
