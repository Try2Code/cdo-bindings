require 'pp'
require 'open3'
require 'logger'
require 'stringio'
require 'json'
require 'tempfile'

class Hash
  alias :include? :has_key?
end

# Copyright 2011-2019 Ralf Mueller, ralf.mueller@dkrz.de
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

class Cdo

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


  attr_accessor :cdo, :returnCdf, :forceOutput, :env, :debug, :logging, :logFile
  attr_reader   :operators, :filetypes, :hasNetcdf

  def initialize(cdo: 'cdo',
                 returnFalseOnError: false,
                 returnNilOnError: false,
                 forceOutput: true,
                 env: {},
                 debug: false,
                 tempdir: Dir.tmpdir,
                 logging: false,
                 logFile: StringIO.new)

    # setup path to cdo executable
    @cdo = ENV.has_key?('CDO') ? ENV['CDO'] : cdo

    @operators              = getOperators(@cdo)
    @noOutputOperators      = @operators.select {|op,io| 0 == io}.keys

    @hasNetcdf              = loadOptionalLibs

    @forceOutput            = forceOutput
    @env                    = env
    @debug                  = ENV.has_key?('DEBUG') ? true : debug
    @returnNilOnError       = returnNilOnError
    @returnFalseOnError     = returnFalseOnError

    @tempStore              = CdoTempfileStore.new(tempdir)
    @logging                = logging
    @logFile                = logFile
    @logger                 = Logger.new(@logFile,'daily')
    @logger.level           = Logger::INFO

    @config                 = getFeatures

    # create methods to descibe what can be done with the binary
    @config.each {|k,v|
      self.class.send :define_method, k.tr('-','_') do
        v
      end
    }

    # ignore return code 1 for diff operators (from 1.9.6 onwards)
    @exit_success = lambda {|operatorName|
      return 0 if version < '1.9.6'
      return 0 if 'diff' != operatorName[0,4]
      return 1
    }
  end

  private # {{{

  # split arguments into hash-like args and the rest
  def Cdo.parseArgs(args)
    operatorArgs = args.reject {|a| a.class == Hash}
    opArguments = operatorArgs.empty? ? '' : ',' + operatorArgs.join(',')
    io   = args.find {|a| a.class == Hash}
    io   = {} if io.nil?
    #args.delete_if   {|a| a.class == Hash}
    # join input streams together if possible
    io[:input] = io[:input].join(' ') if io[:input].respond_to?(:join)

    return [io,opArguments]
  end

  # collect the complete list of possible operators
  def getOperators(path2cdo) #{{{
    operators = {}

    # little side note: the option --operators_no_output works in 1.8.0 and
    # 1.8.2, but not in 1.9.0, from 1.9.1 it works again
    case
    when version < '1.7.2' then
      cmd       = path2cdo + ' 2>&1'
      help      = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
      if 5 >= help.size
        warn "Operators could not get listed by running the CDO binary (#{path2cdo})"
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

    when (version < '1.8.0'  or '1.9.0' == version) then
      cmd                = "#{path2cdo} --operators"
      _operators         = IO.popen(cmd).readlines.map {|l| l.split(' ').first }

      _operators.each {|op| operators[op] = 1 }
      operators.each {|op,_|
        operators[op] = 0  if NoOutputOperators.include?(op)
        operators[op] = 2  if TwoOutputOperators.include?(op)
        operators[op] = -1 if MoreOutputOperators.include?(op)
      }


    when version < '1.9.3' then

      cmd                = "#{path2cdo} --operators"
      _operators         = IO.popen(cmd).readlines.map {|l| l.split(' ').first }
      cmd                = "#{path2cdo} --operators_no_output"
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
      cmd       = "#{path2cdo} --operators"
      operators = {}
      IO.popen(cmd).readlines.map {|line|
        lineContent        = line.chomp.split(' ')
        name               = lineContent[0]
        iCounter, oCounter = lineContent[-1][1..-1].split('|')
        operators[name]    = oCounter.to_i
      }
    end
    return operators
  end #}}}

  # get meta-data about the CDO installation
  def getFeatures
    config = {}
    config.default(false)

    if version > '1.9.3' then
      config.merge!(JSON.parse(IO.popen(@cdo + " --config all").read.chomp))
      config.each {|k,v| config[k] = ('yes' == v) ? true : false}
    else
      _, _, stderr, _ = Open3.popen3(@cdo + " -V")
      supported       = stderr.readlines.map(&:chomp)

      supported.grep(/(Filetypes)/)[0].split(':')[1].split.map(&:downcase).each {|ftype|
        config["has-#{ftype}"] = true
      }
    end
    config
  end

  # Execute the given cdo call and return all outputs
  def _call(cmd,env={})
    @logger.info(cmd+"\n") if @logging

    stdin, stdout, stderr, wait_thr = Open3.popen3(@env.merge(env),cmd)
    status = {
      :stdout     => stdout.read,
      :stderr     => stderr.read,
      :returncode => wait_thr.value
    }


    # popen3 does not catch exitcode in case of an abort (128+SIGABRT=134)
    st = -1
    st = status[:returncode].exitstatus if not status[:returncode].exitstatus.nil?
    st = 128 + status[:returncode].termsig if (status[:returncode].signaled? and (status[:returncode].termsig != 0))
    status[:returncode] = st


    if (@debug)
      puts '# DEBUG - start ============================================================='
      pp @env unless @env.empty?
      pp  env unless  env.empty?
      puts 'CALL:' + cmd
      puts 'STDOUT:'
      puts status[:stdout] unless status[:stdout].strip.empty?
      puts 'STDERR:'
      puts status[:stderr] unless status[:stderr].strip.empty?
      puts '# DEBUG - end ==============================================================='
    end

    status
  end

  # Error handling for the given command
  def _hasError(cmd,operatorName,retvals)
    if @debug
      puts("RETURNCODE: #{retvals[:returncode]}")
    end
    if ( @exit_success[operatorName] < retvals[:returncode] )
      puts("Error in calling:")
      puts(">>> "+cmd+"<<<")
      puts(retvals[:stderr])
      @logger.error("FAILIURE in execution of:"+cmd+"| msg:"+retvals[:stderr]) if @logging
      return true
    else
      return false
    end
  end

  # command execution wrapper, which handles the possible return types
  def _run(operatorName,
           operatorParameters,
           input:         nil,
           output:        nil,
           options:       '',
           returnCdf:     false,
           force:         nil,
           returnArray:   nil,
           returnMaArray: nil,
           env:           nil,
           autoSplit:     nil)

    # switch netcdf output if data of filehandles are requested as output
    options << ' -f nc' if ( \
                             (     returnCdf ) or \
                             ( not returnArray.nil? ) or \
                             ( not returnMaArray.nil?) \
                           )

    # setup basic operator execution command
    cmd = "#{@cdo} -O #{options} -#{operatorName}#{operatorParameters} #{input} "

    # use an empty hash for non-given environment
    env = {} if env.nil?

    # list of all output streams
    outputs = []

    # just collect given output(s)
    outputs << output unless output.nil?

    case output
    when $stdout
      retvals = _call(cmd,env)
      unless _hasError(cmd,operatorName,retvals)
        _output = retvals[:stdout].split($/).map {|l| l.chomp.strip}
        unless autoSplit.nil?
          _output.map! {|line| line.split(autoSplit)}
          _output = _output[0] if 1 == _output.size
        end
        return _output
      else
        if @returnNilOnError then
          return nil
        else
          raise ArgumentError,"CDO did NOT run successfully!"
        end
      end
    else
      # if operators was not called with output-forcing given, take the global switch
      force = @forceOutput if force.nil?

      if force or not File.exists?(output.to_s)
        # create tempfile(s) according to the number of output streams needed
        # if output argument is missing
        if output.nil? then
          operators[operatorName].times { outputs << @tempStore.newFile}
        end

        #finalize the execution command
        cmd << "#{outputs.join(' ')}"

        retvals = _call(cmd,env)

        if _hasError(cmd,operatorName,retvals)
          if @returnNilOnError then
            return nil
          else
            raise ArgumentError,"CDO did NOT run successfully!"
          end
        end
      else
        warn "Use existing file(s) '#{outputs.join(' ')}'" if @debug
      end
    end

    # return data arrays instead - this is for now limitted to fields of the
    # first output file. number from the second need only one addition line, so
    # I think this is sufficient
    if not returnArray.nil?
      readArray(outputs[0],returnArray)
    elsif not returnMaArray.nil?
      readMaArray(outputs[0],returnMaArray)
    elsif returnCdf
      retval = outputs.map{|f| readCdf(f)}
      return 1 == retval.size ? retval[0] : retval
    elsif /^split/.match(operatorName)
      Dir.glob("#{output}*")
    else
      return outputs[0] if outputs.size == 1
      return outputs
    end
  end

  # Implementation of operator calls using ruby's meta programming skills
  #
  # args is expected to look like
  #   [opt1,...,optN,:input => iStream,:output => oStream, :options => ' ']
  #   where iStream could be another CDO call (timmax(selname(Temp,U,V,ifile.nc))
  def method_missing(sym, *args, &block)
    operatorName = sym.to_s
    puts "Operator #{operatorName} is called" if @debug

    # exit eary on missing operator
    unless @operators.include?(operatorName)
      return false if @returnFalseOnError
      raise ArgumentError,"Operator #{operatorName} not found"
    end

    io, operatorParameters = Cdo.parseArgs(args)

    # mark calls for operators without output files
    io[:output] = $stdout if @noOutputOperators.include?(operatorName)

    _run(operatorName,operatorParameters,**io)
  end

  # load the netcdf bindings
  def loadOptionalLibs
    begin
      require "numru/netcdf_miss"
      return true
    rescue
      warn "Could not load ruby's netcdf bindings"
      return false
    end
  end

  # }}}

  public  # {{{

  # show Cdo's built-in help for given operator
  def help(operator=nil)
    if operator.nil?
      puts _call([@cdo,'-h'].join(' '))[:stderr]
    else
      operator = operator.to_s
      puts _call([@cdo,'-h',operator].join(' ')).values_at(:stdout,:stderr)
    end
  end

  # collect logging messages
  def collectLogs
    if @logger.instance_variable_get(:'@logdev').filename.nil?
      @logFile.rewind
      return @logFile.read
    else
      return File.open(@logFile).readlines
    end
  end

  # print the loggin messaged
  def showLog
    puts collectLogs
  end

  # check if the CDO binary is present and works
  def hasCdo(path=@cdo)
    executable = system("#{path} -V >/dev/null 2>&1")
    fullpath   = File.exists?(path) and File.executable?(path)

    return (executable or fullpath)
  end

  # check if cdo backend is working
  def check
    return false unless hasCdo

    retval = _call("#{@cdo} -V")
    pp retval if @debug

    return true
  end

  # return CDO version string
  def version(verbose=false)
    info = IO.popen("#{@cdo} -V 2>&1").readlines
    if verbose then
      return info.join
    else
      return info.first.split(/version/i).last.strip.split(' ').first
    end
  end

  # return cdf handle to given file readonly
  def readCdf(iFile,mode='r')
    if @hasNetcdf then
      NumRu::NetCDF.open(iFile,mode)
    else
      raise LoadError,"Could not load ruby-netcdf"
    end
  end

  # return cdf handle opened in append more
  def openCdf(iFile)
    readCdf(iFile,'r+')
  end

  # return narray for given variable name
  def readArray(iFile,varname)
    filehandle = readCdf(iFile)
    if filehandle.var_names.include?(varname)
      # return the data array
      filehandle.var(varname).get
    else
      raise ArgumentError, "Cannot find variable '#{varname}'"
    end
  end

  # return a masked array for given variable name
  def readMaArray(iFile,varname)
    filehandle = readCdf(iFile)
    if filehandle.var_names.include?(varname)
      # return the data array
      filehandle.var(varname).get_with_miss
    else
      raise ArgumentError,"Cannot find variable '#{varname}'"
    end
  end

  # remove tempfiles created from this or previous runs
  def cleanTempDir
    @tempStore.cleanTempDir
  end
  # }}}

  # Addional operators: {{{

  # compute vertical boundary levels from full levels
  def boundaryLevels(args)
    ilevels         = self.showlevel(:input => args[:input])[0].split.map(&:to_f)
    bound_levels    = Array.new(ilevels.size+1)
    bound_levels[0] = 0
    (1..ilevels.size).each {|i|
      bound_levels[i] =bound_levels[i-1] + 2*(ilevels[i-1]-bound_levels[i-1])
    }
    bound_levels
  end

  # compute level thicknesses from given full levels
  def thicknessOfLevels(args)
    bound_levels = self.boundaryLevels(args)
    delta_levels    = []
    bound_levels.each_with_index {|v,i|
      next if 0 == i
      delta_levels << v - bound_levels[i-1]
    }
    delta_levels
  end

  # }}}

end
#
# Helper module for easy temp file handling {{{
class CdoTempfileStore
  # base for persitent temp files - just for debugging
  N = 10000000

  def initialize(dir=Dir.tmpdir)
    @dir                  = dir
    @tag                  = 'Cdorb'
    @persistent_tempfiles = false

    # storage for filenames in order to prevent too early removement
    @_tempfiles           = []

    # make sure the tempdir ie really there
    Dir.mkdir(@dir) unless Dir.exists?(@dir)
  end

  def setPersist(value)
    @persistent_tempfiles = value
  end

  def newFile
    unless @persistent_tempfiles
      t = Tempfile.new(@tag,@dir)
      @_tempfiles << t
      @_tempfiles << t.path
      t.path
    else
      t = "_"+rand(N).to_s
      @_tempfiles << t
      t
    end
  end

  def showFiles
    @_tempfiles.each {|f| print(f+" ") if f.kind_of? String}
  end

  def cleanTempDir
    # filter by name, realfile and ownership
    Dir.entries(@dir).map {|f| "#@dir/#{f}"}.find_all {|file|
      File.file?(file) and File.owned?(file) and file.include?(@tag)
    }.each {|f| File.unlink(f)}
  end
end #}}}

# vim: fdm=marker
