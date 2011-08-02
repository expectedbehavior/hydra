require File.join(File.dirname(__FILE__), 'test_helper')

class TraceTester
  traceable("TEST")
  attr_accessor :verbose, :remote
  def initialize verbose, remote
    self.verbose, self.remote = verbose, remote
  end
end

class TraceTest < Test::Unit::TestCase
  def setup
    @result = StringIO.new("")
  end

  def run_trace object, str
    old_stdout = $stdout
    $stdout = @result
    object.trace str
    return @result.string
  ensure
    $stdout = old_stdout
  end

  context "with no tracing enabled" do 
    setup do
      @tracer = TraceTester.new false, false
    end

    should "not output" do
      result = run_trace @tracer, "testing"
      assert_equal '', result
    end
  end

  context "with a local object" do
    setup do
      @tracer = TraceTester.new true, false
    end
    
    should "output" do
      result = run_trace @tracer, 'testing'
      assert_match /TEST/, result
      assert_match /testing/, result
      assert_no_match /#{Hydra::Trace::REMOTE_IDENTIFIER}/, result
    end
  end

  context "with a remote object" do
    setup do
      @tracer = TraceTester.new true, 'localhost'
    end
    
    should "output" do
      result = run_trace @tracer, 'testing'
      assert_match /TEST/, result
      assert_match /testing/, result
      assert_equal "\n"[0], result[-1]
      assert_match /#{Hydra::Trace::REMOTE_IDENTIFIER} localhost/, result
    end

    should "output a multiline message" do
      result = run_trace @tracer, "testing\ntrace line #1\ntrace line #2"
      assert_match /TEST/, result
      assert_match /testing/, result
      assert_match /#{Hydra::Trace::REMOTE_IDENTIFIER} localhost TEST/, result
      assert_match /\n#{Hydra::Trace::REMOTE_IDENTIFIER} localhost trace line #1/, result
      assert_match /\n#{Hydra::Trace::REMOTE_IDENTIFIER} localhost trace line #2/, result
    end
  end
end

