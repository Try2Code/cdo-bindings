require 'pp'
require 'open3'

# Copyright (C) 2011-2012 Ralf Mueller, ralf.mueller@zmaw.de
# See COPYING file for copying and redistribution conditions.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# ==============================================================================
# CDO calling mechnism
module Cdo

  VERSION = "1.2.0"

  State = {
    :debug       => false,
    :returnCdf => false,
    :operators   => [],
    :forceOutput => true
  }
  State[:debug] = true unless ENV['DEBUG'].nil?

  @@CDO = ENV['CDO'].nil? ? 'cdo' : ENV['CDO']

  # Since cdo-1.5.4 undocumented operators are given with the -h option. For
  # earlier version, they have to be provided manually
  @@undocumentedOperators = %w[anomaly beta boxavg change_e5lsm change_e5mask
    change_e5slm chisquare chvar cloudlayer cmd com command complextorect
    covar0 covar0r daycount daylogs del29feb delday delete deltap deltap_fl
    delvar diffv divcoslat dumplogo dumplogs duplicate eca_r1mm enlargegrid
    ensrkhistspace ensrkhisttime eof3d eof3dspatial eof3dtime export_e5ml
    export_e5res fc2gp fc2sp fillmiss fisher fldcovar fldrms fourier fpressure
    gather gengrid geopotheight ggstat ggstats globavg gp2fc gradsdes
    gridverify harmonic hourcount hpressure import_e5ml import_e5res
    import_obs imtocomplex infos infov interpolate intgrid intgridbil
    intgridtraj intpoint isosurface lmavg lmean lmmean lmstd log lsmean
    meandiff2test mergegrid mod moncount monlogs mrotuv mrotuvb mulcoslat ncode
    ncopy nmltest normal nvar outputbounds outputboundscpt outputcenter
    outputcenter2 outputcentercpt outputkey outputtri outputvector outputvrml
    pardup parmul pinfo pinfov pressure_fl pressure_hl read_e5ml remapcon1
    remapdis1 retocomplex scalllogo scatter seascount select selgridname
    seloperator selvar selzaxisname setrcaname setvar showvar sinfov smemlogo
    snamelogo sort sortcode sortlevel sortname sorttaxis sorttimestamp sortvar
    sp2fc specinfo spectrum sperclogo splitvar stimelogo studentt template1
    template2 test test2 testdata thinout timcount timcovar tinfo transxy trms
    tstepcount vardes vardup varmul varquot2test varrms vertwind write_e5ml
    writegrid writerandom yearcount]

  @@outputOperatorsPattern = /(diff|info|output|griddes|zaxisdes|show|ncode|ndate|nlevel|nmon|nvar|nyear|ntime|npar|gradsdes|pardes)/

  private
  def Cdo.getOperators(force=false)
    # Do NOT compute anything, if it is not required
    return State[:operators] unless (State[:operators].empty? or force)
    cmd       = @@CDO + ' 2>&1'
    help      = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
    if 5 >= help.size
      warn "Operators could not get listed by running the CDO binary (#{@@CDO})"
      pp help if Cdo.debug
      exit
    end
    # in version 1.5.6 the output of '-h' has changed
    State[:operators] = case 
                        when Cdo.version < "1.5.6"
                          (help[help.index("Operators:")+1].split + @@undocumentedOperators).uniq
                        else
                          help[(help.index("Operators:")+1)..help.index(help.find {|v| v =~ /CDO version/}) - 2].join(' ').split
                        end
  end

  def Cdo.hasError(cmd,retvals)
    if (State[:debug])
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

  def Cdo.call(cmd)
    if (State[:debug])
      puts '# DEBUG ====================================================================='
      puts cmd
      puts '# DEBUG ====================================================================='
    end
    stdin, stdout, stderr, wait_thr = Open3.popen3(cmd)

    {
      :stdout => stdout.read,
      :stderr => stderr.read,
      :returncode => wait_thr.value.exitstatus
    }
  end
  def Cdo.run(cmd,ofile='',options='',returnCdf=false,force=nil,returnArray=nil,returnMaArray=nil)
    cmd = "#{@@CDO} -O #{options} #{cmd} "
    case ofile
    when $stdout
      retvals = Cdo.call(cmd)
      unless hasError(cmd,retvals)
        return retvals[:stdout].split($/).map {|l| l.chomp.strip}
      else
        raise ArgumentError,"CDO did NOT run successfully!"
      end
    else
      force = State[:forceOutput] if force.nil?
      if force or not File.exists?(ofile.to_s)
        ofile = MyTempfile.path if ofile.nil?
        cmd << "#{ofile}"
        retvals = call(cmd)
        if hasError(cmd,retvals)
          raise ArgumentError,"CDO did NOT run successfully!"
        end
      else
        warn "Use existing file '#{ofile}'" if Cdo.debug
      end
    end
    if not returnArray.nil?
      Cdo.readArray(ofile,returnArray)
    elsif not returnMaArray.nil?
      Cdo.readMaArray(ofile,returnMaArray)
    elsif returnCdf or State[:returnCdf]
      Cdo.readCdf(ofile)
    else
      return ofile
    end
  end
  def Cdo.parseArgs(args)
    # splitinto hash-like args and the rest
    operatorArgs = args.reject {|a| a.class == Hash}
    opts = operatorArgs.empty? ? '' : ',' + operatorArgs.join(',')
    io   = args.find {|a| a.class == Hash}
    io   = {} if io.nil?
    args.delete_if   {|a| a.class == Hash}
    return [io,opts]
  end
  def Cdo.method_missing(sym, *args, &block)
    ## args is expected to look like [opt1,...,optN,:input => iStream,:output => oStream] where
    # iStream could be another CDO call (timmax(selname(Temp,U,V,ifile.nc))
    puts "Operator #{sym.to_s} is called" if State[:debug]
    if getOperators.include?(sym.to_s)
      io,opts = Cdo.parseArgs(args)
      if @@outputOperatorsPattern.match(sym)
        run(" -#{sym.to_s}#{opts} #{io[:input]} ",$stdout)
      else
        run(" -#{sym.to_s}#{opts} #{io[:input]} ",io[:output],io[:options],io[:returnCdf],io[:force],io[:returnArray],io[:returnMaArray])
      end
    else
      raise ArgumentError,"Operator #{sym.to_s} not found"
    end
  end
  def Cdo.loadCdf
    begin
      require "numru/netcdf_miss"
      include NumRu
    rescue LoadError
      warn "Could not load ruby's netcdf bindings. Please install it."
      raise
    end
  end

  public
  def Cdo.debug=(value)
    State[:debug] = value
  end
  def Cdo.debug
    State[:debug]
  end
  def Cdo.forceOutput=(value)
    State[:forceOutput] = value
  end
  def Cdo.forceOutput
    State[:forceOutput]
  end
  def Cdo.version
    cmd     = @@CDO + ' 2>&1'
    help    = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
    regexp  = %r{CDO version (\d.*), Copyright}
    line    = help.find {|v| v =~ regexp}
    version = regexp.match(line)[1]
  end
  def Cdo.setReturnCdf(value=true)
    if value
      Cdo.loadCdf
    end
    State[:returnCdf] = value
  end
  def Cdo.unsetReturnCdf
    setReturnCdf(false)
  end
  def Cdo.returnCdf
    State[:returnCdf]
  end

  def Cdo.hasCdo?(bin=@@CDO)
    return true if File.exists?(@@CDO) and File.executable?(@@CDO)
    ENV['PATH'].split(File::PATH_SEPARATOR).each {|path| 
      return true if File.exists?([path,bin].join(File::SEPARATOR))
    }
  end

  # test if @@CDO can be used
  def Cdo.checkCdo
    unless hasCdo?(@@CDO)
      warn "Testing application #@@CDO is not available!"
      exit 1
    else
      puts "Using CDO: #@@CDO"
      puts IO.popen(@@CDO + " -V").readlines
    end
    return true
  end
  def Cdo.setCdo(cdo)
    puts "Will use #{cdo} instead of #@@CDO" if Cdo.debug
    @@CDO = cdo
    Cdo.getOperators(true)
  end
  def Cdo.getCdo
    @@CDO
  end
  def Cdo.operators
    Cdo.getOperators if State[:operators].empty?
    State[:operators]
  end

  #==================================================================
  # Addional operotors:
  #------------------------------------------------------------------
  def Cdo.boundaryLevels(args)
    ilevels         = Cdo.showlevel(:input => args[:input])[0].split.map(&:to_f)
    bound_levels    = Array.new(ilevels.size+1)
    bound_levels[0] = 0
    (1..ilevels.size).each {|i| 
      bound_levels[i] =bound_levels[i-1] + 2*(ilevels[i-1]-bound_levels[i-1])
    }
    bound_levels
  end

  def Cdo.thicknessOfLevels(args)
    bound_levels = Cdo.boundaryLevels(args)
    delta_levels    = []
    bound_levels.each_with_index {|v,i| 
      next if 0 == i
      delta_levels << v - bound_levels[i-1]
    }
    delta_levels
  end

  def Cdo.readCdf(iFile)
    Cdo.loadCdf unless State[:returnCdf] 
    NetCDF.open(iFile)
  end

  def Cdo.readArray(iFile,varname)
    filehandle = Cdo.readCdf(iFile)
    if filehandle.var_names.include?(varname)
      # return the data array
      filehandle.var(varname).get
    else
      raise ArgumentError, "Cannot find variable '#{varname}'"
    end
  end

  def Cdo.readMaArray(iFile,varname)
    filehandle = Cdo.readCdf(iFile)
    if filehandle.var_names.include?(varname)
      # return the data array
      filehandle.var(varname).get_with_miss
    else
      raise ArgumentError,"Cannot find variable '#{varname}'"
    end
  end
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
end

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
