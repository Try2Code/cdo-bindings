$:.unshift File.join(File.dirname(__FILE__),"..","lib")
require 'cdo'

require 'minitest/autorun'


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
    @tempStore = CdoTempfileStore.new
  end

  def test_cdo
    assert_equal(true,@cdo.check)
    if ENV['CDO']
      assert_equal(ENV['CDO'],@cdo.cdo)
    else
      pp DEFAULT_CDO_PATH if @@debug
      pp @cdo.cdo if @@debug
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

  def test_hasCdo
    assert(@cdo.hasCdo)
    @cdo.cdo = 'cccccccc'
    assert_equal( false, @cdo.hasCdo)

    @cdo.cdo='/bin/cdo'
    assert(@cdo.hasCdo) if File.exist?(@cdo.cdo)
  end
  def test_getOperators
    pp @cdo.operators
    %w[seq random stdatm info showlevel sinfo remap geopotheight mask topo thicknessOfLevels].each {|op|
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

  def test_verifyGridOP
    if Cdo.version("1.9.5") >= @cdo.version then
      assert(@cdo.operators.keys.include?('gridverify'))
    else
      assert(@cdo.operators.keys.include?('verifygrid'))
    end
  end

  def test_ifNoOutfileOperator
    noOutputOperators = @cdo.getNoOutputOperators
    %w[verifygrid showlevel].each {|operator|
      assert(noOutputOperators.include?(operator))
      output = @cdo.send(operator.to_sym, input: '-topo')
    }
  end
  def test_outputOperators
    @cdo.debug = @@debug
    levels = @cdo.showlevel(:input => "-stdatm,0")
    assert_equal([0,0].map(&:to_s),levels)

    info = @cdo.sinfo(:input => "-stdatm,0")
    assert_equal("GRIB",info[0].split(':').last.strip)

    values = @cdo.outputkey("value",:input => "-stdatm,0")
    assert_equal(["1013.25", "288"],values[-2..-1])
    values = @cdo.outputkey("value",:input => "-stdatm,0,10000")
    assert_equal(
      ["1013.25", "271.9125", "288", "240.591"].map(&:to_f).map {|f| f.round(1)}.map(&:to_s),
      values[-4..-1].map(&:to_f).map {|f| f.round(1)}.map(&:to_s))
    values = @cdo.outputkey("lev",:input => "-stdatm,0,10000")
    assert_equal(["0", "10000","0", "10000"],values[-4..-1])
  end
  def test_CDO_version
    assert(Cdo.version('1.4.3') < @cdo.version,"Version too low: #{@cdo.version}")
    assert(Cdo.version('1.6.3') < @cdo.version,"Version too low: #{@cdo.version}")
    assert(Cdo.version('3.0') > @cdo.version,"Version too high: #{@cdo.version}")
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
    @cdo.debug=@@debug
    targetLevels = [0,10,50,100,200,400,1000]
    levels = @cdo.showlevel(:input => " -stdatm,#{targetLevels.join(',')}")
    [0,1].each {|i| assert_equal(targetLevels.join(' '),levels[i])}
    names = @cdo.showname(:input => "-stdatm,0",:options => "-f nc")
    assert_equal(["P T"],names)
  end
  def test_chain
    @cdo.debug = @@debug
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
    sleep(1)
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

  def test_stdout_operators
    sourceLevels = %W{25 100 250 500 875 1400 2100 3000 4000 5000}
    assert_equal(sourceLevels,
                 @cdo.showlevel(:input => "-selname,T #{@cdo.stdatm(*sourceLevels,:options => '-f nc')}")[0].split)

   # test autoSplit usage
   levels = @cdo.showlevel(input: "-stdatm,0,10,20",autoSplit: ' ')
   assert_equal([['0','10','20'],['0','10','20']],levels)
   assert_equal(sourceLevels,
                @cdo.showlevel(:input => "-selname,T #{@cdo.stdatm(*sourceLevels,:options => '-f nc')}",
                               :autoSplit => ' '))

   timesExpected = ['2001-01-01T12:00:00',
                    '2001-01-01T13:00:00',
                    '2001-01-01T14:00:00',
                    '2001-01-01T15:00:00',
                    '2001-01-01T16:00:00',
                    '2001-01-01T17:00:00',
                    '2001-01-01T18:00:00',
                    '2001-01-01T19:00:00',
                    '2001-01-01T20:00:00',
                    '2001-01-01T21:00:00']
   assert_equal(timesExpected,
                    @cdo.showtimestamp(input: "-settaxis,2001-01-01,12:00,1hour -for,1,10", autoSplit: '  '))

   assert_equal(['P T'],@cdo.showname(input: "-stdatm,0"))
   assert_equal(['P','T'],@cdo.showname(input: "-stdatm,0",autoSplit: ' '))
  end

  def test_verifygrid_output
    return if @cdo.version < Cdo.version('1.9.0')
    actualOutput = @cdo.verifygrid(input: '-topo,r2x2')
    if @cdo.version < Cdo.version('2.0.0') then
      assert_empty(actualOutput)
    else
      expectedVerifyOutput = [
        "cdo    verifygrid: Grid consists of 4 (2x2) cells (type: lonlat), of which",
        "cdo    verifygrid:         4 cells have 4 vertices",
        "cdo    verifygrid:         4 cells have duplicate vertices",
        "cdo    verifygrid:         2 cells have their vertices arranged in a clockwise order",
        "cdo    verifygrid:        lon : 0 to 180 degrees",
        "cdo    verifygrid:        lat : -45 to 45 degrees",
      ]
      actualOutput = @cdo.verifygrid(input: '-topo,r2x2')
      pp actualOutput if @@debug
      expectedVerifyOutput.each {|line| assert(actualOutput.include?(line),"'#{line}' is missing in output") }
    end
  end

  def test_verticalLevels
    @cdo.debug = @@debug
    targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
    sourceLevels = %W{25 100 250 500 875 1400 2100 3000 4000 5000}
    thicknesses = @cdo.thicknessOfLevels(:input => "-selname,T #{@cdo.stdatm(*sourceLevels,:options => '-f nc')}")
    assert_equal(targetThicknesses,thicknesses)
  end

  def test_parseArgs
    io,opts = Cdo.parseArgs([1,2,3,:input => '1',:output => '2',:force => true,:returnCdf => true,:autoSplit => '  '])
    assert_equal("1",io[:input])
    assert_equal("2",io[:output])
    assert_equal(true,io[:force])
    assert_equal(true,io[:returnCdf])
    assert_equal("  ",io[:autoSplit])
    pp [io,opts]
  end

  def test_errorException
    @cdo.debug = @@debug
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

  def test_features
    assert_equal(true,@cdo.has_srv)
    assert_equal(true,@cdo.has_ieg)
    assert_equal(true,@cdo.has_ext)
  end

  def test_noOutputOps
    operators = @cdo.operators
    %w[griddes griddes2 info infoc infon infop infos infov map
       outputarr outputbounds outputboundscpt outputcenter outputcenter2
       outputcentercpt outputext outputf outputfld outputint outputkey outputsrv
       outputtab outputtri outputts outputvector outputvrml outputxyz partab verifygrid verifyweights].each {|op|
      assert(operators.include?(op),"Operator '#{op}' cannot be found!")
      assert_equal(0,operators[op],"Operator '#{op}' has a non-zero output counter!")
    }
    # just a rought estimation
    opsCounf = @cdo.operators.select {|_,c| 0 == c}.size
    assert(opsCounf > 50)
    assert(opsCounf < 200)
  end

  def test_output_set_to_nil
    assert_equal(String,@cdo.topo(:output => nil).class)
    assert_equal("File format: GRIB".tr(' ',''),@cdo.sinfov(:input => "-topo", :output => nil)[0].tr(' ',''))
  end

  def test_splitOps
    pattern = 'stdAtm'
    resultsFiles = @cdo.splitname(input: '-stdatm,0',output: pattern)
    assert_equal(2,resultsFiles.size)
    %w[T P].each {|var|
      assert(resultsFiles.include?("#{pattern}#{var}.grb"))
    }

    pattern = 'sel'
    resultsFiles = @cdo.splitsel(1,input: '-for,0,9',output: pattern)
    assert_equal(10,resultsFiles.size)
    (1...10).each {|var|
      assert(resultsFiles.include?("#{pattern}00000#{var}.grb"))
    }

    pattern = 'lev'
    resultsFiles = @cdo.splitlevel(input: '-stdatm,100,2000,5000',output: pattern)
    assert_equal(3,resultsFiles.size)
    %w[0100 2000 5000].each {|var|
      assert(resultsFiles.include?("#{pattern}00#{var}.grb"))
    }
  end

  def test_seqVSfor
    if @cdo.version < Cdo.version('1.9.7') then
      @cdo.for(0,1)
    else
      @cdo.seq(0,1)
    end

  end
  def test_operators_with_multiple_output_files
    varname = ( @cdo.version < Cdo.version('1.9.7') ) ? 'for' : 'seq'
    assert_equal(1,@cdo.operators['topo'],'wrong output counter for "topo"')
    assert_equal(0,@cdo.operators['sinfo'],'wrong output counter for "sinfo"')
    assert_equal(0,@cdo.operators['ngridpoints'],'wrong output counter for "sinfo"') if @cdo.version > Cdo.version('1.6.4')

    assert_equal(-1,@cdo.operators['splitsel'],'wrong output counter for "splitsel"')
    assert_equal(2,@cdo.operators['trend'],'wrong output counter for "trend"')
    # create input for eof
    #
    # check automatic generation ot two tempfiles
    aFile, bFile = @cdo.trend(input: "-addc,7 -mulc,44 -#{varname},1,100")
    assert_equal(51.0,@cdo.outputkey('value',input: aFile)[-1].to_f)
    assert_equal(44.0,@cdo.outputkey('value',input: bFile)[-1].to_f)
    # check usage of 'returnCdf' with these operators
    aFile, bFile = @cdo.trend(input: "-addc,7 -mulc,44 -#{varname},1,100",returnCdf: true)
    assert_equal(51.0, aFile.var(varname).get.flatten[0],"got wrong value from cdf handle")
    assert_equal(44.0, bFile.var(varname).get.flatten[0],"got wrong value from cdf handle")

    avar = @cdo.trend(input: "-addc,7 -mulc,44 -#{varname},1,100",returnArray: varname).flatten[0]
    assert_equal(51.0, avar,"got wrong value from narray")
  end
  def test_tempdir
    # manual set path
    tag = 'tempRb'
    tempPath = Dir.pwd+'/'+tag
    pp Dir.glob("#{tempPath}/*")
    pp Dir.glob("#{tempPath}/*").size
    assert_equal(0,Dir.glob("#{tempPath}/*").size)
    cdo = Cdo.new(tempdir: tempPath)
    cdo.topo('r10x10',options: '-f nc')
    assert_equal(1,Dir.glob("#{tempPath}/*").size)
    cdo.topo('r10x10',options: '-f nc')
    cdo.topo('r10x10',options: '-f nc')
    assert_equal(3,Dir.glob("#{tempPath}/*").size)
    cdo.topo('r10x10',options: '-f nc')
    cdo.topo('r10x10',options: '-f nc')
    assert_equal(5,Dir.glob("#{tempPath}/*").size)
    cdo.cleanTempDir
    assert_equal(0,Dir.glob("#{tempPath}/*").size)
  end

  def test_returnArray
    if @cdo.hasNetcdf then
      temperature = @cdo.stdatm(0,:returnCdf => true).var('T').get.flatten[0]
      assert(1.7 < temperature,"Temperature to low!")
      assert_raises ArgumentError do
        @cdo.stdatm(0,:returnArray => 'TT')
      end
      temperature = @cdo.stdatm(0,:returnArray => 'T')
      assert_equal(288.0,temperature.flatten[0])
      pressure = @cdo.stdatm(0,1000,:options => '-b F64',:returnArray => 'P')
      assert_equal("1013.25 898.54",pressure.flatten.to_a.map {|v| v.round(2)}.join(' '))
    else
      assert_raises LoadError do
        temperature = @cdo.stdatm(0,:returnCdf => true).var('T').get.flatten[0]
      end
    end
  end
  def test_returnMaArray
    if @cdo.hasNetcdf then
      @cdo.debug = @@debug
      topo = @cdo.topo(:returnMaArray => 'topo')
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
    else
      assert_raises LoadError do
        topo = @cdo.topo(:returnMaArray => 'topo')
      end
    end
  end

  def test_returnCdf
    ofile = rand(0xfffff).to_s + '_test_returnCdf.nc'
    vals = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
    assert_equal(ofile,vals)
    if @cdo.hasNetcdf then
      vals = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:returnCdf => true)
      assert_equal(["lon","lat","level","P","T"],vals.var_names)
      assert_equal(276,vals.var("T").get.flatten.mean.floor)
      vals = @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:output => ofile,:options => "-f nc")
      assert_equal(ofile,vals)
    end
    FileUtils.rm(ofile)
  end
  def test_simple_returnCdf
    if @cdo.hasNetcdf then
      ofile0, ofile1 = @tempStore.newFile, @tempStore.newFile
      sum = @cdo.fldsum(:input => @cdo.stdatm(0,:options => "-f nc"),
                        :returnCdf => true).var("P").get
      assert_equal(1013.25,sum.min)
      sum = @cdo.fldsum(:input => @cdo.stdatm(0,:options => "-f nc"),:output => ofile0)
      assert_equal(ofile0,sum)
      test_returnCdf
    else
      puts "test_simple_returnCdf is disabled because of missing ruby-netcdf"
    end
  end
  def test_readCdf
    varname = ( @cdo.version < Cdo.version('1.9.7') ) ? 'for' : 'seq'
    input = "-settunits,days  -setyear,2000 -#{varname},1,4"
    cdfFile = @cdo.copy(:options =>"-f nc",:input=>input)
    if @cdo.hasNetcdf then
      cdf = @cdo.readCdf(cdfFile)
      assert_empty(['lon','lat',varname,'time'] - cdf.var_names)
    else
      assert_raises LoadError do
        cdf = @cdo.readCdf(cdfFile)
      end
    end
  end
  def test_combine
    ofile0, ofile1 = @tempStore.newFile, @tempStore.newFile
    @cdo.fldsum(:input => @cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,:options => "-f nc"),:output => ofile0)
    @cdo.fldsum(:input => "-stdatm,25,100,250,500,875,1400,2100,3000,4000,5000",:options => "-f nc",:output => ofile1)
    @tempStore.showFiles
    if @cdo.hasNetcdf then
      diff = @cdo.sub(:returnCdf => true, :input => [ofile0,ofile1].join(' ')).var('T').get
      assert_equal(0.0,diff.min)
      assert_equal(0.0,diff.max)
    end
  end
  def test_readArray
    if @cdo.hasNetcdf then
      @cdo.debug = @@debug
      assert_equal([40,80],@cdo.readArray(@cdo.sellonlatbox(-10,10,-20,20,:input => '-topo',:options => '-f nc'), 'topo').shape)
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
    @cdo = Cdo.new(returnNilOnError: true)
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
  def test_proj
    myTempfile=@tempStore.newFile
    File.open(myTempfile,'w') {|f|
    f << '
gridtype = projection
xsize     = 10
ysize     = 10
xunits   = "meter"
yunits   = "meter"
xfirst    = -638000
xinc      = 100
yfirst    = -3349350
yinc      = 100
grid_mapping = crs
grid_mapping_name = polar_stereographic
proj_params = "+proj=stere +lon_0=-45 +lat_ts=70 +lat_0=90 +x_0=0 +y_0=0"
'
    }
    data = @cdo.remapnn(myTempfile,input: '-topo',returnArray: 'topo', options: '-f nc')
    assert_equal(-3190.0,data.flatten[0])
  end

  if @@maintainermode  then
    require 'unifiedPlot'

    def test_system_tempdir
      # automatic path
      tempPath = Dir.tmpdir
      tag = 'Cdorb'
      pattern = "#{tempPath}/#{tag}*"
      cdo = Cdo.new
      pp Dir.glob(pattern) if @@debug
      assert_equal(0,Dir.glob(pattern).size)
      cdo.topo('r10x10')
      assert_equal(1,Dir.glob(pattern).size)
      cdo.topo('r10x10')
      cdo.topo('r10x10',options: '-f nc')
      assert_equal(3,Dir.glob(pattern).size)
      cdo.topo('r10x10',options: '-f nc')
      cdo.topo('r10x10',options: '-f nc')
      cdo.topo('r10x10',options: '-f nc')
      cdo.topo('r10x10')
      cdo.topo('r10x10',options: '-f nc')
      cdo.topo('r10x10',options: '-f nc')
      cdo.topo('r10x10',options: '-f nc')
      cdo.topo('r10x10')
      cdo.topo('r10x10',options: '-f nc')
      pp Dir.glob(pattern) if @@debug
      assert_equal(12,Dir.glob(pattern).size)
      cdo.cleanTempDir()
      assert_equal(0,Dir.glob(pattern).size)
    end
    def test_longChain
      ifile = "-enlarge,global_0.3 -settaxis,2000-01-01 -expr,'t=sin(seq*3.141529/180.0)' -seq,1,10"
      t = @cdo.fldmax(input: "-div -sub -timmean -seltimestep,2,3 #{ifile} -seltimestep,1 #{ifile}  -gridarea #{ifile}",returnArray: "t")
      assert_equal(8.981299259858133e-09,t[0])
    end
    def test_tempfile
      ofile0, ofile1 = @tempStore.newFile, @tempStore.newFile
      assert(ofile0 != ofile1, "Found equal tempfiles!")
      # Tempfile should not disappeare even if the GC was started
      puts ofile0
      assert(File.exist?(ofile0))
      GC.start
      assert(File.exist?(ofile0))
    end
    def test_selIndexListFromIcon
      input = "~/data/icon/oce.nc"
    end
    def test_readArray
      @cdo.debug = @@debug
      assert_equal([40,80],@cdo.readArray(@cdo.sellonlatbox(-10,10,-20,20,:input => '-topo',:options => '-f nc'), 'topo').shape)
    end
    def test_doc
      @cdo.debug = @@debug
      @cdo.help(:remap)
      @cdo.help(:infov)
      @cdo.help(:topo)
      @cdo.help(:notDefinedOP)
      @cdo.help
    end
    def test_fillmiss
      rand = @cdo.setname('v',
                          :input => '-random,r1x10 ',
                          :options => ' -f nc')

      if @cdo.hasNetcdf then
        @cdo.debug = @@debug
        cdf  = @cdo.openCdf(rand)
        vals = cdf.var('v').get
        cdf.var('v').put(vals.sort)
        cdf.sync
        cdf.close
      else
        assert_raises LoadError do
          cdf  = @cdo.openCdf(rand)
        end
      end

      if @cdo.hasNetcdf then
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
        rm([rand])
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
        rm([rand])
      end
    end

    # opendap test - broken since 1.9.0
    def test_opendap
      ifile = 'https://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/cpc_global_precip/precip.1979.nc'
      @cdo.sinfov(input: ifile)
    end if @@debug

    def test_ydiv
      @cdo.debug = true

      if @cdo.operators.include?('yeardiv')

        input='-settaxis,2001-01-01,12:00:00,12hours -for,1,10000'

        opChain = "-expr,'seq=seq*cyear()/seq;' -settaxis,2001-01-01,12:00:00,12hours -for,1,10000 -yearmean -expr,'seq=seq*cyear()/seq;' -settaxis,2001-01-01,12:00:00,12hours -for,1,10000"

        values = @cdo.yeardiv(input: opChain, returnArray: 'seq').flatten
        assert(Array.new(values.size,1.0),values.to_a)
      else
        puts "no tests for 'yeardiv' because operator is missing"
      end
    end
    # input operator does not work straight forward. the input needs to be set as output
    def test_input_chain
      @cdo.debug = true
      gridfile  = '/home/ram/Downloads/gridfile.txt'
      inputfile = '/home/ram/Downloads/tmax.txt'
      @cdo.settaxis('1979-01-01,00:12:00,1days',
                    :options => ' -r -f nc',
                    input: "-setname,tmax -setctomiss,-999.99 -input,#{gridfile} tmax.nc < ", output: inputfile)
    end
  end
end
