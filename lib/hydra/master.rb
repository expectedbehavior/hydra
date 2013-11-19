require 'hydra/hash'
require 'open3'
require 'hydra/tmpdir'
require 'erb'
require 'yaml'

module Hydra #:nodoc:
  # Hydra class responsible for delegate work down to workers.
  #
  # The Master is run once for any given testing session.
  class YmlLoadError < StandardError; end

  class Master
    include Hydra::Messages::Master
    include Open3
    traceable('MASTER')
    attr_reader :failed_files, :file_count

    # Create a new Master
    #
    # Options:
    # * :files
    #   * An array of test files to be run. These should be relative paths from
    #     the root of the project, since they may be run on different machines
    #     which may have different paths.
    # * :workers
    #   * An array of hashes. Each hash should be the configuration options
    #     for a worker.
    # * :listeners
    #   * An array of Hydra::Listener objects. See Hydra::Listener::MinimalOutput for an
    #     example listener
    # * :verbose
    #   * Set to true to see lots of Hydra output (for debugging)
    # * :autosort
    #   * Set to false to disable automatic sorting by historical run-time per file
    def initialize(opts = { })
      opts.stringify_keys!
      config_file = opts.delete('config') { nil }
      opts.merge!(Hydra.load_config(config_file)) if config_file
      @files = Array(opts.fetch('files') { nil })
      @file_count = @files.size
      raise "No files, nothing to do" if @files.empty?
      @incomplete_files = @files.dup
      @failed_files = []
      @workers = []
      @listeners = []
      @event_listeners = Array(opts.fetch('listeners') { nil } )
      @event_listeners.select{|l| l.is_a? String}.each do |l|
        @event_listeners.delete_at(@event_listeners.index(l))
        listener = eval(l)
        @event_listeners << listener if listener.is_a?(Hydra::Listener::Abstract)
      end

      @string_runner_event_listeners = Array( opts.fetch( 'runner_listeners' ) { nil } )

      @runner_log_file = opts.fetch('runner_log_file') { nil }
      @verbose = opts.fetch('verbose') { false }
      @autosort = opts.fetch('autosort') { true }
      @sync = opts.fetch('sync') { nil }
      @environment = opts.fetch('environment') { 'test' }
      @signals = opts.fetch('signals') {
        ['SIGTERM', 'SIGINT']
      }

      @test_opts = opts.fetch('test_opts') { '' }
      @test_failure_guard_regexp = opts.fetch('test_failure_guard_regexp') { '' }

      if @autosort
        sort_files_from_report
        @event_listeners << Hydra::Listener::ReportGenerator.new(File.new(heuristic_file, 'a+'))
      end

      # default is one worker that is configured to use a pipe with one runner
      worker_cfg = opts.fetch('workers') { [ { 'type' => 'local', 'runners' => 1} ] }

      trace "Initialized"
      trace "  Files:   (#{@files.inspect})"
      trace "  Workers: (#{worker_cfg.inspect})"
      trace "  Verbose: (#{@verbose.inspect})"

      @event_listeners.each{|l| l.testing_begin(@files) }

      boot_workers worker_cfg
      trap_signals
      process_messages
    end

    # Message handling
    def worker_begin(worker)
      @event_listeners.each {|l| l.worker_begin(worker) }
    end

    # Send a file down to a worker.
    def send_file(worker)
      f = @files.shift
      if f
        trace "Sending #{f.inspect}"
        @event_listeners.each{|l| l.file_begin(f) }
        worker[:io].write(RunFile.new(:file => f))
      else
        trace "No more files to send"
      end
    end

    # Process the results coming back from the worker.
    def process_results(worker, message)
      if message.output =~ /ActiveRecord::StatementInvalid(.*)[Dd]eadlock/ or
         message.output =~ /PGError: ERROR(.*)[Dd]eadlock/ or
         message.output =~ /Mysql::Error: SAVEPOINT(.*)does not exist: ROLLBACK/ or
         message.output =~ /Mysql::Error: Deadlock found/
        trace "Deadlock detected running [#{message.file}]. Will retry at the end"
        @files.push(message.file)
        send_file(worker)
      else
        @incomplete_files.delete_at(@incomplete_files.index(message.file))
        remainder = "#{@incomplete_files.size} Files Remaining"
        remainder << ": #{@incomplete_files.inspect}" if @incomplete_files.size < 100
        trace remainder
        @event_listeners.each{|l| l.file_end(message.file, message.output) }
        unless message.output == '.'
          @failed_files << message.file
        end
        if @incomplete_files.empty?
          @workers.each do |worker|
            @event_listeners.each{|l| l.worker_end(worker) }
          end

          shutdown_all_workers
        else
          send_file(worker)
        end
      end
    end

    # A text report of the time it took to run each file
    attr_reader :report_text

    private

    def boot_workers(workers)
      trace "Booting #{workers.size} workers"
      workers.each do |worker|
        worker.stringify_keys!
        trace "worker opts #{worker.inspect}"
        type = worker.fetch('type') { 'local' }
        if type.to_s == 'local'
          boot_local_worker(worker)
        elsif type.to_s == 'ssh'
          @workers << worker # will boot later, during the listening phase
        else
          raise "Worker type not recognized: (#{type.to_s})"
        end
      end
    end

    def boot_local_worker(worker)
      runners = worker.fetch('runners') { raise "You must specify the number of runners" }
      trace "Booting local worker"
      pipe = Hydra::Pipe.new(:verbose => @verbose)
      child = SafeFork.fork do
        pipe.identify_as_child
        Hydra::Worker.new(:io => pipe, :runners => runners, :verbose => @verbose, :runner_listeners => @string_runner_event_listeners, :runner_log_file => @runner_log_file )
      end

      pipe.identify_as_parent
      @workers << { :pid => child, :io => pipe, :idle => false, :type => :local }
    end

    def boot_ssh_worker(worker)
      sync = Sync.new(worker, @sync, @verbose)

      runners = worker.fetch('runners') { raise "You must specify the number of runners"  }
      tee_flags = @verbose ? "-a" : ""
      command = worker.fetch('command') {
        # exit at the end so it the worker borks the ssh connection gets closed and we don't wait on io
        "RAILS_ENV=#{@environment} ruby -e \"require 'rubygems'; require 'bundler/setup'; require 'hydra'; Hydra::Worker.new(:io => Hydra::Stdio.new(:verbose => #{@verbose}), :runners => #{runners}, :verbose => #{@verbose}, :test_opts => '#{@test_opts}', :test_failure_guard_regexp => '#{@test_failure_guard_regexp}', :runner_listeners => \'#{@string_runner_event_listeners}\', :runner_log_file => \'#{@runner_log_file}\', :remote => '#{sync.connect}' );\" 2>&1 | tee #{tee_flags} log/hydra_worker.log; exit"
      }

      trace "Booting SSH worker"
      ssh = Hydra::SSH.new("#{sync.ssh_opts} #{sync.connect}", sync.remote_dir, command, :verbose => @verbose)
      return { :io => ssh, :idle => false, :type => :ssh, :connect => sync.connect }
    end

    def shutdown_all_workers
      trace "Shutting down all workers"
      @workers.map do |worker|
        Thread.new do
          worker[:shutdown] = true
          worker[:io].write(Shutdown.new) if worker[:io]
          trace "worker[:io]: #{worker[:io].inspect}"
          begin
            worker[:io].close if worker[:io]
          rescue IOError
          end
          worker[:listener].exit if worker[:listener]
        end
      end
      trace "Shutdown sent to all workers"
    end

    def process_messages
      Thread.abort_on_exception = true

      trace "Processing Messages"
      trace "Workers: #{@workers.inspect}"
      @workers.each do |worker|
        @listeners << Thread.new do
          trace "Listening to #{worker.inspect}"
           if worker.fetch('type') { 'local' }.to_s == 'ssh'
             worker = boot_ssh_worker(worker)
             @workers << worker
             worker[:listener] = Thread.current
           end
          while true
            begin
              trace "About to gets from: #{worker.inspect}"
              message = worker[:io].gets
              raise IOError if message.nil? # the connection was closed
              trace "got message: #{message.inspect}" if message
              # if it exists and its for me.
              # SSH gives us back echoes, so we need to ignore our own messages
              if message and !message.class.to_s.index("Worker").nil?
                message.handle(self, worker)
              end
            rescue IOError
              if worker[:shutdown]
                Thread.exit # ignore and exit silently
              else
                puts  "\n\nError: Lost Worker [#{worker.inspect}] #{$!.message}\n#{$!.backtrace}\n\n"
                exit 2
              end
            end
          end
        end
      end

      @listeners.each{|l| l.join}
      @event_listeners.each{|l| l.testing_end}
      trace "Finished processing messages (thread list: #{Thread.list.inspect})"
    end

    def sort_files_from_report
      if File.exists? heuristic_file and File.read(heuristic_file).present?
        report = YAML.load_file(heuristic_file)
        return unless report
        sorted_files = report.sort{ |a,b|
          (b[1]['duration'] || 0) <=> (a[1]['duration'] || 0)
        }.collect{|tuple| tuple[0]}

        @files.sort_by! do |f|
          f = f[:file] if f.is_a?(Hash)
          sorted_files.index(f) || -1
        end
      end
    end

    def heuristic_file
      @heuristic_file ||= File.join(Dir.consistent_tmpdir, 'hydra_heuristics.yml')
    end

    def trap_signals
      @signals.each do |signal|
        Signal.trap signal do
          puts "Caught signal #{signal}, shutting down.\n#{caller.join("\n")}"
          shutdown_all_workers
          exit 1
        end
      end
    end
  end
end
