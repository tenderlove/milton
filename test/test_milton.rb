require 'rubygems'
require 'minitest/autorun'
require 'milton'
require 'net_http_stubs'

class TestMilton < MiniTest::Unit::TestCase
  def test_run
    milton = Milton.new
    milton.run({})
  end
end
