require 'rubygems'
require 'minitest/autorun'
require 'milton'
require 'net_http_stubs'

class TestMilton < MiniTest::Unit::TestCase
  def test_run

    1.upto(11).each do |n|
      Net::HTTP.responses.push File.read("test/htdocs/sanity/#{n}.html")
    end

    milton = Milton.new
    milton.run({})
  end
end
