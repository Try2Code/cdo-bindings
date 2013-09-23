$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'test/unit'
require 'cdo'
require 'pp'

class TestCdo < Test::Unit::TestCase

  DEFAULT_CDO_PATH = 'cdo'

  def test_cdo
    assert_equal(true,Cdo.checkCdo)
    if ENV['CDO']
      assert_equal(ENV['CDO'],Cdo.getCdo)
    else
      assert_equal(DEFAULT_CDO_PATH,Cdo.getCdo)
    end
    newCDO="#{ENV['HOME']}/bin/cdo"
    if File.exist?(newCDO) then
      Cdo.setCdo(newCDO)
      assert_equal(true,Cdo.checkCdo)
      assert_equal(newCDO,Cdo.getCdo)
    end
  end
  def test_getOperators
    %w[for random stdatm info showlevel sinfo remap geopotheight mask topo thicknessOfLevels].each {|op|
      if ["thicknessOfLevels"].include?(op)
        assert(Cdo.respond_to?(op),"Operator '#{op}' not found")
      else
        assert(Cdo.getOperators.include?(op),"Operator '#{op}' not found")
      end
    }
  end
  def test_listAllOperators
    print Cdo.operators.join("\n")
  end

  def test_outputOperators
    Cdo.debug = true
    levels = Cdo.showlevel(:input => "-stdatm,0")
    assert_equal([0,0].map(&:to_s),levels)

    info = Cdo.sinfo(:input => "-stdatm,0")
    assert_equal("File format: GRIB",info[0])

    values = Cdo.outputkey("value",:input => "-stdatm,0")
    assert_equal(["1013.25", "288"],values)
    values = Cdo.outputkey("value",:input => "-stdatm,0,10000")
    assert_equal(["1013.25", "271.913", "288", "240.591"],values)
    values = Cdo.outputkey("level",:input => "-stdatm,0,10000")
    assert_equal(["0", "10000","0", "10000"],values)
  end
  def test_CDO_version
    assert("1.4.3.1" < Cdo.version,"Version to low: #{Cdo.version}")
  end
  def test_args
    #Cdo.Debug = true
    #MyTempfile.setPersist(true)
    ofile0 = MyTempfile.path
    ofile1 = MyTempfile.path
    ofile2 = MyTempfile.path
    ofile3 = MyTempfile.path
    Cdo.stdatm(0,20,40,80,200,230,400,600,1100,:output => ofile0)
    Cdo.intlevel(0,10,50,100,500,1000,  :input => ofile0,:output => ofile1)
    Cdo.intlevel([0,10,50,100,500,1000],:input => ofile0,:output => ofile2)
    Cdo.sub(:input => [ofile1,ofile2].join(' '),:output => ofile3)
    info = Cdo.infon(:input => ofile3)
    (1...info.size).each {|i| assert_equal(0.0,info[i].split[-1].to_f)}
  end
  def test_operator_options
    Cdo.debug=true
    targetLevels = [0,10,50,100,200,400,1000]
    levels = Cdo.showlevel(:input => " -stdatm,#{targetLevels.join(',')}")
    [0,1].each {|i| assert_equal(targetLevels.join(' '),levels[i])}
  end
  def test_CDO_options
    names = Cdo.showname(:input => "-stdatm,0",:options => "-f nc")
    assert_equal(["P T"],names)

    if Cdo.hasLib?("sz")
      ofile = Cdo.topo(:output => ofile,:options => "-z szip")
      assert_equal(["GRIB SZIP"],Cdo.showformat(:input => ofile))
    end
  end
  def test_chain
    Cdo.debug = true
    ofile = Cdo.setname('veloc',:input => " -copy -random,r1x1",:options => "-f nc")
    assert_equal(["veloc"],Cdo.showname(:input => ofile))
  end

  def test_diff
    Cdo.debug = true
    diffv = Cdo.diffn(:input => "-random,r1x1 -random,r1x1")
    assert_equal(diffv[1].split(' ')[-1],"random")
    assert_equal(diffv[1].split(' ')[-3],"0.53060")
    diff  = Cdo.diff(:input => "-random,r1x1 -random,r1x1")
    assert_equal(diff[1].split(' ')[-3],"0.53060")
  end

  def test_operators
    assert_includes(Cdo.operators,"infov")
    assert_includes(Cdo.operators,"showlevel")
  end

  def test_bndLevels
    ofile = Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:options => "-f nc")
    assert_equal([0, 50.0, 150.0, 350.0, 650.0, 1100.0, 1700.0, 2500.0, 3500.0, 4500.0, 5500.0],
                 Cdo.boundaryLevels(:input => "-selname,T #{ofile}"))
    assert_equal([50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0, 1000.0, 1000.0, 1000.0],
                 Cdo.thicknessOfLevels(:input => ofile))
  end

  def test_combine
    ofile0, ofile1 = MyTempfile.path, MyTempfile.path
    Cdo.fldsum(:input => Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:options => "-f nc"),:output => ofile0)
    Cdo.fldsum(:input => "-stdatm,25,100,250,500,875,1400,2100,3000,4000,5000",:options => "-f nc",:output => ofile1)
    Cdo.setReturnCdf
    MyTempfile.showFiles
    diff = Cdo.sub(:input => [ofile0,ofile1].join(' ')).var('T').get
    assert_equal(0.0,diff.min)
    assert_equal(0.0,diff.max)
    Cdo.setReturnCdf(false)
  end

  def test_tempfile
    ofile0, ofile1 = MyTempfile.path, MyTempfile.path
    assert_not_equal(ofile0,ofile1)
    # Tempfile should not disappeare even if the GC was started
    puts ofile0
    assert(File.exist?(ofile0))
    GC.start
    assert(File.exist?(ofile0))
  end

  def test_returnCdf
    ofile = rand(0xfffff).to_s + '_test_returnCdf.nc'
    vals = Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
    assert_equal(ofile,vals)
    Cdo.setReturnCdf
    vals = Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
    assert_equal(["lon","lat","level","P","T"],vals.var_names)
    assert_equal(276,vals.var("T").get.flatten.mean.floor)
    Cdo.unsetReturnCdf
    vals = Cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
    assert_equal(ofile,vals)
    FileUtils.rm(ofile)
  end
  def test_simple_returnCdf
    ofile0, ofile1 = MyTempfile.path, MyTempfile.path
    sum = Cdo.fldsum(:input => Cdo.stdatm(0,:options => "-f nc"),
               :returnCdf => true).var("P").get
    assert_equal(1013.25,sum.min)
    sum = Cdo.fldsum(:input => Cdo.stdatm(0,:options => "-f nc"),:output => ofile0)
    assert_equal(ofile0,sum)
    test_returnCdf
  end
  def test_force
    outs = []
    # tempfiles
    outs << Cdo.stdatm(0,10,20)
    outs << Cdo.stdatm(0,10,20)
    assert_not_equal(outs[0],outs[1])

    # deticated output, force = true
    outs.clear
    outs << Cdo.stdatm(0,10,20,:output => 'test_force')
    mtime0 = File.stat(outs[-1]).mtime
    outs << Cdo.stdatm(0,10,20,:output => 'test_force')
    mtime1 = File.stat(outs[-1]).mtime
    assert_not_equal(mtime0,mtime1)
    assert_equal(outs[0],outs[1])
    FileUtils.rm('test_force')
    outs.clear

    # dedicated output, force = false
    ofile = 'test_force_false'
    outs << Cdo.stdatm(0,10,20,:output => ofile,:force => false)
    mtime0 = File.stat(outs[-1]).mtime
    outs << Cdo.stdatm(0,10,20,:output => ofile,:force => false)
    mtime1 = File.stat(outs[-1]).mtime
    assert_equal(mtime0,mtime1)
    assert_equal(outs[0],outs[1])
    FileUtils.rm(ofile)
    outs.clear

    # dedicated output, global force setting
    ofile = 'test_force_global'
    Cdo.forceOutput = false
    outs << Cdo.stdatm(0,10,20,:output => ofile)
    mtime0 = File.stat(outs[-1]).mtime
    outs << Cdo.stdatm(0,10,20,:output => ofile)
    mtime1 = File.stat(outs[-1]).mtime
    assert_equal(mtime0,mtime1)
    assert_equal(outs[0],outs[1])
    FileUtils.rm(ofile)
    outs.clear
  end

  def test_thickness
    levels            = "25 100 250 500 875 1400 2100 3000 4000 5000".split
    targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
    assert_equal(targetThicknesses, Cdo.thicknessOfLevels(:input => "-selname,T -stdatm,#{levels.join(',')}"))
  end

  def test_showlevels
    sourceLevels = %W{25 100 250 500 875 1400 2100 3000 4000 5000}
    assert_equal(sourceLevels,
                 Cdo.showlevel(:input => "-selname,T #{Cdo.stdatm(*sourceLevels,:options => '-f nc')}")[0].split)
  end

  def test_verticalLevels
    Cdo.debug = true
    targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
    sourceLevels = %W{25 100 250 500 875 1400 2100 3000 4000 5000}
    thicknesses = Cdo.thicknessOfLevels(:input => "-selname,T #{Cdo.stdatm(*sourceLevels,:options => '-f nc')}")
    assert_equal(targetThicknesses,thicknesses)
  end

  def test_parseArgs
    io,opts = Cdo.parseArgs([1,2,3,:input => '1',:output => '2',:force => true,:returnCdf => "T"])
    assert_equal("1",io[:input])
    assert_equal("2",io[:output])
    assert_equal(true,io[:force])
    assert_equal("T",io[:returnCdf])
    pp [io,opts]
  end 

  def test_returnArray
    temperature = Cdo.stdatm(0,:options => '-f nc',:returnCdf => true).var('T').get.flatten[0]
    assert_raise ArgumentError do
      Cdo.stdatm(0,:options => '-f nc',:returnArray => 'TT')
    end
    temperature = Cdo.stdatm(0,:options => '-f nc',:returnArray => 'T')
    assert_equal(288.0,temperature.flatten[0])
    pressure = Cdo.stdatm(0,1000,:options => '-f nc -b F64',:returnArray => 'P')
    assert_equal("1013.25 898.543456035875",pressure.flatten.to_a.join(' '))
  end
  def test_returnMaArray
    Cdo.debug = true
    topo = Cdo.topo(:options => '-f nc',:returnMaArray => 'topo')
    assert_equal(-1890.0,topo.mean.round)
    bathy = Cdo.setrtomiss(0,10000,
        :input => Cdo.topo(:options => '-f nc'),:returnMaArray => 'topo')
    assert_equal(-3386.0,bathy.mean.round)
    oro = Cdo.setrtomiss(-10000,0,
        :input => Cdo.topo(:options => '-f nc'),:returnMaArray => 'topo')
    assert_equal(1142.0,oro.mean.round)
    bathy = Cdo.remapnn('r2x2',:input => Cdo.topo(:options => '-f nc'), :returnMaArray => 'topo')
    assert_equal(-4298.0,bathy[0,0])
    assert_equal(-2669.0,bathy[1,0])
    ta = Cdo.remapnn('r2x2',:input => Cdo.topo(:options => '-f nc'))
    tb = Cdo.subc(-2669.0,:input => ta)
    withMask = Cdo.div(:input => ta+" "+tb,:returnMaArray => 'topo')
    assert(-8.0e+33 > withMask[1,0])
    assert(0 < withMask[0,0])
    assert(0 < withMask[0,1])
    assert(0 < withMask[1,1])
  end

  def test_errorException
    Cdo.debug = true
    # stdout operators get get wrong input
    assert_raise ArgumentError do
      Cdo.showname(:input => '-for,d')
    end
    # non-existing operator
    assert_raise ArgumentError do
      Cdo.neverDefinedOperator()
    end
    # standard opertor get mis-spelled value
    assert_raise ArgumentError do
      Cdo.remapnn('r-10x10')
    end
    # standard operator get unexisting operator as input stream
    assert_raise ArgumentError do
      Cdo.remapnn('r10x10',:input => '-99topo')
    end
    # missing input stream
    assert_raise ArgumentError do
      Cdo.setname('setname')
    end
    # missing input stream for stdout-operator
    assert_raise ArgumentError do
      Cdo.showname
    end
  end

  def test_inputArray
    # check for file input
    fileA = Cdo.stdatm(0)
    fileB = Cdo.stdatm(0)
    files = [fileA,fileB]
    assert_equal(Cdo.diffv(:input => files.join(' ')),
                 Cdo.diffv(:input => files))
    assert_equal("0 of 2 records differ",Cdo.diffv(:input => files).last)
    # check for operator input
    assert_equal("0 of 2 records differ",Cdo.diffv(:input => ["-stdatm,0","-stdatm,0"]).last)
    # check for operator input and files
    assert_equal("0 of 2 records differ",Cdo.diffv(:input => ["-stdatm,0",fileB]).last)
  end

  def test_libs
    assert(Cdo.hasLib?("cdi"),"CDI support missing")
    assert(Cdo.hasLib?("nc4"),"netcdf4 support missing")
    assert(Cdo.hasLib?("netcdf"),"netcdf support missing")
    assert_equal(false,Cdo.hasLib?("boost"))
    if 'thingol' == `hostname`.chomp
      assert_equal('1.10.0',Cdo.libsVersion("grib_api")) if Cdo.hasLib?("grib_api") 
      Cdo.debug  = true
      assert(! Cdo.libs.has_key?('magics'),"Magics support shoud not be build in the system wide installation")
      Cdo.setCdo('../../src/cdo')
      assert(Cdo.libs.has_key?('magics'),"Magics support is expected in the local development binary")
    end
    assert_raise ArgumentError do
      Cdo.libsVersion("foo")
    end
  end

  def test_output_set_to_nil
    assert_equal(String,Cdo.topo(:output => nil).class)
    assert_equal("File format: GRIB",Cdo.sinfov(:input => "-topo", :output => nil)[0])
  end

  if 'thingol' == `hostname`.chomp  then
    def test_readCdf
      input = "-settunits,days  -setyear,2000 -for,1,4"
      cdfFile = Cdo.copy(:options =>"-f nc",:input=>input)
      cdf     = Cdo.readCdf(cdfFile)
      assert_equal(['lon','lat','time','for'],cdf.var_names)
    end
    def test_selIndexListFromIcon
      input = "~/data/icon/oce.nc"
    end
    def test_readArray
      ifile = '/home/ram/data/examples/EH5_AMIP_1_TSURF_1991-1995.nc'
      assert_equal([192, 96, 10],Cdo.readArray(Cdo.seltimestep('1/10',:input => ifile), 'tsurf').shape)
    end
    def test_doc
      Cdo.debug = true
      Cdo.help(:remap)
      Cdo.help(:infov)
      Cdo.help(:topo)
      Cdo.help(:notDefinedOP)
      Cdo.help
    end


  end

end

#  # Calling simple operators
#  #
#  # merge:
#  #   let files be an erray of valid filenames and ofile is a string
#  Cdo.merge(:input => outvars.join(" "),:output => ofile)
#  #   or with multiple arrays:
#  Cdo.merge(:input => [ifiles0,ifiles1].flatten.join(' '),:output => ofile)
#  # selname:
#  #   lets grep out some variables from ifile:
#  ["T","U","V"].each {|varname|
#    varfile = varname+".nc"
#    Cdo.selname(varname,:input => ifile,:output => varfile)
#  }
#  #   a threaded version of this could look like:
#  ths = []
#  ["T","U","V"].each {|outvar|
#    ths << Thread.new(outvar) {|ovar|
#      varfile = varname+".nc"
#      Cdo.selname(varname,:input => ifile,:output => varfile)
#    }
#  }
#  ths.each {|th| th.join}
#  # another example with sub:
#  Cdo.sub(:input => [oldfile,newfile].join(' '), :output => diff)
#  
#  # It is possible too use the 'send' method
#  operator  = /grb/.match(File.extname(ifile)) ? :showcode : :showname
#  inputVars = Cdo.send(operator,:input => ifile)
#  # show and info operators are writing to stdout. cdo.rb tries to collects this into arrays
#  #
#  # Same stuff with other operators:
#  operator = case var
#             when Fixnum then 'selcode'
#             when String then 'selname'
#             else
#               warn "Wrong usage of variable identifier for '#{var}' (class #{var.class})!"
#             end
#  Cdo.send(operator,var,:input => @ifile, :output => varfile)
#  
#  # Pass an array for operators with multiple options:
#  #   Perform conservative remapping with pregenerated weights
#  Cdo.remap([gridfile,weightfile],:input => copyfile,:output => outfile)
#  #   Create vertical height levels out of hybrid model levels
#  Cdo.ml2hl([0,20,50,100,200,400,800,1200].join(','),:input => hybridlayerfile, :output => reallayerfile)
#  # or use multiple arguments directly
#  Cdo.remapeta(vctfile,orofile,:input => ifile,:output => hybridlayerfile)
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
#  Cdo.expr("'p=#{PRES_EXPR['geopotheight']}'", :input => ifile, :output => presFile)
#  Cdo.expr("'t=#{TEMP_EXPR['geopotheight']}'", :input => ifile, :output => tempFile)
#  
#  
#  # TIPS: I often work with temporary files and for getting rid of handling them manually the MyTempfile module can be used:
#  #       Simply include the following methods into you scripts and use tfile for any temporary variable
#  def tfile
#    MyTempfile.path
#  end
#  # As an example, the computation of simple atmospherric density could look like
#  presFile, tempFile = tfile, tfile
#  Cdo.expr("'p=#{PRES_EXPR['geopotheight']}'", :input => ifile, :output => presFile)
#  Cdo.expr("'t=#{TEMP_EXPR['geopotheight']}'", :input => ifile, :output => tempFile)
#  Cdo.chainCall("setname,#{rho} -divc,#{C_R} -div",in: [presFile,tempFile].join(' '), out: densityFile)
#  
#  # For debugging, it is helpfull, to avoid the automatic cleanup at the end of the scripts:
#  MyTempfile.setPersist(true)
#  # creates randomly names files. Switch on debugging with 
#  Cdo.Debug = true
