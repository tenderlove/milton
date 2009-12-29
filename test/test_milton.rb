require 'rubygems'
require 'minitest/autorun'
require 'milton'
require 'net_http_stubs'

class TestMilton < MiniTest::Unit::TestCase
  def test_run
    1.upto(11).each do |n|
      payload = Marshal.load(File.read("test/htdocs/sanity/#{n}.dump"))
      Net::HTTP.responses.push payload
    end

    milton = Milton.new
    milton.run({})
  end
end
