$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'test/unit'
require 'cdo'
require 'pp'

class TestCdo < Test::Unit::TestCase

  DEFAULT_CDO_PATH = '/usr/bin/cdo'
  def setup
    if ENV['CDO'].nil?
      if File.exists?(DEFAULT_CDO_PATH)
        Cdo.setCdo(DEFAULT_CDO_PATH)
      else
        stop(DEFAULT_CDO_PATH)
      end
    else
      # Check user given path
      unless File.exists?(ENV['CDO'])
        stop(ENV['CDO'])
      else
        Cdo.setCdo(ENV['CDO'])
      end
    end
  end
  def stop(path)
    warn "Could not find CDO binary (#{path})! Abort tests"
    exit
  end

  def test_getOperators
    %w[for random stdatm info showlevel sinfo remap geopotheight mask topo thicknessOfLevels].each {|op|
      if ["thicknessOfLevels"].include?(op)
        assert(Cdo.respond_to?(op),"Operator '#{op}' not found")
      else
        assert(Cdo.getOperators.include?(op))
      end
    }
  end
  def test_info
    levels = Cdo.showlevel(:in => "-stdatm,0")
    assert_equal([0,0].map(&:to_s),levels)

    info = Cdo.sinfo(:in => "-stdatm,0")
    assert_equal("File format: GRIB",info[0])
  end
  def test_args
    #Cdo.Debug = true
    #MyTempfile.setPersist(true)
    ofile0 = MyTempfile.path
    ofile1 = MyTempfile.path
    ofile2 = MyTempfile.path
    ofile3 = MyTempfile.path
    Cdo.stdatm(0,20,40,80,200,230,400,600,1100,:out => ofile0)
    Cdo.intlevel(0,10,50,100,500,1000,  :in => ofile0,:out => ofile1)
    Cdo.intlevel([0,10,50,100,500,1000],:in => ofile0,:out => ofile2)
    Cdo.sub(:in => [ofile1,ofile2].join(' '),:out => ofile3)
    info = Cdo.infon(:in => ofile3)
    (1...info.size).each {|i| assert_equal(0.0,info[i].split[-1].to_f)}
  end
  def test_operator_options
    ofile = MyTempfile.path
    targetLevels = [0,10,50,100,200,400,1000]
    Cdo.stdatm(targetLevels,:out => ofile)
    levels = Cdo.showlevel(:in => ofile)
    [0,1].each {|i| assert_equal(targetLevels.map(&:to_s),levels[i].split)}
  end
  def test_CDO_options
    names = Cdo.showname(:in => "-stdatm,0",:options => "-f nc")
    assert_equal(["P T"],names)

    ofile = MyTempfile.path
    Cdo.topo(:out => ofile,:options => "-z szip")
    assert_equal(["GRIB SZIP"],Cdo.showformat(:in => ofile))
  end
  def test_chain
    ofile     = MyTempfile.path
    #Cdo.Debug = true
    Cdo.setname('veloc',:in => " -copy -random,r1x1",:out => ofile,:options => "-f nc")
    assert_equal(["veloc"],Cdo.showname(:in => ofile))
  end

  def test_diff
    diffv = Cdo.diffn(:in => "-random,r1x1 -random,r1x1")
    assert_equal(diffv[1].split(' ')[4],"random")
    assert_equal(diffv[1].split(' ')[-1],"0.53060")
    diff  = Cdo.diff(:in => "-random,r1x1 -random,r1x1")
    assert_equal(diff[1].split(' ')[-1],"0.53060")
  end

  def test_bndLevels
    ofile = MyTempfile.path
    Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:out => ofile,:options => "-f nc")
    assert_equal([0, 50.0, 150.0, 350.0, 650.0, 1100.0, 1700.0, 2500.0, 3500.0, 4500.0, 5500.0],
                 Cdo.boundaryLevels(:in => "-selname,T #{ofile}"))
    assert_equal([50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0, 1000.0, 1000.0, 1000.0],
                 Cdo.thicknessOfLevels(:in => ofile))
  end

  def test_combine
    ofile0, ofile1 = MyTempfile.path, MyTempfile.path
    Cdo.fldsum(:in => Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:options => "-f nc"),:out => ofile0)
    ofile1 = Cdo.fldsum(:in => "-stdatm,25,100,250,500,875,1400,2100,3000,4000,5000",:options => "-f nc")
    Cdo.setReturnArray(true)
    diff = Cdo.sub(:in => [ofile0,ofile1].join(' '),:out => MyTempfile.path).var('T').get
    assert_equal(0.0,diff.min)
    assert_equal(0.0,diff.max)
    Cdo.setReturnArray(false)
  end

  def test_returnArray
    ofile = MyTempfile.path
    vals = Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:out => ofile,:options => "-f nc")
    assert_equal(ofile,vals)
    Cdo.setReturnArray
    vals = Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:out => ofile,:options => "-f nc")
    assert_equal(["lon","lat","level","P","T"],vals.var_names)
    assert_equal(276,vals.var("T").get.flatten.mean.floor)
    Cdo.unsetReturnArray
  end
  def test_simple_returnArray
    ofile0, ofile1 = MyTempfile.path, MyTempfile.path
    sum = Cdo.fldsum(:in => Cdo.stdatm(0,:options => "-f nc"),
               :returnArray => true).var("P").get
    assert_equal(1013.25,sum.min)
    test_returnArray
  end

  def test_thickness
    levels            = "25 100 250 500 875 1400 2100 3000 4000 5000".split
    targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
    assert_equal(targetThicknesses, Cdo.thicknessOfLevels(:in => "-selname,T -stdatm,#{levels.join(',')}"))
  end

  if 'thingol' == `hostname`.chomp  then
    def test_verticalLevels
      iconpath = "/home/ram/src/git/icon/grids"
      # check, if a given input files has vertival layers of a given thickness array
      targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
      ifile = [iconpath,"ts_phc_annual-iconR2B04-L10_50-1000m.nc"].join('/')
      assert_equal(["25 100 250 500 875 1400 2100 3000 4000 5000",
                   "25 100 250 500 875 1400 2100 3000 4000 5000"],Cdo.showlevel(:in => ifile))
      thicknesses = Cdo.thicknessOfLevels(:in => ifile)
      assert_equal(targetThicknesses,thicknesses)
    end
  end

end

#  # Calling simple operators
#  #
#  # merge:
#  #   let files be an erray of valid filenames and ofile is a string
#  Cdo.merge(:in => outvars.join(" "),:out => ofile)
#  #   or with multiple arrays:
#  Cdo.merge(:in => [ifiles0,ifiles1].flatten.join(' '),:out => ofile)
#  # selname:
#  #   lets grep out some variables from ifile:
#  ["T","U","V"].each {|varname|
#    varfile = varname+".nc"
#    Cdo.selname(varname,:in => ifile,:out => varfile)
#  }
#  #   a threaded version of this could look like:
#  ths = []
#  ["T","U","V"].each {|outvar|
#    ths << Thread.new(outvar) {|ovar|
#      varfile = varname+".nc"
#      Cdo.selname(varname,:in => ifile,:out => varfile)
#    }
#  }
#  ths.each {|th| th.join}
#  # another example with sub:
#  Cdo.sub(:in => [oldfile,newfile].join(' '), :out => diff)
#  
#  # It is possible too use the 'send' method
#  operator  = /grb/.match(File.extname(ifile)) ? :showcode : :showname
#  inputVars = Cdo.send(operator,:in => ifile)
#  # show and info operators are writing to stdout. cdo.rb tries to collects this into arrays
#  #
#  # Same stuff with other operators:
#  operator = case var
#             when Fixnum then 'selcode'
#             when String then 'selname'
#             else
#               warn "Wrong usage of variable identifier for '#{var}' (class #{var.class})!"
#             end
#  Cdo.send(operator,var,:in => @ifile, :out => varfile)
#  
#  # Pass an array for operators with multiple options:
#  #   Perform conservative remapping with pregenerated weights
#  Cdo.remap([gridfile,weightfile],:in => copyfile,:out => outfile)
#  #   Create vertical height levels out of hybrid model levels
#  Cdo.ml2hl([0,20,50,100,200,400,800,1200].join(','),:in => hybridlayerfile, :out => reallayerfile)
#  # or use multiple arguments directly
#  Cdo.remapeta(vctfile,orofile,:in => ifile,:out => hybridlayerfile)
#  
#  # the powerfull expr operator:
#  # taken from the tutorial in https://code.zmaw.de/projects/cdo/wiki/Tutorial#The-_expr_-Operator
#  SCALEHEIGHT  = 10000.0
#  C_EARTH_GRAV = 9.80665
#  # function for later computation of hydrostatic atmosphere pressure
#  PRES_EXPR    = lambda {|height| "101325.0*exp((-1)*(1.602769777072154)*log((exp(#{height}/#{SCALEHEIGHT})*213.15+75.0)/288.15))"}
#  TEMP_EXPR    = lambda {|height| "213.0+75.0*exp(-#{height}/#{SCALEHEIGHT})"}
#  
#  # Create Pressure and Temperature out of a height field 'geopotheight' from ifile
#  Cdo.expr("'p=#{PRES_EXPR['geopotheight']}'", :in => ifile, :out => presFile)
#  Cdo.expr("'t=#{TEMP_EXPR['geopotheight']}'", :in => ifile, :out => tempFile)
#  
#  
#  # TIPS: I often work with temporary files and for getting rid of handling them manually the MyTempfile module can be used:
#  #       Simply include the following methods into you scripts and use tfile for any temporary variable
#  def tfile
#    MyTempfile.path
#  end
#  # As an example, the computation of simple atmospherric density could look like
#  presFile, tempFile = tfile, tfile
#  Cdo.expr("'p=#{PRES_EXPR['geopotheight']}'", :in => ifile, :out => presFile)
#  Cdo.expr("'t=#{TEMP_EXPR['geopotheight']}'", :in => ifile, :out => tempFile)
#  Cdo.chainCall("setname,#{rho} -divc,#{C_R} -div",in: [presFile,tempFile].join(' '), out: densityFile)
#  
#  # For debugging, it is helpfull, to avoid the automatic cleanup at the end of the scripts:
#  MyTempfile.setPersist(true)
#  # creates randomly names files. Switch on debugging with 
#  Cdo.Debug = true
