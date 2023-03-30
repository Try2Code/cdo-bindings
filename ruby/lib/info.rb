require 'semverse'
require 'json'
module CdoInfo
  # hardcoded fallback list of output operators - from 1.8.0 there is an
  # options for this: --operators_no_output
  # this list works for cdo-1.6.4
  NoOutputOperators = %w[cdiread cmor codetab conv_cmor_table diff diffc diffn
  diffp diffv dump_cmor_table dumpmap filedes gmtcells gmtxyz gradsdes griddes
  griddes2 gridverify info infoc infon infop infos infov map ncode ndate
  ngridpoints ngrids nlevel nmon npar ntime nvar nyear output outputarr
  outputbounds outputboundscpt outputcenter outputcenter2 outputcentercpt
  outputext outputf outputfld outputint outputkey outputsrv outputtab outputtri
  outputts outputvector outputvrml outputxyz pardes partab partab2 seinfo
  seinfoc seinfon seinfop showattribute showatts showattsglob showattsvar
  showcode showdate showformat showgrid showlevel showltype showmon showname
  showparam showstdname showtime showtimestamp showunit showvar showyear sinfo
  sinfoc sinfon sinfop sinfov spartab specinfo tinfo vardes vct vct2 verifygrid
  vlist xinfon zaxisdes]
  TwoOutputOperators = %w[trend samplegridicon mrotuv eoftime
  eofspatial eof3dtime eof3dspatial eof3d eof complextorect complextopol]
  MoreOutputOperators = %w[distgrid eofcoeff eofcoeff3d intyear scatter splitcode
  splitday splitgrid splithour splitlevel splitmon splitname splitparam splitrec
  splitseas splitsel splittabnum splitvar splityear splityearmon splitzaxis]
  def CdoInfo.version(executable)
    info = IO.popen(executable+' -V 2>&1').readlines.first
    info.split(' ').grep(%r{\d+\.\d+.*})[0].to_s
  end
  " get the CDO version "
  def CdoInfo.semversion(executable)
    Semverse::Version.new(CdoInfo.version(executable))
  end

  " get supported filetypes of the binary and other configuration data"
  def CdoInfo.config(executable)
    config = {}
    config.default(false)

    if Semverse::Version.new('1.9.3') < CdoInfo.semversion(executable) then
      config.merge!(JSON.parse(IO.popen(executable + " --config all").read.chomp))
      config.each {|k,v| config[k] = ('yes' == v) ? true : false}
    else
      warn "Cannot check configuration of the binary!"
      warn "Please check manually with '#{executable} -V'"
    end
    config
  end

  " get an infentory for the operators provided by the executable "
  def CdoInfo.operators(executable) #{{{
    operators = {}

    version = CdoInfo.semversion(executable)

    # little side note: the option --operators_no_output works in 1.8.0 and
    # 1.8.2, but not in 1.9.0, from 1.9.1 it works again
    case
    when version < Semverse::Version.new('1.7.2') then
      cmd       = executable + ' 2>&1'
      help      = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
      if 5 >= help.size
        warn "Operators could not get listed by running the CDO binary (#{executable})"
        pp help if @debug
        exit
      end

      _operators = help[(help.index("Operators:")+1)..help.index(help.find {|v|
        v =~ /CDO version/
      }) - 2].join(' ').split

      # build up operator inventory
      # default is 1 output stream
      _operators.each {|op| operators[op] = 1 }
      operators.each {|op,_|
        operators[op] = 0  if NoOutputOperators.include?(op)
        operators[op] = 2  if TwoOutputOperators.include?(op)
        operators[op] = -1 if MoreOutputOperators.include?(op)
      }

    when (version < Semverse::Version.new('1.8.0')  or Semverse::Version.new('1.9.0') == version) then
      cmd                = "#{executable} --operators"
      _operators         = IO.popen(cmd).readlines.map {|l| l.split(' ').first }

      _operators.each {|op| operators[op] = 1 }
      operators.each {|op,_|
        operators[op] = 0  if NoOutputOperators.include?(op)
        operators[op] = 2  if TwoOutputOperators.include?(op)
        operators[op] = -1 if MoreOutputOperators.include?(op)
      }


    when version < Semverse::Version.new('1.9.3') then
      cmd                = "#{executable} --operators"
      _operators         = IO.popen(cmd).readlines.map {|l| l.split(' ').first }
      cmd                = "#{executable} --operators_no_output"
      _operatorsNoOutput = IO.popen(cmd).readlines.map {|l| l.split(' ').first }

      # build up operator inventory
      _operators.each {|op| operators[op] = 1 }
      _operatorsNoOutput.each {|op| operators[op] = 0}
      operators.each {|op,_|
        operators[op] = 0  if _operatorsNoOutput.include?(op)
        operators[op] = 2  if TwoOutputOperators.include?(op)
        operators[op] = -1 if MoreOutputOperators.include?(op)
      }

    else
      cmd       = "#{executable} --operators"
      operators = {}
      IO.popen(cmd).readlines.map {|line|
        lineContent        = line.chomp.split(' ')
        name               = lineContent[0]
        iCounter, oCounter = lineContent[-1][1..-1].split('|')
        operators[name]    = oCounter.to_i
      }
    end
    return operators
  end
end
