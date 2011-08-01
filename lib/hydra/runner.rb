require 'test/unit'
require 'test/unit/testresult'
Test::Unit.run = true

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
    # Boot up a runner. It takes an IO object (generally a pipe from its
    # parent) to send it messages on which files to execute.
    def initialize(opts = {})
      @io = opts.fetch(:io) { raise "No IO Object" } 
      @verbose = opts.fetch(:verbose) { false }      
      $stdout.sync = true

      @runner_opts = opts.fetch(:runner_opts) { "" }

      trace 'Creating test database'
      ENV['TEST_ENV_NUMBER'] = Process.pid.to_s
      begin
#         Rake::Task['db:drop'].invoke        
#         Rake::Task['db:create:all'].invoke        
#         trace ``

        cmd = <<-CMD
          rake db:drop
          rake db:create:all
        CMD
        trace `#{cmd}`
        
        old_env = ENV['RAILS_ENV']
        ENV['RAILS_ENV'] = "development"
#         cmd = "rake db:test:clone_structure --trace"
        cmd = <<-CMD
          rake db:test:load_structure --trace
        CMD
        trace `#{cmd}`
        ENV['RAILS_ENV'] = old_env
        require 'tempfile'
        
        
        
        r, w = IO.pipe
        @memcached_pid = fork do
          w.close
          
          i = (Process.pid % 50_000) + 10_000
          cmd = "memcached -p #{i}"
          puts "running: #{cmd}"
          child_pid = fork do
            exec cmd
          end
          
          Thread.new do
            begin
              r.read
            ensure
              Process.kill "TERM", child_pid
              exit
            end
          end
          
          Process.wait child_pid
          exit
        end
        r.close
#         at_exit { w.close }
        
        ENV['MEMCACHED_PORT'] = ((@memcached_pid % 50_000) + 10_000).to_s
        trace "runner memcached port: #{ENV['MEMCACHED_PORT']}"
        

        r, w = IO.pipe
        @redis_pid = fork do
          w.close
          
          i = (Process.pid % 50_000) + 10_000
          
          
#           raise 'First fork failed' if (pid = fork) == -1
#           exit unless pid.nil?

#           Process.setsid
#           raise 'Second fork failed' if (pid = fork) == -1
#           exit unless pid.nil?
#           puts "Daemon pid: #{Process.pid}" # Or save it somewhere, etc.

#           Dir.chdir '/'
#           File.umask 0000
          
          
          
          
          cmd = "echo 'port #{i}' | redis-server -"
          puts "running: #{cmd}"
#           child_pid = fork do
#             exec cmd
#           end
          io = IO.popen("redis-server -", "r+")
          child_pid = io.pid
          io.puts "port #{i}"
          io.close_write

          Thread.new do
            loop do
              trace io.gets
            end
          end

          Thread.new do
            begin
              r.read
            ensure
              trace "killing TERM #{child_pid}"
              Process.kill "TERM", child_pid
              exit
            end
          end
          
          Process.wait child_pid
          exit
        end
        r.close
#         Process.detach @redis_pid
#         at_exit { w.close }
        
        ENV['REDIS_PORT'] = ((@redis_pid % 50_000) + 10_000).to_s
        trace "runner redis port: #{ENV['REDIS_PORT']}"
        
      rescue Exception => e
        trace "Error creating test DB: #{e}"
        raise
      end
      

      trace 'Booted. Sending Request for file'

      @io.write RequestFile.new
      begin
        process_messages
      rescue => ex
        trace ex.to_s
        raise ex
      end
    end

    # Run a test file and report the results
    def run_file(file)
      trace "Running file: #{file}"

      output = ""
      if file =~ /_spec.rb$/i
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
        trace "Could not drop test database #{ENV['TEST_ENV_NUMBER']}: #{e}"
      end
      
      @running = false
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
          @running = false
        end
      end
    end

    def format_ex_in_file(file, ex)
      "Error in #{file}:\n  #{format_exception(ex)}"
    end

    def format_exception(ex)
      "#{ex.class.name}: #{ex.message}\n    #{ex.backtrace.join("\n    ")}"
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
      cmd = "bundle exec spec #{@runner_opts} --require hydra/spec/hydra_formatter --format Spec::Runner::Formatter::HydraFormatter:#{log_file} #{file} 2>&1"
      puts "================================================================================================================================================================================================================================================================running: #{cmd}"
      stdout = `#{cmd}`
      status = $?
      trace stdout
      ENV['RAILS_ENV'] = old_env
      
      
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
      cmd = "bundle exec cucumber #{@runner_opts} --require #{File.dirname(__FILE__)}/cucumber/formatter.rb --format Cucumber::Formatter::Hydra --out #{log_file} #{file} 2>&1"
      puts "================================================================================================================================================================================================================================================================running: #{cmd}"
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
  end
end
