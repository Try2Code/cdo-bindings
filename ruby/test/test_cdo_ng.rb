$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'cdoNG'

require 'minitest/autorun'

Cdo = CdoNG

#===============================================================================
def rm(files); files.each {|f| FileUtils.rm(f) if File.exist?(f)};end


class TestCdo < Minitest::Test

  DEFAULT_CDO_PATH = 'cdo'

  @@show           = ENV.has_key?('SHOW')
  @@maintainermode = ENV.has_key?('MAINTAINERMODE')
  @@debug          = ENV.has_key?('DEBUG')

  parallelize_me! unless @@debug

  def setup
    @cdo = Cdo.new
  end

  def test_cdo
    assert_equal(true,@cdo.run)
  end

  def test_operator_missing
    assert_raises ArgumentError do
      @cdo.noexistent(:input => '-for,d')
    end
  end
end
