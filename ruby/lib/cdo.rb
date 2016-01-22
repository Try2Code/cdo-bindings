require 'pp'
require 'open3'
require 'logger'
require 'stringio'

class Cdo
  OutputOperatorsPattern = /(diff|info|output|griddes|zaxisdes|show|ncode|ndate|nlevel|nmon|nvar|nyear|ntime|npar|gradsdes|pardes)/

  attr_accessor :cdo, :returnCdf, :forceOutput, :env, :debug, :logging, :logFile
  attr_reader   :operators, :filetypes

  def initialize(cdo: 'cdo',
                 returnCdf: false,
                 returnFalseOnError: false,
                 forceOutput: true,
                 env: {},
                 logging: false,
                 logFile: StringIO.new,
                 debug: false,
                 returnNilOnError: false)

    # setup path to cdo executable
    @cdo = ENV.has_key?('CDO') ? ENV['CDO'] : cdo

    @operators              = getOperators(binary=@cdo)
    @returnCdf              = returnCdf
    @forceOutput            = forceOutput
    @env                    = env
    @debug                  = ENV.has_key?('DEBUG') ? true : debug
    @returnNilOnError       = returnNilOnError

    @filetypes              = getFiletypes
    @returnFalseOnError     = returnFalseOnError

    @logging                = logging
    @logFile                = logFile
    @logger                 = Logger.new(@logFile,'a')
    @logger.level           = Logger::INFO
  end

  private # {{{

  # split arguments into hash-like args and the rest
  def Cdo.parseArgs(args)
    operatorArgs = args.reject {|a| a.class == Hash}
    opts = operatorArgs.empty? ? '' : ',' + operatorArgs.join(',')
    io   = args.find {|a| a.class == Hash}
    io   = {} if io.nil?
    args.delete_if   {|a| a.class == Hash}
    # join input streams together if possible
    io[:input] = io[:input].join(' ') if io[:input].respond_to?(:join)

    return [io,opts]
  end

  # collect the complete list of possible operators
  def getOperators(path2cdo)
    if version <= '1.7.0' then
      cmd       = path2cdo + ' 2>&1'
      help      = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
      if 5 >= help.size
        warn "Operators could not get listed by running the CDO binary (#{path2cdo})"
        pp help if @debug
        exit
      end

      @operators = help[(help.index("Operators:")+1)..help.index(help.find {|v| v =~ /CDO version/}) - 2].join(' ').split
    else
      cmd = "#{path2cdo} --operators"

      @operators = IO.popen(cmd).readlines.map {|l| l.split(' ').first }
    end
  end

  # get supported IO filetypes form the binary
  def getFiletypes
    _, _, stderr, _ = Open3.popen3(@cdo + " -V")
    supported       = stderr.readlines.map(&:chomp)

    supported.grep(/(Filetypes)/)[0].split(':')[1].split.map(&:downcase)
  end


  # Execute the given cdo call and return all outputs
  def _call(cmd)
    if (@debug)
      puts '# DEBUG ====================================================================='
      pp @env unless @env.empty?
      puts 'CMD: '
      puts cmd
      puts '# DEBUG ====================================================================='
    end

    @logger.info(cmd+"\n") if @logging

    stdin, stdout, stderr, wait_thr = Open3.popen3(@env,cmd)
    {
      :stdout     => stdout.read,
      :stderr     => stderr.read,
      :returncode => wait_thr.value.exitstatus
    }
  end

  # Error handling for the given command
  def _hasError(cmd,retvals)
    if @debug
      puts("RETURNCODE: #{retvals[:returncode]}")
    end
    if ( 0 != retvals[:returncode] )
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
  def _run(cmd,ofile='',options=nil,returnCdf=false,force=nil,returnArray=nil,returnMaArray=nil)
    options = options.to_s

    options << '-f nc' if options.empty? and ( \
                                              (     returnCdf ) or \
                                              ( not returnArray.nil? ) or \
                                              ( not returnMaArray.nil?) \
                                             )
    cmd = "#{@cdo} -O #{options} #{cmd} "

    case ofile
    when $stdout
      retvals = _call(cmd)
      unless _hasError(cmd,retvals)
        return retvals[:stdout].split($/).map {|l| l.chomp.strip}
      else
        if @returnNilOnError then
          return nil
        else
          raise ArgumentError,"CDO did NOT run successfully!"
        end
      end
    else
      force = @forceOutput if force.nil?
      if force or not File.exists?(ofile.to_s)
        ofile = MyTempfile.path if ofile.nil?
        cmd << "#{ofile}"
        retvals = _call(cmd)
        if _hasError(cmd,retvals)
          if @returnNilOnError then
            return nil
          else
            raise ArgumentError,"CDO did NOT run successfully!"
          end
        end
      else
        warn "Use existing file '#{ofile}'" if @debug
      end
    end

    if not returnArray.nil?
      readArray(ofile,returnArray)
    elsif not returnMaArray.nil?
      readMaArray(ofile,returnMaArray)
    elsif returnCdf or @returnCdf
      readCdf(ofile)
    else
      ofile
    end
  end

  # Implementation of operator calls using ruby's meta programming skills
  #
  # args is expected to look like
  #   [opt1,...,optN,:input => iStream,:output => oStream, :options => ' ']
  #   where iStream could be another CDO call (timmax(selname(Temp,U,V,ifile.nc))
  def method_missing(sym, *args, &block)
    puts "Operator #{sym.to_s} is called" if @debug

    if @operators.include?(sym.to_s)
      io, opts = Cdo.parseArgs(args)
      if OutputOperatorsPattern.match(sym.to_s)
        _run(" -#{sym.to_s}#{opts} #{io[:input]} ",$stdout)
      else
        _run(" -#{sym.to_s}#{opts} #{io[:input]} ",io[:output],io[:options],io[:returnCdf],io[:force],io[:returnArray],io[:returnMaArray])
      end
    else
      return false if @returnFalseOnError
      raise ArgumentError,"Operator #{sym.to_s} not found"
    end
  end

  # load the netcdf bindings
  def loadCdf
    begin
      require "numru/netcdf_miss"
    rescue LoadError
      warn "Could not load ruby's netcdf bindings. Please install it."
      raise
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

  # check if cdo backend is working
  def check
    return false unless system("#@cdo -h 1>/dev/null 2>&1")

    retval = _call("#{@cdo} -V")
    pp retval if @debug

    return true
  end

  def version
    IO.popen("#{@cdo} -V 2>&1").readlines.first.split(/version/i).last.strip.split(' ').first
  end

  # return cdf handle to given file readonly
  def readCdf(iFile)
    loadCdf
    NumRu::NetCDF.open(iFile)
  end

  # return cdf handle opened in append more
  def openCdf(iFile)
    loadCdf
    NumRu::NetCDF.open(iFile,'r+')
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
# Helper module for easy temp file handling
module MyTempfile
  require 'tempfile'
  @@_tempfiles           = []
  @@persistent_tempfiles = false
  @@N                    = 10000000

  def MyTempfile.setPersist(value)
    @@persistent_tempfiles = value
  end

  def MyTempfile.path
    unless @@persistent_tempfiles
      t = Tempfile.new(self.class.to_s)
      @@_tempfiles << t
      @@_tempfiles << t.path
      t.path
    else
      t = "_"+rand(@@N).to_s
      @@_tempfiles << t
      t
    end
  end

  def MyTempfile.showFiles
    @@_tempfiles.each {|f| print(f+" ") if f.kind_of? String}
  end
end

#vim:fdm=marker
