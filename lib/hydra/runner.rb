# require 'test/unit'
# require 'test/unit/testresult'
# Test::Unit.run = true
require 'thread'
require 'system_timer'

module Hydra #:nodoc:
  # Hydra class responsible for running test files.
  #
  # The Runner is never run directly by a user. Runners are created by a
  # Worker to run test files.
  #
  # The general convention is to have one Runner for each logical processor
  # of a machine.
  class Runner
    include Hydra::Messages::Runner
    traceable('RUNNER')

    DEFAULT_LOG_FILE = File.join('log', 'hydra-runner.log')
    LOCK = Mutex.new

    # Boot up a runner. It takes an IO object (generally a pipe from its
    # parent) to send it messages on which files to execute.
    def initialize(opts = {})
      redirect_output( opts.fetch( :runner_log_file ) { DEFAULT_LOG_FILE } )
      reg_trap_sighup

      @io = opts.fetch(:io) { raise "No IO Object" }
      @verbose = opts.fetch(:verbose) { false }
      @remote = opts.fetch(:remote) { false }      
      @event_listeners = Array( opts.fetch( :runner_listeners ) { nil } )
      @runner_num = opts[:runner_num]

      $stdout.sync = true

      @runner_opts = opts.fetch(:runner_opts) { "" }

      trace 'Creating test database'
      parent_pid = Process.pid
      ENV['TEST_ENV_NUMBER'] = parent_pid.to_s
      begin
#         Rake::Task['db:drop'].invoke        
#         Rake::Task['db:create:all'].invoke        
#         trace ``
        
        trace "DB DROP FORK before fork env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}"
        # this should really clean up after the runner dies
        fork do
          fork do
            begin
              # don't redirect yet, because we're tee'ing the worker
  #             STDIN.reopen '/dev/null'
  #             STDOUT.reopen '/dev/null', 'a'
  #             STDERR.reopen STDOUT
              while (Process.kill(0, parent_pid) rescue nil)
                trace "DB DROP FORK loop env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}"
                sleep 1
              end
              cmd = <<-CMD
                rake db:drop --trace 2>&1
              CMD
              trace "DB DROP FORK after loop env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}"
              trace "DB DROP FORK run env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid} -> " + `#{cmd}`
              # also kill redis and memcached?
            rescue Exception => e
              puts "DB DROP FORK exception env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}, exception: #{e.inspect}"
              trace "DB DROP FORK exception env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}, exception: #{e.inspect}"
            ensure
              puts "DB DROP FORK ensure env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}, exception: #{$!.inspect}"
              trace "DB DROP FORK ensure env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} parent pid: #{parent_pid}, my pid: #{Process.pid}, exception: #{$!.inspect}"
            end
          end
        end
        
        
        
        
        srand # since we've forked we need to reseed
        
        memcached_pid_file_name = "#{Dir.pwd}/log/runner_#{@runner_num}_memcached.pid"
        memcached_log_file_name = "#{Dir.pwd}/log/memcached_#{@runner_num.to_s}.log"
        run_dependent_process(memcached_pid_file_name, memcached_log_file_name) do
          LOCK.synchronize do
            ENV['MEMCACHED_PORT'] = find_open_port.to_s
          end
          "memcached -vvvd -P #{memcached_pid_file_name} -p #{ENV['MEMCACHED_PORT']}"
        end
        


        redis_pid_file_name = "#{Dir.pwd}/log/runner_#{@runner_num}_redis.pid"
        redis_log_file_name = "#{Dir.pwd}/log/redis_#{@runner_num.to_s}.log"
        run_dependent_process(redis_pid_file_name, redis_log_file_name) do
          LOCK.synchronize do
            ENV['REDIS_PORT'] = find_open_port.to_s
          end
          
          config_contents = <<-CONFIG
# written #{Time.now.to_f.to_s}   #{Time.now.to_s}
port #{ENV['REDIS_PORT']}
loglevel debug
pidfile #{redis_pid_file_name}
logfile #{redis_log_file_name}
# so it creates the pid file
daemonize yes
# trying to resolve EAGAIN redis connections errors, my latest thought is that it coincides with dumping the redis db to disk, so let's turn that off
timeout 0
# databases 16
# rdbcompression yes
# dbfilename dump_#{@runner_num.to_s}.rdb
# dir #{File.dirname(redis_pid_file_name)}
appendonly no
appendfsync no
glueoutputbuf yes
vm-enabled no
          CONFIG
          trace "runner #{@runner_num.to_s} redis config: #{config_contents}"
          redis_config_file = File.open("#{Dir.pwd}/tmp/redis_#{@runner_num.to_s}_config", "w") # Tempfile.new("redis-hydra")
          redis_config_file.puts config_contents
          redis_config_file.flush
          
          "redis-server #{redis_config_file.path}"
        end
        
        
        sleep 10

        cmd = <<-CMD
          rake db:drop --trace 2>&1
          rake db:create:all --trace 2>&1
        CMD
        trace "DB CREATE env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} -> " + `#{cmd}`
        
        ENV['SKIP_ROLLOUT_FETCH'] = "true"
        
        old_env = ENV['RAILS_ENV']
        ENV['RAILS_ENV'] = "development"
#         cmd = "rake db:test:clone_structure --trace"
        cmd = <<-CMD
          rake db:test:load_structure --trace 2>&1
        CMD
        trace "DB LOAD STRUCTURE env: #{ENV['RAILS_ENV']} #{ENV['TEST_ENV_NUMBER']} -> " + `#{cmd}`
        ENV['RAILS_ENV'] = old_env
        require 'tempfile'
        

#         user_service_log_file_name = "#{Dir.pwd}/log/user_service_log_file_name_#{@runner_num.to_s}.log"
#         run_dependent_process('', user_service_log_file_name) do
#           LOCK.synchronize do
#             ENV['USER_SERVICE_PORT'] = find_open_port.to_s
#           end
#           "script/server -p #{ENV['USER_SERVICE_PORT']}"
#         end
        
        trace "runner #{@runner_num.to_s} about to enter waiting for services to start loop"
        loop do
          trace "runner #{@runner_num.to_s} waiting for services to start..."
          finished = false
          ports = nil
          LOCK.synchronize do
            ports = [
#                      ENV['USER_SERVICE_PORT'],
                     ENV['MEMCACHED_PORT'],
                     ENV['REDIS_PORT']
                    ].map { |p| p.to_i }
          end
          if ports.all? { |p| is_port_in_use?(p) }
            finished = true
          end
          if finished
            trace "runner #{@runner_num.to_s} services should be done starting"
            break
          end
          sleep 1
        end
        
      rescue Exception => e
        trace "Error creating test DB: #{e}\n#{e.backtrace}"
        raise
      end
      
      # let's see if this fixes memcache server marked dead errors
      sleep 10
      trace "memcache stats port #{ENV['MEMCACHED_PORT']}: " + `echo stats | nc localhost #{ENV['MEMCACHED_PORT']}`

      trace 'Booted. Sending Request for file'

      
      
      
      runner_begin


      trace 'Booted. Sending Request for file'
      @io.write RequestFile.new
      begin
        process_messages
      rescue => ex
        trace ex.to_s
        raise ex
      end
    end
    
    def run_dependent_process(pid_file_name, log_file_name, &command_block)
      trace "run_dependent_process start runner: #{@runner_num} pid: #{pid_file_name}, log: #{log_file_name}"
      if File.exist?(pid_file_name)
        trace "run_dependent_process found pid file runner: #{@runner_num} pid: #{pid_file_name}, log: #{log_file_name}"
        pid = File.read(pid_file_name).strip.to_i
        trace "run_dependent_process found pid runner: #{@runner_num} pid: #{pid}, pid: #{pid_file_name}, log: #{log_file_name}"
        if pid > 0
          trace "run_dependent_process before killing loop runner: #{@runner_num} pid: #{pid}, pid: #{pid_file_name}, log: #{log_file_name}"
          ["TERM", "KILL"].each do |signal|
            tries = 20
            while(Process.kill(0, pid) rescue nil)
              trace "run_dependent_process before kill runner: #{@runner_num} pid: #{pid}, pid: #{pid_file_name}, log: #{log_file_name}"
              Process.kill(signal, pid)
              sleep 0.1
              tries -= 1
              if tries == 0
                raise "Could not kill previous process runner: #{@runner_num} pid: #{pid}, pid: #{pid_file_name}, log: #{log_file_name}" if signal == "KILL"
                break
              end
            end
          end
        end
      end
      trace "run_dependent_process after killing old runner: #{@runner_num} pid: #{pid_file_name}, log: #{log_file_name}, remaining processes:#{`pgrep -fl '(redis-server /zynga|memcached -vvv)'`}"
      
      trace "run_dependent_process before thread runner: #{@runner_num} pid: #{pid_file_name}, log: #{log_file_name}"
      Thread.new do
        trace "run_dependent_process inside thread runner: #{@runner_num} pid: #{pid_file_name}, log: #{log_file_name}"
        loop do
          cmd = yield
          cmd = "strace -fF -ttt -s 200 #{cmd}" if @verbose
          trace "run_dependent_process before fork runner #{@runner_num} cmd: #{cmd}"
          puts "running: #{cmd}"
          
          # maybe the fork below is causing the redis issues?
          # synchronize
#           LOCK.synchronize do
#           # reopen outputs
#             file = File.open(log_file_name, "w")
#             STDOUT.reopen(file)
#             STDERR.reopen(file)
# #           system cmd
#           end
          
          child_pid = fork do
            @io.close
            file = File.open(log_file_name + "-out", "w")
            STDOUT.reopen(file)
            STDERR.reopen(file)
            exec cmd
          end
          trace "run_dependent_process before exec wait runner: #{@runner_num} child_pid: #{child_pid}, pid: #{pid_file_name}, log: #{log_file_name}"
          Process.wait child_pid
          trace "run_dependent_process after exec wait runner: #{@runner_num} child_pid: #{child_pid}, pid: #{pid_file_name}, log: #{log_file_name}"
          
          trace "run_dependent_process before pid file wait read runner: #{@runner_num} child_pid: #{child_pid}, pid: #{pid_file_name}, log: #{log_file_name}"
#           sleep 0.1
          
          # Wait for a new pid file if the old one is in place
          10.times do
            break if File.exist?(pid_file_name) && File.mtime(pid_file_name) > (Time.now - 5)
            sleep 0.2
          end
          if File.exist?(pid_file_name)
            pid = File.read(pid_file_name).strip.to_i
            if pid > 0
              if (Process.kill(0, pid) rescue nil)
#                 at_exit do
#                   Process.kill("TERM", pid)
#                   sleep 0.1
#                   Process.kill("KILL", pid)
#                 end
              end
              trace "run_dependent_process before pid file wait actual wait runner: #{@runner_num} child_pid: #{child_pid}, pid: #{pid_file_name}, log: #{log_file_name}"
              
              while (Process.kill(0, pid) rescue nil)
                trace "run_dependent_process before pid file wait loop wait runner: #{@runner_num} child_pid: #{child_pid}, pid: #{pid_file_name}, log: #{log_file_name}"
                sleep 1
              end
              
            end
          end
          trace "run_dependent_process after pid file wait read runner: #{@runner_num} child_pid: #{child_pid}, pid: #{pid_file_name}, log: #{log_file_name}"
        end
      end
    end
    
    def find_open_port
      100.times do
        port = 10_000 + rand(20_000)
        trace "runner #{@runner_num.to_s} checking open port: #{port}"
        unless is_port_in_use?(port)
          trace "runner #{@runner_num.to_s} found open port: #{port}"
          return port
        end
      end
      raise "Couldn't find open port"
    end
    
    require 'socket'
    def is_port_in_use?(port, ip = "localhost")
      trace "runner #{@runner_num.to_s} is port in use: #{port}"
      begin
        SystemTimer.timeout_after(1) do
          begin
            s = TCPSocket.new(ip, port)
            s.close
            trace "runner #{@runner_num.to_s} port is used: #{port}"
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            trace "runner #{@runner_num.to_s} port is free: #{port}"
            return false
          end
        end
      rescue Timeout::Error
      end
     
      trace "runner #{@runner_num.to_s} port is used: #{port}"
      return true
    end

    def reg_trap_sighup
      for sign in [:SIGHUP, :INT]
        trap sign do
          stop
        end
      end
      @runner_began = true
    end

    def runner_begin
      trace "Firing runner_begin event"
      @event_listeners.each {|l| l.runner_begin( self ) }
    end

    # Run a test file and report the results
    def run_file(file)
      trace "Running file: #{file}"

      output = ""
      if file =~ /_spec.rb$/i || file =~ /spec -e/i
        output = run_rspec_file(file)
      elsif file =~ /.feature$/i
        output = run_cucumber_file(file)
      elsif file =~ /.js$/i or file =~ /.json$/i
        output = run_javascript_file(file)
      else
        output = run_test_unit_file(file)
      end

      output = "." if output == ""

      @io.write Results.new(:output => output, :file => file)
      return output
    end

    # Stop running
    def stop
      trace "Dropping test database #{ENV['TEST_ENV_NUMBER']}"
      ENV['TEST_ENV_NUMBER'] = Process.pid.to_s
      begin
        output = `rake db:drop TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER']} RAILS_ENV=test`
        trace "DB:DROP -> #{output}"
      rescue Exception => e
        trace "Could not drop test database #{ENV['TEST_ENV_NUMBER']}: #{e}\n#{e.backtrace}"
      end
      
      runner_end if @runner_began
      @runner_began = @running = false
      trace "About to close my io"
      @io.close
      trace "io closed"
    end

    def runner_end
      trace "Ending runner #{self.inspect}"
      @event_listeners.each {|l| l.runner_end( self ) }
    end

    def format_exception(ex)
      "#{ex.class.name}: #{ex.message}\n    #{ex.backtrace.join("\n    ")}"
    end

    private

    # The runner will continually read messages and handle them.
    def process_messages
      trace "Processing Messages"
      @running = true
      while @running
        begin
          message = @io.gets
          if message and !message.class.to_s.index("Worker").nil?
            trace "Received message from worker"
            trace "\t#{message.inspect}"
            message.handle(self)
          else
            @io.write Ping.new
          end
        rescue IOError => ex
          trace "Runner lost Worker"
          stop
        end
      end
      trace "Stopped Processing Messages"
    end

    def format_ex_in_file(file, ex)
      "Error in #{file}:\n  #{format_exception(ex)}"
    end

    # Run all the Test::Unit Suites in a ruby file
    def run_test_unit_file(file)
      begin
        require file
      rescue LoadError => ex
        trace "#{file} does not exist [#{ex.to_s}]"
        return ex.to_s
      rescue Exception => ex
        trace "Error requiring #{file} [#{ex.to_s}]"
        return format_ex_in_file(file, ex)
      end
      output = []
      @result = Test::Unit::TestResult.new
      @result.add_listener(Test::Unit::TestResult::FAULT) do |value|
        output << value
      end

      klasses = Runner.find_classes_in_file(file)
      begin
        klasses.each{|klass| klass.suite.run(@result){|status, name| ;}}
      rescue => ex
        output << format_ex_in_file(file, ex)
      end

      return output.join("\n")
    end

    # run all the Specs in an RSpec file (NOT IMPLEMENTED)
    def run_rspec_file(file)
      
      hydra_output = Tempfile.new("hydra")
      log_file = hydra_output.path
      old_env = ENV['RAILS_ENV']
      ENV.delete('RAILS_ENV')
      cmd = "bundle exec spec -b #{@runner_opts} --require hydra/spec/hydra_formatter --format Spec::Runner::Formatter::HydraFormatter:#{log_file} #{file} 2>&1 | tee -a /tmp/spec_runner_#{@runner_num}.log"
      trace "================================================================================================================================================================================================================================================================running: #{cmd}"
      stdout = `#{cmd}`
      status = $?
      trace stdout
      ENV['RAILS_ENV'] = old_env
      
      trace "memcache stats port #{ENV['MEMCACHED_PORT']}: " + `echo stats | nc localhost #{ENV['MEMCACHED_PORT']}`
      
      hydra_output.rewind
      output = hydra_output.read.chomp
      output = "" if output.gsub("\n","") =~ /^\.*$/
      
      output = "FAILURE: command (#{cmd}) exited with #{status.inspect} and produced: #{stdout}" unless status.success?
      hydra_output.close
      hydra_output.unlink

      return output
    end

    # run all the scenarios in a cucumber feature file
    def run_cucumber_file(file)

      files = [file]
      hydra_output = Tempfile.new("hydra")
      log_file = hydra_output.path
      old_env = ENV['RAILS_ENV']
      ENV.delete('RAILS_ENV')
      cmd = "bundle exec cucumber -b #{@runner_opts} --require #{File.dirname(__FILE__)}/cucumber/formatter.rb --format Cucumber::Formatter::Hydra --out #{log_file} #{file} 2>&1 | tee -a /tmp/feature_runner_#{@runner_num}.log"
      trace "================================================================================================================================================================================================================================================================running: #{cmd}"
      stdout = `#{cmd}`
      status = $?
      trace stdout
      ENV['RAILS_ENV'] = old_env
      
      
      hydra_output.rewind
      output = hydra_output.read.chomp
      output = "FAILURE: command (#{cmd}) exited with #{status.inspect} and produced: #{stdout}" unless status.success?
      hydra_output.close
      hydra_output.unlink

      return output
    end

    def run_javascript_file(file)
      errors = []
      require 'v8'
      V8::Context.new do |context|
        context.load(File.expand_path(File.join(File.dirname(__FILE__), 'js', 'lint.js')))
        context['input'] = lambda{
          File.read(file)
        }
        context['reportErrors'] = lambda{|js_errors|
          js_errors.each do |e|
            e = V8::To.rb(e)
            errors << "\n\e[1;31mJSLINT: #{file}\e[0m"
            errors << "  Error at line #{e['line'].to_i + 1} " + 
              "character #{e['character'].to_i + 1}: \e[1;33m#{e['reason']}\e[0m"
            errors << "#{e['evidence']}"
          end
        }
        context.eval %{
          JSLINT(input(), {
            sub: true,
            onevar: true,
            eqeqeq: true,
            plusplus: true,
            bitwise: true,
            regexp: true,
            newcap: true,
            immed: true,
            strict: true,
            rhino: true
          });
          reportErrors(JSLINT.errors);
        }
      end

      if errors.empty?
        return '.'
      else
        return errors.join("\n")
      end
    end

    # find all the test unit classes in a given file, so we can run their suites
    def self.find_classes_in_file(f)
      code = ""
      File.open(f) {|buffer| code = buffer.read}
      matches = code.scan(/class\s+([\S]+)/)
      klasses = matches.collect do |c|
        begin
          if c.first.respond_to? :constantize
            c.first.constantize
          else
            eval(c.first)
          end
        rescue NameError
          # means we could not load [c.first], but thats ok, its just not
          # one of the classes we want to test
          nil
        rescue SyntaxError
          # see above
          nil
        end
      end
      return klasses.select{|k| k.respond_to? 'suite'}
    end

    # Yanked a method from Cucumber
    def tag_excess(features, limits)
      limits.map do |tag_name, tag_limit|
        tag_locations = features.tag_locations(tag_name)
        if tag_limit && (tag_locations.length > tag_limit)
          [tag_name, tag_limit, tag_locations]
        else
          nil
        end
      end.compact
    end

    def redirect_output file_name
      begin
        file = File.open(file_name, 'a')
        $stdout.reopen(file)
        $stderr.reopen(file)
      rescue
        # it should always redirect output in order to handle unexpected interruption
        # successfully
        file = File.open(DEFAULT_LOG_FILE, 'a')
        $stdout.reopen(file)
        $stderr.reopen(file)
      end
      $stdout.sync = true
      $stderr.sync = true
    end
  end
end
