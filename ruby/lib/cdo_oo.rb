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

CDF_MOD_SCIPY   = "scipy"
CDF_MOD_NETCDF4 = "netcdf4"
CDO_PY_VERSION  = "1.2.6"

class CDOException <<  Exception

   #def __init__(self, stdout, stderr, returncode):
   #    super(CDOException, self).__init__()
   #    self.stdout     = stdout
   #    self.stderr     = stderr
   #    self.returncode = returncode
   #    self.msg        = '(returncode:%s) %s' % (returncode, stderr)

end

class Cdo

  attr_accessor :returnCdf, :forceOutput, :env, :debug

  def initialize( returnCdf: false,
#                 returnNoneOnError: false,
                  forceOutput: true,
                  cdfMod: CDF_MOD_NETCDF4,
                  env: {},
                  debug: false) 
    #
    # Since cdo-1.5.4 undocumented operators are given with the -h option. For
    # earlier version, they have to be provided manually
    @undocumentedOperators = ['anomaly','beta','boxavg','change_e5lsm','change_e5mask',
        'change_e5slm','chisquare','chvar','cloudlayer','cmd','com','command','complextorect',
        'covar0','covar0r','daycount','daylogs','del29feb','delday','delete','deltap','deltap_fl',
        'delvar','diffv','divcoslat','dumplogo','dumplogs','duplicate','eca_r1mm','enlargegrid',
        'ensrkhistspace','ensrkhisttime','eof3d','eof3dspatial','eof3dtime','export_e5ml',
        'export_e5res','fc2gp','fc2sp','fillmiss','fisher','fldcovar','fldrms','fourier','fpressure',
        'gather','gengrid','geopotheight','ggstat','ggstats','globavg','gp2fc','gradsdes',
        'gridverify','harmonic','hourcount','hpressure','ifs2icon','import_e5ml','import_e5res',
        'import_obs','imtocomplex','infos','infov','interpolate','intgrid','intgridbil',
        'intgridtraj','intpoint','isosurface','lmavg','lmean','lmmean','lmstd','log','lsmean',
        'meandiff2test','mergegrid','mod','moncount','monlogs','mrotuv','mrotuvb','mulcoslat','ncode',
        'ncopy','nmltest','normal','nvar','outputbounds','outputboundscpt','outputcenter',
        'outputcenter2','outputcentercpt','outputkey','outputtri','outputvector','outputvrml',
        'pardup','parmul','pinfo','pinfov','pressure_fl','pressure_hl','read_e5ml','remapcon1',
        'remapdis1','retocomplex','scalllogo','scatter','seascount','select','selgridname',
        'seloperator','selvar','selzaxisname','setrcaname','setvar','showvar','sinfov','smemlogo',
        'snamelogo','sort','sortcode','sortlevel','sortname','sorttaxis','sorttimestamp','sortvar',
        'sp2fc','specinfo','spectrum','sperclogo','splitvar','stimelogo','studentt','template1',
        'template2','test','test2','testdata','thinout','timcount','timcovar','tinfo','transxy','trms',
        'tstepcount','vardes','vardup','varmul','varquot2test','varrms','vertwind','write_e5ml',
        'writegrid','writerandom','yearcount']

    @CDO = ENV.has_key?('CDO') ? ENV['CDO'] : 'cdo'

    @operators              = getOperators()
    @returnCdf              = returnCdf
    @returnNoneOnError      = returnNoneOnError
    @tempfile               = MyTempfile()
    @forceOutput            = forceOutput
    @cdfMod                 = cdfMod.lower()
    @env                    = env
    @debug                  = ENV.has_key?('DEBUG') ? true : debug
    @outputOperatorsPattern = '(diff|info|output|griddes|zaxisdes|show|ncode|ndate|nlevel|nmon|nvar|nyear|ntime|npar|gradsdes|pardes)'

    @libs        = getSupportedLibs()

    private:

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

    def Cdo.getOperators(force=false)
      # Do NOT compute anything, if it is not required
      return @operators unless (@operators.empty? or force)
      cmd       = @CDO + ' 2>&1'
      help      = IO.popen(cmd).readlines.map {|l| l.chomp.lstrip}
      if 5 >= help.size
        warn "Operators could not get listed by running the CDO binary (#{@CDO})"
        pp help if @debug
        exit
      end
      # in version 1.5.6 the output of '-h' has changed
      State[:operators] = case 
                          when Cdo.version < "1.5.6"
                            (help[help.index("Operators:")+1].split + @undocumentedOperators).uniq
                          else
                            help[(help.index("Operators:")+1)..help.index(help.find {|v| v =~ /CDO version/}) - 2].join(' ').split
                          end
    end

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

    def Cdo.parseArgs(args)
      # splitinto hash-like args and the rest
      operatorArgs = args.reject {|a| a.class == Hash}
      opts = operatorArgs.empty? ? '' : ',' + operatorArgs.join(',')
      io   = args.find {|a| a.class == Hash}
      io   = {} if io.nil?
      args.delete_if   {|a| a.class == Hash}
      # join input streams together if possible
      io[:input] = io[:input].join(' ') if io[:input].respond_to?(:join)
      return [io,opts]
    end

    def Cdo.method_missing(sym, *args, &block)
      ## args is expected to look like [opt1,...,optN,:input => iStream,:output => oStream] where
      # iStream could be another CDO call (timmax(selname(Temp,U,V,ifile.nc))
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


  def Cdo.loadCdf
    begin
      require "numru/netcdf_miss"
      include NumRu
    rescue LoadError
      warn "Could not load ruby's netcdf bindings. Please install it."
      raise
    end
  end

  def Cdo.getSupportedLibs(force=false)
    return unless (State[:libs].nil? or force)
    _, _, stderr, _ = Open3.popen3(@@CDO + " -V")
    supported       = stderr.readlines.map(&:chomp)
    with            = supported.grep(/(with|Features)/)[0].split(':')[1].split.map(&:downcase)
    libs            = supported.grep(/library version/).map {|l| 
      l.strip.split(':').map {|l| 
        l.split.first.downcase
      }[0,2]
    }
    State[:libs] = {}
    with.flatten.each {|k| State[:libs][k]=true}
    libs.each {|lib,version| State[:libs][lib] = version}
  end

  def setReturnArray(self,value=True):
    self.returnCdf = value


  def unsetReturnArray(self):
    self.setReturnArray(False)

  def hasCdo(self,path=None):
    if path is None:
      path = self.CDO

    if os.path.isfile(path) and os.access(path, os.X_OK):
      return True
    return False

  def checkCdo(self):
    if (self.hasCdo()):
      call = [self.CDO,' -V']
      proc = subprocess.Popen(' '.join(call),
          shell  = True,
          stderr = subprocess.PIPE,
          stdout = subprocess.PIPE)
      retvals = proc.communicate()
      print(retvals)

  def setCdo(self,value):
    self.CDO       = value
    self.operators = self.getOperators()

  def getCdo(self):
    return self.CDO

  def hasLib(self,lib):
    return (lib in self.libs.keys())

  def libsVersion(self,lib):
    if not self.hasLib(lib):
      raise AttributeError("Cdo does NOT have support for '#{lib}'")
    else:
      if True != self.libs[lib]:
        return self.libs[lib]
      else:
        print("No version information available about '" + lib + "'")
        return False

  #==================================================================
  # Addional operators:
  #------------------------------------------------------------------
  def version(self):
    # return CDO's version
    proc = subprocess.Popen([self.CDO,'-h'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
    ret  = proc.communicate()
    cdo_help   = ret[1].decode("utf-8")
    match = re.search("CDO version (\d.*), Copyright",cdo_help)
    return match.group(1)

  def boundaryLevels(self,**kwargs):
    ilevels         = list(map(float,self.showlevel(input = kwargs['input'])[0].split()))
    bound_levels    = []
    bound_levels.insert(0,0)
    for i in range(1,len(ilevels)+1):
      bound_levels.insert(i,bound_levels[i-1] + 2*(ilevels[i-1]-bound_levels[i-1]))

    return bound_levels

  def thicknessOfLevels(self,**kwargs):
    bound_levels = self.boundaryLevels(**kwargs)
    delta_levels    = []
    for i in range(0,len(bound_levels)):
      v = bound_levels[i]
      if 0 == i:
        continue

      delta_levels.append(v - bound_levels[i-1])

    return delta_levels

  def readCdf(self,iFile):
    """Return a cdf handle created by the available cdf library. python-netcdf4 and scipy suported (default:scipy)"""
    try:
        fileObj =  self.cdf(iFile, mode='r')
    except:
      print("Could not import data from file '%s'" % iFile)
      raise
    else:
        return fileObj

  def openCdf(self,iFile):
    """Return a cdf handle created by the available cdf library. python-netcdf4 and scipy suported (default:netcdf4)"""
    try:
      fileObj =  self.cdf(iFile, mode='r+')
    except:
      print("Could not import data from file '%s'" % iFile)
      raise
    else:
        return fileObj

  def readArray(self,iFile,varname):
    """Direcly return a numpy array for a given variable name"""
    filehandle = self.readCdf(iFile)
    try:
      # return the data array
      return filehandle.variables[varname][:].copy()
    except KeyError:
      print("Cannot find variable '%s'" % varname)
      return False

  def readMaArray(self,iFile,varname):
    """Create a masked array based on cdf's FillValue"""
    fileObj =  self.readCdf(iFile)

    #.data is not backwards compatible to old scipy versions, [:] is
    data = fileObj.variables[varname][:].copy()

    # load numpy if available
    try:
      import numpy as np
    except:
      raise ImportError("numpy is required to return masked arrays.")

    if hasattr(fileObj.variables[varname],'_FillValue'):
      #return masked array
      retval = np.ma.array(data,mask=data == fileObj.variables[varname]._FillValue)
    else:
      #generate dummy mask which is always valid
      retval = np.ma.array(data,mask=data != data )

    return retval

  def __version__(self):
    return CDO_PY_VERSION
# Helper module for easy temp file handling
class MyTempfile(object):

  __tempfiles = []

  def __init__(self):
    self.persistent_tempfile = False

  def __del__(self):
    # remove temporary files
    for filename in self.__class__.__tempfiles:
      if os.path.isfile(filename):
        os.remove(filename)

  def setPersist(self,value):
    self.persistent_tempfiles = value

  def path(self):
    if not self.persistent_tempfile:
      t = tempfile.NamedTemporaryFile(delete=True,prefix='cdoPy')
      self.__class__.__tempfiles.append(t.name)
      t.close()

      return t.name
    else:
      N =10000000 
      t = "_"+random.randint(N).__str__()
