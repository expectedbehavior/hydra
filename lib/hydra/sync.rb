require 'yaml'
module Hydra #:nodoc:
  # Hydra class responsible for delegate work down to workers.
  #
  # The Sync is run once for each remote worker.
  class Sync
    traceable('SYNC')
    self.class.traceable('SYNC MANY')

    attr_reader :connect, :ssh_opts, :remote_dir, :worker_opts

    # Create a new Sync instance to rsync source from the local machine to a remote worker
    #
    # Arguments:
    # * :worker_opts
    #   * A hash of the configuration options for a worker.
    # * :sync
    #   * A hash of settings specifically for copying the source directory to be tested
    #     to the remote worked
    # * :verbose
    #   * Set to true to see lots of Hydra output (for debugging)
    def initialize(worker_opts, sync_opts, verbose = false)
      trace "  Sync:   (#{sync_opts.inspect})"
      @worker_opts = worker_opts || {}
      @worker_opts.stringify_keys!
      @verbose = verbose
      @connect = @worker_opts.fetch('connect') { raise "You must specify an SSH connection target" }
      @ssh_opts = @worker_opts.fetch('ssh_opts') { "" }
      @remote_dir = @worker_opts.fetch('directory') { raise "You must specify a remote directory" }

      return unless sync_opts
      sync_opts.stringify_keys!
      @local_dir = sync_opts.fetch('directory') { raise "You must specify a synchronization directory" }
      @exclude_paths = sync_opts.fetch('exclude') { [] }
      @rsync_opts = sync_opts.fetch('rsync_opts') { "" }
      @reverse_sync_direction = sync_opts.fetch('reverse_sync_direction') { false }

      trace "Initialized"
      trace "  Worker: (#{@worker_opts.inspect})"
      trace "  Sync:   (#{sync_opts.inspect})"

#       sync
    end

    def sync
      # make directory to sync to
      ssh = Hydra::SSH.new("#{@ssh_opts} #{@connect}", @remote_dir, "echo done", :verbose => @verbose)
      ssh.close
      
      #trace "Synchronizing with #{connect}\n\t#{sync_opts.inspect}"
      exclude_opts = @exclude_paths.inject(''){|memo, path| memo += "--exclude=#{path} "}

      src_dest = [
        File.expand_path(@local_dir)+'/',
        "#{@connect}:#{@remote_dir}"
      ]
      src_dest.reverse! if @reverse_sync_direction
      rsync_command = [
        'time',
        'rsync',
        '-avz',
        '--delete',
        exclude_opts,
        "-e \"ssh #{@ssh_opts}\"",
        @rsync_opts,
        *src_dest
      ].join(" ")
      rsync_command = "(#{rsync_command}) 2>&1" # capture all output
      trace rsync_command
      output = `#{rsync_command}`
      status = $?
      if status.success?
        trace "rsync output #{@connect}:" + output
      else
        raise "rsync failed with output: #{output}"
      end
    end

    def self.sync_many opts
      opts.stringify_keys!
      config_file = opts.delete('config') { nil }
      if config_file
        opts.merge!(Hydra.load_config(config_file))
      end
      @verbose = opts.fetch('verbose') { false }
      @sync = opts.fetch('sync') { {} }

      workers_opts = opts.fetch('workers') { [] }
      @remote_worker_opts = []
      workers_opts.each do |worker_opts|
        worker_opts.stringify_keys!
        if worker_opts['type'].to_s == 'ssh'
          @remote_worker_opts << worker_opts
        end
      end

      trace "Initialized"
      trace "  Sync:   (#{@sync.inspect})"
      trace "  Workers: (#{@remote_worker_opts.inspect})"

      Thread.abort_on_exception = true
      trace "Processing workers"
      @listeners = []
      syncers = @remote_worker_opts.map { |worker_opts| Sync.new(worker_opts, @sync.dup, @verbose) }
      syncers.each do |syncer|
        @listeners << Thread.new do
          begin
            trace "Syncing #{syncer.worker_opts.inspect}"
            syncer.sync
          rescue 
            trace "Syncing failed [#{syncer.worker_opts.inspect}]\n#{$!.message}\n#{$!.backtrace}"
            raise
          end
        end
      end
      
      @listeners.each{|l| l.join}
    end

  end
end
