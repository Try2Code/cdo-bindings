$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'info'
require 'minitest/autorun'
#===============================================================================
def rm(files); files.each {|f| FileUtils.rm(f) if File.exist?(f)};end

class TestCdoInfo < Minitest::Test
  def test_version
    version = CdoInfo.version('/usr/bin/cdo')
    assert_equal('2.1.1',version)
    version = CdoInfo.semversion('/usr/bin/cdo')
    assert_equal(Semverse::Version.new('2.1.1'),version)
  end
  def test_config
    config = CdoInfo.config('cdo')
    expectedConfig = {"has-cgribex"=>true, "has-cmor"=>false, "has-ext"=>true,
                      "has-grb"=>true, "has-grb1"=>true, "has-grb2"=>true,
                      "has-hdf5"=>true, "has-ieg"=>true, "has-magics"=>true,
                      "has-nc"=>true, "has-nc2"=>true, "has-nc4"=>true,
                      "has-nc4c"=>true, "has-nc5"=>true, "has-nczarr"=>true,
                      "has-openmp"=>true, "has-proj"=>true, "has-srv"=>true,
                      "has-threads"=>true, "has-wordexp"=>true}
    assert_equal(config,expectedConfig)
  end
  def test_operators
    operators = CdoInfo.operators('cdo')
    pp operators
    assert_equal(operators["map"],-1)
    assert_equal(operators["select"],1)
    assert_equal(operators["fldmean"],1)
    assert_equal(operators["infov"],1)
  end
end
