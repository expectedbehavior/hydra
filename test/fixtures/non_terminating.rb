require File.join(File.dirname(__FILE__), '..', 'test_helper')

class NonTerminatingTest < Test::Unit::TestCase
  def test_non_terminating
    sleep 5 while true
  end
end

