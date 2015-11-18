require 'pp'
require 'fileutils'

class Cdo
  OutputOperatorsPattern = '(diff|info|output|griddes|zaxisdes|show|ncode|ndate|nlevel|nmon|nvar|nyear|ntime|npar|gradsdes|pardes)'

  attr_accessor :cdo, :returnCdf, :forceOutput, :env, :debug
  attr_reader   :operators

  def initalize(cdo: 'cdo', 
                returnCdf: false,
                returnFalseOnError: false,
                forceOutput: true,
                env: {},
                debug: false) 

    # setup path to cdo executable
    @cdo = ENV.has_key?('CDO') ? ENV['CDO'] : cdo

    @operators              = Cdo.getOperators(true)
    @returnCdf              = returnCdf
    @forceOutput            = forceOutput
    @env                    = env
    @debug                  = ENV.has_key?('DEBUG') ? true : debug

    @libs                   = getSupportedLibs()
    @returnFalseOnError     = returnFalseOnError
    @tempfile               = MyTempfile()

  end

  #============================================================================
  private

  # collect the complete list of possible operators
  def Cdo.getOperators(force=false)
    # Do NOT compute anything, if it is not required
    return @operators unless ((@operators ||= []).empty? or force)

    cmd       = @cdo + ' 2>&1'
    help      = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
    if 5 >= help.size
      warn "Operators could not get listed by running the CDO binary (#{@cdo})"
      pp help if @debug
      exit
    end

    @operators = help[(help.index("Operators:")+1)..help.index(help.find {|v| v =~ /CDO version/}) - 2].join(' ').split
  end
  # Execute the given cdo call and return all outputs
  def Cdo.call(cmd)
    if (State[:debug])
      puts '# DEBUG ====================================================================='
      pp Cdo.env unless Cdo.env.empty?
      puts 'CMD: '
      puts cmd
      puts '# DEBUG ====================================================================='
    end
    stdin, stdout, stderr, wait_thr = Open3.popen3(Cdo.env,cmd)

    {
      :stdout     => stdout.read,
      :stderr     => stderr.read,
      :returncode => wait_thr.value.exitstatus
    }
  end

  # Error handling for the given command
  def Cdo.hasError(cmd,retvals)
    if @debug
      puts("RETURNCODE: #{retvals[:returncode]}")
    end
    if ( 0 != retvals[:returncode] )
      puts("Error in calling:")
      puts(">>> "+cmd+"<<<")
      puts(retvals[:stderr])
      return true
    else
      return false
    end
  end

  # command execution wrapper, which handles the possible return types
  def Cdo.run(cmd,ofile='',options='',returnCdf=false,force=nil,returnArray=nil,returnMaArray=nil)
    cmd = "#{@CDO} -O #{options} #{cmd} "
    case ofile
    when $stdout
      retvals = Cdo.call(cmd)
      @logger.info(cmd+"\n") if @log
      unless Cdo.hasError(cmd,retvals)
        return retvals[:stdout].split($/).map {|l| l.chomp.strip}
      else
        raise ArgumentError,"CDO did NOT run successfully!"
      end
    else
      force = @forceOutput if force.nil?
      if force or not File.exists?(ofile.to_s)
        ofile = MyTempfile.path if ofile.nil?
        cmd << "#{ofile}"
        retvals = Cdo.call(cmd)
        @logger.info(cmd+"\n") if @log
        if Cdo.hasError(cmd,retvals)
          raise ArgumentError,"CDO did NOT run successfully!"
        end
      else
        warn "Use existing file '#{ofile}'" if @debug
      end
    end
    if not returnArray.nil?
      Cdo.readArray(ofile,returnArray)
    elsif not returnMaArray.nil?
      Cdo.readMaArray(ofile,returnMaArray)
    elsif returnCdf or @returnCdf
      Cdo.readCdf(ofile)
    else
      return ofile
    end
  end

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

  # Implementation of operator calls using ruby's meta programming skills
  #
  # args is expected to look like
  #   [opt1,...,optN,:input => iStream,:output => oStream, :options => ' ']
  #   where iStream could be another CDO call (timmax(selname(Temp,U,V,ifile.nc))
  def method_missing(sym, *args, &block)
    puts "Operator #{sym.to_s} is called" if @debug

    if getOperators.include?(sym.to_s)
      io, opts = Cdo.parseArgs(args)
      if @@outputOperatorsPattern.match(sym)
        run(" -#{sym.to_s}#{opts} #{io[:input]} ",$stdout)
      else
        run(" -#{sym.to_s}#{opts} #{io[:input]} ",io[:output],io[:options],io[:returnCdf],io[:force],io[:returnArray],io[:returnMaArray])
      end
    else
      raise ArgumentError,"Operator #{sym.to_s} not found"
    end
  end

  # load the netcdf bindings
  def loadCdf
    begin
      require "numru/netcdf_miss"
      include NumRu
    rescue LoadError
      warn "Could not load ruby's netcdf bindings. Please install it."
      raise
    end
  end

  def getSupportedLibs(force=false)
    return unless (@libs.nil? or force)
    _, _, stderr, _ = Open3.popen3(@CDO + " -V")
    supported       = stderr.readlines.map(&:chomp)
    with            = supported.grep(/(with|Features)/)[0].split(':')[1].split.map(&:downcase)
    libs            = supported.grep(/library version/).map {|l| 
      l.strip.split(':').map {|l| 
        l.split.first.downcase
      }[0,2]
    }
    @libs = {}
    with.flatten.each {|k| @libs[k]=true}
    libs.each {|lib,version| @libs[lib] = version}
  end

  #============================================================================
  public

  # Public Class Methods {{{
  def Cdo.help(operator=nil)
    if operator.nil?
      puts Cdo.call([@@CDO,'-h'].join(' '))[:stderr]
    else
      operator = operator.to_s unless String == operator.class
      if Cdo.operators.include?(operator)
        puts Cdo.call([@@CDO,'-h',operator].join(' '))[:stdout]
      else
        puts "Unknown operator #{operator}"
      end
    end
  end
  # }}}
  # Public Instance Methods {{{

  # check if cdo backend is working
  def check
    return false unless File.exists?(@cdo)
    return false unless File.executable?(@cdo)

    call = [self.CDO,' -V']
    proc = subprocess.Popen(' '.join(call),
                            shell  = True,
                            stderr = subprocess.PIPE,
                            stdout = subprocess.PIPE)
    retvals = proc.communicate()
    pp retvals if @debug

    return true
  end

  # return cdf handle to given file readonly
  def readCdf(iFile)
    loadCdf
    NetCDF.open(iFile)
  end

  # return cdf handle opened in append more
  def openCdf(iFile)
    loadCdf
    NetCDF.open(iFile,'r+')
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


  #==================================================================
  # Addional operotors: {{{
  #------------------------------------------------------------------
  def boundaryLevels(args)
    ilevels         = self.showlevel(:input => args[:input])[0].split.map(&:to_f)
    bound_levels    = Array.new(ilevels.size+1)
    bound_levels[0] = 0
    (1..ilevels.size).each {|i| 
      bound_levels[i] =bound_levels[i-1] + 2*(ilevels[i-1]-bound_levels[i-1])
    }
    bound_levels
  end

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

#vim fdm=marker
