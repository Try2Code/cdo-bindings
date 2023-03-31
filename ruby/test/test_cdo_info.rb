$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'info'
require 'minitest/autorun'
require 'semverse'
#===============================================================================
def rm(files); files.each {|f| FileUtils.rm(f) if File.exist?(f)};end
#===============================================================================
EXECUTABLE = ENV.has_key?('CDO') ? ENV['CDO'] : 'cdo'
#===============================================================================

class TestCdoInfo < Minitest::Test
  def test_version
    version = CdoInfo.version(EXECUTABLE)
    assert_equal('2.1.1',version)
    version = CdoInfo.semversion(EXECUTABLE)
    assert_equal(Semverse::Version.new('2.1.1'),version)
  end
  def test_config
    config = CdoInfo.config(EXECUTABLE)
#   if Semverse::Version.new('2.1.1') == CdoInfo.semversion(@executable) then
    expectedConfig = {"has-cgribex"=>true, "has-cmor"=>false, "has-ext"=>true,
                      "has-grb"=>true, "has-grb1"=>true, "has-grb2"=>true,
                      "has-hdf5"=>true, "has-ieg"=>true, "has-magics"=>true,
                      "has-nc"=>true, "has-nc2"=>true, "has-nc4"=>true,
                      "has-nc4c"=>true, "has-nc5"=>true, "has-nczarr"=>true,
                      "has-openmp"=>true, "has-proj"=>true, "has-srv"=>true,
                      "has-threads"=>true, "has-wordexp"=>true, "has-hirlam_extensions"=>false}
#   else if false then
#   end
    assert_equal(config,expectedConfig)
  end
  def test_operators
    operators = CdoInfo.operators(EXECUTABLE)

    # check for specific operators properties
    # maps abritrary inputs and 0 output
    assert_equal(-1,operators["map"][:in])
    assert_equal(0,operators["map"][:out])

    assert_equal(-1,operators["select"][:in])
    assert_equal(1,operators["select"][:out])

    assert_equal(1,operators["fldmean"][:in])
    assert_equal(1,operators["fldmean"][:out])


    assert_equal(1,operators["zaxisdes"][:in])
    assert_equal(0,operators["zaxisdes"][:out])
  end

  def test_works
    assert(CdoInfo.works?('cdo'))
    assert(!CdoInfo.works?('cda_____o'))
    assert(!CdoInfo.works?('ls'))
    assert(CdoInfo.works?(EXECUTABLE))
  end
end
