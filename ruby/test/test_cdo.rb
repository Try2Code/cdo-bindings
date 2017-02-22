$:.unshift File.join(File.dirname(__FILE__),"..","lib")

require 'minitest/autorun'
require 'cdo'
require 'pp'


#===============================================================================
def rm(files); files.each {|f| FileUtils.rm(f) if File.exists?(f)};end


class TestCdo < Minitest::Test

  DEFAULT_CDO_PATH = 'cdo'

  @@show           = ENV.has_key?('SHOW')
  @@maintainermode = ENV.has_key?('MAINTAINERMODE')

  def setup
    @cdo = Cdo.new
  end

  def test_cdo
    assert_equal(true,@cdo.check)
    if ENV['CDO']
      assert_equal(ENV['CDO'],@cdo.cdo)
    else
      assert_equal(DEFAULT_CDO_PATH,@cdo.cdo)
    end
    newCDO="#{ENV['HOME']}/local/bin/cdo-dev"
    if File.exist?(newCDO) then
      cdo = Cdo.new
      cdo.cdo = newCDO
      assert_equal(true,cdo.check)
      assert_equal(newCDO,cdo.cdo)
    end
    pp 'MAINTAINERMODE: '
    pp @@maintainermode
    pp @@show
  end
  def test_getOperators
    %w[for random stdatm info showlevel sinfo remap geopotheight mask topo thicknessOfLevels].each {|op|
      if ["thicknessOfLevels"].include?(op)
        assert(@cdo.respond_to?(op),"Operator '#{op}' not found")
      else
        assert(@cdo.operators.include?(op),"Operator '#{op}' not found")
      end
    }
    assert(@cdo.operators.include?('diff'),"Operator alias 'diff' is not callable")
  end
  def test_listAllOperators
    assert(@cdo.operators.size > 700,"cound not find enough operators")
  end

  def test_outputOperators
    @cdo.debug = true
    levels = @cdo.showlevel(:input => "-stdatm,0")
    assert_equal([0,0].map(&:to_s),levels)

    info = @cdo.sinfo(:input => "-stdatm,0")
    assert_equal("GRIB",info[0].split(':').last.strip)

    values = @cdo.outputkey("value",:input => "-stdatm,0")
    assert_equal(["1013.25", "288"],values[-2..-1])
    values = @cdo.outputkey("value",:input => "-stdatm,0,10000")
    assert_equal(["1013.25", "271.913", "288", "240.591"],values[-4..-1])
    values = @cdo.outputkey("level",:input => "-stdatm,0,10000")
    assert_equal(["0", "10000","0", "10000"],values[-4..-1])
  end
  def test_CDO_version
    assert("1.4.3.1" < @cdo.version,"Version too low: #{@cdo.version}")
    assert("1.8.1" > @cdo.version,"Version too high: #{@cdo.version}")
  end
  def test_args
    ofile0 = @cdo.stdatm(0,20,40,80,200,230,400,600,1100)
    ofile1 = @cdo.intlevel(0,10,50,100,500,1000,  :input => ofile0)
    ofile2 = @cdo.intlevel([0,10,50,100,500,1000],:input => ofile0)
    ofile3 = @cdo.sub(:input => [ofile1,ofile2].join(' '))
    info = @cdo.infon(:input => ofile3)
    (1...info.size).each {|i| assert_equal(0.0,info[i].split[-1].to_f)}
  end
  def test_operator_options
    @cdo.debug=true
    targetLevels = [0,10,50,100,200,400,1000]
    levels = @cdo.showlevel(:input => " -stdatm,#{targetLevels.join(',')}")
    [0,1].each {|i| assert_equal(targetLevels.join(' '),levels[i])}
    names = @cdo.showname(:input => "-stdatm,0",:options => "-f nc")
    assert_equal(["P T"],names)
  end
  def test_chain
    @cdo.debug = true
    ofile = @cdo.setname('veloc',:input => " -copy -random,r1x1",:options => "-f nc")
    assert_equal(["veloc"],@cdo.showname(:input => ofile))
  end

  def test_diff
    diffv_ = @cdo.diffn(:input => "-random,r1x1 -random,r1x1")
    diff_  = @cdo.diffv(:input => "-random,r1x1 -random,r1x1")
    return

    assert_equal(diffv[1].split(' ')[-1],"random")
    assert_equal(diffv[1].split(' ')[-3],"0.53060")
    pp diff
    assert_equal(diff[1].split(' ')[-3],"0.53060")
  end

  def test_bndLevels
    ofile = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:options => "-f nc")
    assert_equal([0, 50.0, 150.0, 350.0, 650.0, 1100.0, 1700.0, 2500.0, 3500.0, 4500.0, 5500.0],
                 @cdo.boundaryLevels(:input => "-selname,T #{ofile}"))
    assert_equal([50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0, 1000.0, 1000.0, 1000.0],
                 @cdo.thicknessOfLevels(:input => ofile))
  end

  def test_force
    outs = []
    # tempfiles
    outs << @cdo.stdatm(0,10,20)
    outs << @cdo.stdatm(0,10,20)
    assert(outs[0] != outs[1])

    # deticated output, force = true
    outs.clear
    outs << @cdo.stdatm(0,10,20,:output => 'test_force')
    mtime0 = File.stat(outs[-1]).mtime
    outs << @cdo.stdatm(0,10,20,:output => 'test_force')
    mtime1 = File.stat(outs[-1]).mtime
    assert(mtime0 != mtime1)
    assert_equal(outs[0],outs[1])
    FileUtils.rm('test_force')
    outs.clear

    # dedicated output, force = false
    ofile = 'test_force_false'
    outs << @cdo.stdatm(0,10,20,:output => ofile,:force => false)
    mtime0 = File.stat(outs[-1]).mtime
    outs << @cdo.stdatm(0,10,20,:output => ofile,:force => false)
    mtime1 = File.stat(outs[-1]).mtime
    assert_equal(mtime0,mtime1)
    assert_equal(outs[0],outs[1])
    FileUtils.rm(ofile)
    outs.clear

    # dedicated output, global force setting
    ofile = 'test_force_global'
    @cdo.forceOutput = false
    outs << @cdo.stdatm(0,10,20,:output => ofile)
    mtime0 = File.stat(outs[-1]).mtime
    outs << @cdo.stdatm(0,10,20,:output => ofile)
    mtime1 = File.stat(outs[-1]).mtime
    assert_equal(mtime0,mtime1)
    assert_equal(outs[0],outs[1])
    FileUtils.rm(ofile)
    outs.clear
  end

  def test_thickness
    levels            = "25 100 250 500 875 1400 2100 3000 4000 5000".split
    targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
    assert_equal(targetThicknesses, @cdo.thicknessOfLevels(:input => "-selname,T -stdatm,#{levels.join(',')}"))
  end

  def test_outputOperators
    sourceLevels = %W{25 100 250 500 875 1400 2100 3000 4000 5000}
    assert_equal(sourceLevels,
                 @cdo.showlevel(:input => "-selname,T #{@cdo.stdatm(*sourceLevels,:options => '-f nc')}")[0].split)
    
   ## test autoSplit usage
   #levels = @cdo.showlevel(input: "-stdatm,0,10,20",autoSplit: ' ')
   #assert_equal([['0','10','20'],['0','10','20']],levels)
   #assert_equal(sourceLevels,
   #             @cdo.showlevel(:input => "-selname,T #{@cdo.stdatm(*sourceLevels,:options => '-f nc')}",
   #                            :autoSplit => ' '))

   #timesExpected = ['2001-01-01T12:00:00',
   #                 '2001-01-01T13:00:00',
   #                 '2001-01-01T14:00:00',
   #                 '2001-01-01T15:00:00',
   #                 '2001-01-01T16:00:00',
   #                 '2001-01-01T17:00:00',
   #                 '2001-01-01T18:00:00',
   #                 '2001-01-01T19:00:00',
   #                 '2001-01-01T20:00:00',
   #                 '2001-01-01T21:00:00']
   #assert_equal(timesExpected,
   #                 @cdo.showtimestamp(input: "-settaxis,2001-01-01,12:00,1hour -for,1,10", autoSplit: '  '))

   #assert_equal(['P T'],@cdo.showname(input: "-stdatm,0"))
   #assert_equal([['P','T']],@cdo.showname(input: "-stdatm,0",autoSplit: ' '))
   #assert_equal(['P','T'],@cdo.showname(input: "-stdatm,0",autoSplit: ' ')[0])
  end

  def test_verticalLevels
    @cdo.debug = true
    targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
    sourceLevels = %W{25 100 250 500 875 1400 2100 3000 4000 5000}
    thicknesses = @cdo.thicknessOfLevels(:input => "-selname,T #{@cdo.stdatm(*sourceLevels,:options => '-f nc')}")
    assert_equal(targetThicknesses,thicknesses)
  end

  def test_parseArgs
    io,opts = Cdo.parseArgs([1,2,3,:input => '1',:output => '2',:force => true,:returnCdf => "T",:autoSplit => '  '])
    assert_equal("1",io[:input])
    assert_equal("2",io[:output])
    assert_equal(true,io[:force])
    assert_equal("T",io[:returnCdf])
    assert_equal("  ",io[:autoSplit])
    pp [io,opts]
  end

  def test_errorException
    @cdo.debug = true
    # stdout operators get get wrong input
    assert_raises ArgumentError do
      @cdo.showname(:input => '-for,d')
    end
    # non-existing operator
    assert_raises ArgumentError do
      @cdo.neverDefinedOperator()
    end
    # standard opertor get mis-spelled value
    assert_raises ArgumentError do
      @cdo.remapnn('r-10x10')
    end
    # standard operator get unexisting operator as input stream
    assert_raises ArgumentError do
      @cdo.remapnn('r10x10',:input => '-99topo')
    end
    # missing input stream
    assert_raises ArgumentError do
      @cdo.setname('setname')
    end
    # missing input stream for stdout-operator
    assert_raises ArgumentError do
      @cdo.showname
    end
  end

  def test_inputArray
    # check for file input
    fileA = @cdo.stdatm(0)
    fileB = @cdo.stdatm(0)
    files = [fileA,fileB]
    assert_equal(@cdo.diffv(:input => files.join(' ')),
                 @cdo.diffv(:input => files))
    assert_nil(@cdo.diffv(:input => files).last)
    # check for operator input
    assert_nil(@cdo.diffv(:input => ["-stdatm,0","-stdatm,0"]).last)
    # check for operator input and files
    assert_nil(@cdo.diffv(:input => ["-stdatm,0",fileB]).last)
  end

  def test_filetypes
    assert(@cdo.filetypes.find{|ft| /^grb/.match(ft)},"GRIB support missing")
    assert(@cdo.filetypes.include?("nc4"),"NETCDF4 support missing")
    assert(@cdo.filetypes.include?("ext"),"EXTRA support missing")
    assert_raises ArgumentError do
      @cdo.filetypes("foo")
    end
  end

  def test_noOutputOps
    case
    when "1.8.0" == @cdo.version then
      assert_equal(Cdo::NoOutputOperators,@cdo.noOutputOps)
    when "1.8.0" < @cdo.version
      assert((Cdo::NoOutputOperators - @cdo.noOutputOps).empty?)
    end
  end

  def test_output_set_to_nil
    assert_equal(String,@cdo.topo(:output => nil).class)
    assert_equal("File format: GRIB".tr(' ',''),@cdo.sinfov(:input => "-topo", :output => nil)[0].tr(' ',''))
  end

  if @@maintainermode  then
    require 'unifiedPlot'

    def test_returnArray
      temperature = @cdo.stdatm(0,:options => '-f nc',:returnCdf => true).var('T').get.flatten[0]
      assert_raises ArgumentError do
        @cdo.stdatm(0,:options => '-f nc',:returnArray => 'TT')
      end
      temperature = @cdo.stdatm(0,:options => '-f nc',:returnArray => 'T')
      assert_equal(288.0,temperature.flatten[0])
      pressure = @cdo.stdatm(0,1000,:options => '-f nc -b F64',:returnArray => 'P')
      assert_equal("1013.25 898.543456035875",pressure.flatten.to_a.join(' '))
    end
    def test_returnMaArray
      @cdo.debug = true
      topo = @cdo.topo(:options => '-f nc',:returnMaArray => 'topo')
      assert_equal(-1890.0,topo.mean.round)
      bathy = @cdo.setrtomiss(0,10000,
          :input => @cdo.topo(:options => '-f nc'),:returnMaArray => 'topo')
      assert_equal(-3386.0,bathy.mean.round)
      oro = @cdo.setrtomiss(-10000,0,
          :input => @cdo.topo(:options => '-f nc'),:returnMaArray => 'topo')
      assert_equal(1142.0,oro.mean.round)
      bathy = @cdo.remapnn('r2x2',:input => @cdo.topo(:options => '-f nc'), :returnMaArray => 'topo')
      assert_equal(-4298.0,bathy[0,0])
      assert_equal(-2669.0,bathy[1,0])
      ta = @cdo.remapnn('r2x2',:input => @cdo.topo(:options => '-f nc'))
      tb = @cdo.subc(-2669.0,:input => ta)
      withMask = @cdo.div(:input => ta+" "+tb,:returnMaArray => 'topo')
      assert(-8.0e+33 > withMask[1,0])
      assert(0 < withMask[0,0])
      assert(0 < withMask[0,1])
      assert(0 < withMask[1,1])
    end
    def test_combine
      ofile0, ofile1 = MyTempfile.path, MyTempfile.path
      @cdo.fldsum(:input => @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:options => "-f nc"),:output => ofile0)
      @cdo.fldsum(:input => "-stdatm,25,100,250,500,875,1400,2100,3000,4000,5000",:options => "-f nc",:output => ofile1)
      @cdo.returnCdf = true
      MyTempfile.showFiles
      diff = @cdo.sub(:input => [ofile0,ofile1].join(' ')).var('T').get
      assert_equal(0.0,diff.min)
      assert_equal(0.0,diff.max)
      @cdo.returnCdf = false
    end

    def test_tempfile
      ofile0, ofile1 = MyTempfile.path, MyTempfile.path
      assert(ofile0 != ofile1, "Found equal tempfiles!")
      # Tempfile should not disappeare even if the GC was started
      puts ofile0
      assert(File.exist?(ofile0))
      GC.start
      assert(File.exist?(ofile0))
    end

    def test_returnCdf
      ofile = rand(0xfffff).to_s + '_test_returnCdf.nc'
      vals = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
      assert_equal(ofile,vals)
      @cdo.returnCdf = true
      vals = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
      assert_equal(["lon","lat","level","P","T"],vals.var_names)
      assert_equal(276,vals.var("T").get.flatten.mean.floor)
      @cdo.returnCdf = false
      vals = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
      assert_equal(ofile,vals)
      FileUtils.rm(ofile)
    end
    def test_simple_returnCdf
      ofile0, ofile1 = MyTempfile.path, MyTempfile.path
      sum = @cdo.fldsum(:input => @cdo.stdatm(0,:options => "-f nc"),
                 :returnCdf => true).var("P").get
      assert_equal(1013.25,sum.min)
      sum = @cdo.fldsum(:input => @cdo.stdatm(0,:options => "-f nc"),:output => ofile0)
      assert_equal(ofile0,sum)
      test_returnCdf
    end
    def test_readCdf
      input = "-settunits,days  -setyear,2000 -for,1,4"
      cdfFile = @cdo.copy(:options =>"-f nc",:input=>input)
      cdf     = @cdo.readCdf(cdfFile)
      assert_equal(['lon','lat','time','for'],cdf.var_names)
    end
    def test_selIndexListFromIcon
      input = "~/data/icon/oce.nc"
    end
    def test_readArray
      @cdo.debug = true
      assert_equal([40,80],@cdo.readArray(@cdo.sellonlatbox(-10,10,-20,20,:input => '-topo',:options => '-f nc'), 'topo').shape)
    end
    def test_doc
      @cdo.debug = true
      @cdo.help(:remap)
      @cdo.help(:infov)
      @cdo.help(:topo)
      @cdo.help(:notDefinedOP)
      @cdo.help
    end
    def test_fillmiss
      @cdo.debug = true
      # check up-down replacement
      rand = @cdo.setname('v',:input => '-random,r1x10 ', :options => ' -f nc',:output => '/tmp/rand.nc')
      cdf  = @cdo.openCdf(rand)
      vals = cdf.var('v').get
      cdf.var('v').put(vals.sort)
      cdf.sync
      cdf.close

      missRange = '0.3,0.8'
      arOrg = @cdo.setrtomiss(missRange,:input => cdf.path,:returnMaArray => 'v')
      arFm  = @cdo.fillmiss(:input => "-setrtomiss,#{missRange} #{cdf.path}",:returnMaArray => 'v')
      arFm1s= @cdo.fillmiss2(:input => "-setrtomiss,#{missRange} #{cdf.path}",:returnMaArray => 'v')
      vOrg  = arOrg[0,0..-1]
      vFm   = arFm[0,0..-1]
      vFm1s = arFm1s[0,0..-1]
      UnifiedPlot.linePlot([{:y => vOrg, :style => 'line',:title => 'org'},
                            {:y => vFm,  :style => 'points',:title => 'fillmiss'},
                            {:y => vFm1s,:style => 'points',:title => 'fillmiss2'}],
                            plotConf: {:yrange => '[0:1]'},title: 'r1x10') if @@show
      # check left-right replacement
      rand = @cdo.setname('v',:input => '-random,r10x1 ', :options => ' -f nc',:output => '/tmp/rand.nc')
      cdf  = @cdo.openCdf(rand)
      vals = cdf.var('v').get
      cdf.var('v').put(vals.sort)
      cdf.sync
      cdf.close

      missRange = '0.3,0.8'
      arOrg = @cdo.setrtomiss(missRange,:input => cdf.path,:returnMaArray => 'v')
      arFm  = @cdo.fillmiss(:input => "-setrtomiss,#{missRange} #{cdf.path}",:returnMaArray => 'v')
      arFm1s= @cdo.fillmiss2(:input => "-setrtomiss,#{missRange} #{cdf.path}",:returnMaArray => 'v')
      vOrg  =  arOrg[0..-1,0]
      vFm   =   arFm[0..-1,0]
      vFm1s = arFm1s[0..-1,0]
      UnifiedPlot.linePlot([{:y => vOrg, :style => 'line',:title => 'org'},
                            {:y => vFm,  :style => 'points',:title => 'fillmiss'},
                            {:y => vFm1s,:style => 'points',:title => 'fillmiss2'}],
                            plotConf: {:yrange => '[0:1]'},title: 'r10x1') if @@show
    end
  end

  def test_env
    oTag     = 'test_env_with_splitlevel_'
    levels   = [0,10,100]
    expected = levels.map {|l| "test_env_with_splitlevel_000#{l.to_s.rjust(3,'0')}"}
    # clean up first
    rm(Dir.glob(oTag+'*'))

    # oType = grb (default)
    ofiles = expected.map {|f| f += '.grb'}
    @cdo.splitlevel(input: "-stdatm,0,10,100",output: oTag)
    assert_equal(ofiles,Dir.glob(oTag+'*').sort)
    rm(ofiles)

    # oType = nc, from cdo options
    ofiles = expected.map {|f| f += '.nc'}
    @cdo.splitlevel(input: "-stdatm,0,10,100",output: oTag,options: '-f nc')
    assert_equal(ofiles,Dir.glob(oTag+'*').sort)
    rm(ofiles)

    # oType = nc, from input type
    ofiles = expected.map {|f| f += '.nc'}
    @cdo.splitlevel(input: @cdo.stdatm(0,10,100,options: '-f nc'),output: oTag)
    assert_equal(ofiles,Dir.glob(oTag+'*').sort)
    rm(ofiles)

    # oType = nc, from input ENV
    ofiles = expected.map {|f| f += '.nc2'}
    @cdo.env = {'CDO_FILE_SUFFIX' => '.nc2'}
    @cdo.splitlevel(input: @cdo.stdatm(0,10,100,options: '-f nc'),output: oTag)
    assert_equal(ofiles,Dir.glob(oTag+'*').sort)
    rm(ofiles)

    # oType = nc, from input ENV setting for each call
    ofiles = expected.map {|f| f += '.nc4'}
    @cdo.splitlevel(input: @cdo.stdatm(0,10,100,options: '-f nc'),output: oTag,env: {'CDO_FILE_SUFFIX' => '.nc4'})
    assert_equal(ofiles,Dir.glob(oTag+'*').sort)
    rm(ofiles)
  end
  def test_log
    cmd = '-fldmean -mul -random,r20x20 -topo,r20x20'
    #  logging without a real file
    @cdo = Cdo.new(                    returnNilOnError: true)
    @cdo.debug = false
    @cdo.logging = true
    @cdo.topo
    @cdo.temp
    @cdo.sinfov(input: cmd)
    puts @cdo.showLog
    @cdo.sinfov(input: '-top')
    @cdo.topo
    puts @cdo.showLog
    #  use a use definded file for looging
    @cdo = Cdo.new(logFile: 'test.log',logging: true, returnNilOnError: true)
    @cdo.topo
    @cdo.temp
    @cdo.sinfov(input: cmd)
    puts @cdo.showLog
  end
end

#  # Calling simple operators
#  #
#  # merge:
#  #   let files be an erray of valid filenames and ofile is a string
#  @cdo.merge(:input => outvars.join(" "),:output => ofile)
#  #   or with multiple arrays:
#  @cdo.merge(:input => [ifiles0,ifiles1].flatten.join(' '),:output => ofile)
#  # selname:
#  #   lets grep out some variables from ifile:
#  ["T","U","V"].each {|varname|
#    varfile = varname+".nc"
#    @cdo.selname(varname,:input => ifile,:output => varfile)
#  }
#  #   a threaded version of this could look like:
#  ths = []
#  ["T","U","V"].each {|outvar|
#    ths << Thread.new(outvar) {|ovar|
#      varfile = varname+".nc"
#      @cdo.selname(varname,:input => ifile,:output => varfile)
#    }
#  }
#  ths.each {|th| th.join}
#  # another example with sub:
#  @cdo.sub(:input => [oldfile,newfile].join(' '), :output => diff)
#
#  # It is possible too use the 'send' method
#  operator  = /grb/.match(File.extname(ifile)) ? :showcode : :showname
#  inputVars = @cdo.send(operator,:input => ifile)
#  # show and info operators are writing to stdout. cdo.rb tries to collects this into arrays
#  #
#  # Same stuff with other operators:
#  operator = case var
#             when Fixnum then 'selcode'
#             when String then 'selname'
#             else
#               warn "Wrong usage of variable identifier for '#{var}' (class #{var.class})!"
#             end
#  @cdo.send(operator,var,:input => @ifile, :output => varfile)
#
#  # Pass an array for operators with multiple options:
#  #   Perform conservative remapping with pregenerated weights
#  @cdo.remap([gridfile,weightfile],:input => copyfile,:output => outfile)
#  #   Create vertical height levels out of hybrid model levels
#  @cdo.ml2hl([0,20,50,100,200,400,800,1200].join(','),:input => hybridlayerfile, :output => reallayerfile)
#  # or use multiple arguments directly
#  @cdo.remapeta(vctfile,orofile,:input => ifile,:output => hybridlayerfile)
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
#  @cdo.expr("'p=#{PRES_EXPR['geopotheight']}'", :input => ifile, :output => presFile)
#  @cdo.expr("'t=#{TEMP_EXPR['geopotheight']}'", :input => ifile, :output => tempFile)
#
#
#  # TIPS: I often work with temporary files and for getting rid of handling them manually the MyTempfile module can be used:
#  #       Simply include the following methods into you scripts and use tfile for any temporary variable
#  def tfile
#    MyTempfile.path
#  end
#  # As an example, the computation of simple atmospherric density could look like
#  presFile, tempFile = tfile, tfile
#  @cdo.expr("'p=#{PRES_EXPR['geopotheight']}'", :input => ifile, :output => presFile)
#  @cdo.expr("'t=#{TEMP_EXPR['geopotheight']}'", :input => ifile, :output => tempFile)
#  @cdo.chainCall("setname,#{rho} -divc,#{C_R} -div",in: [presFile,tempFile].join(' '), out: densityFile)
#
#  # For debugging, it is helpfull, to avoid the automatic cleanup at the end of the scripts:
#  MyTempfile.setPersist(true)
#  # creates randomly names files. Switch on debugging with
#  @cdo.Debug = true
