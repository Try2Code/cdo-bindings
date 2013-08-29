import os,re,subprocess,tempfile,random,string

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

def auto_doc(tool, cdo_self):
    """Generate the __doc__ string of the decorated function by calling the cdo help command"""
    def desc(func):
        func.__doc__ = cdo_self.call([cdo_self.CDO, '-h', tool]).get('stdout')
        return func
    return desc

class CDOException(Exception):

    def __init__(self, stdout, stderr, returncode):
        super(CDOException, self).__init__()
        self.stdout     = stdout
        self.stderr     = stderr
        self.returncode = returncode
        self.msg        = '(returncode:%s) %s' % (returncode, stderr)

    def __str__(self):
        return self.msg

class Cdo(object):

  def __init__(self):
    # Since cdo-1.5.4 undocumented operators are given with the -h option. For
    # earlier version, they have to be provided manually
    self.undocumentedOperators = ['anomaly','beta','boxavg','change_e5lsm','change_e5mask',
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

    if os.environ.has_key('CDO'):
      self.CDO = os.environ['CDO']
    else:
      self.CDO = 'cdo'

    self.operators   = self.getOperators()
    self.returnCdf   = False
    self.returnNoneOnError = False
    self.tempfile    = MyTempfile()
    self.forceOutput = True
    self.debug       = False
    self.outputOperatorsPattern = '(diff|info|output|griddes|zaxisdes|show|ncode|ndate|nlevel|nmon|nvar|nyear|ntime|npar|gradsdes|pardes)'

    self.cdfMod      = ''
    self.libs        = self.getSupportedLibs()

  def __dir__(self):
    res = dir(type(self)) + list(self.__dict__.keys())
    res.extend(self.operators)
    return res

  def call(self,cmd):
    if self.debug:
      print '# DEBUG ====================================================================='
      print 'CALL:'+' '.join(cmd)
      print '# DEBUG ====================================================================='

    proc = subprocess.Popen(' '.join(cmd),
        shell  = True,
        stderr = subprocess.PIPE,
        stdout = subprocess.PIPE)
    retvals = proc.communicate()
    return {"stdout"     : retvals[0]
           ,"stderr"     : retvals[1]
           ,"returncode" : proc.returncode}

  def hasError(self,method_name,cmd,retvals):
    if (self.debug):
      print("RETURNCODE:"+retvals["returncode"].__str__())
    if ( 0 != retvals["returncode"] ):
      print("Error in calling operator " + method_name + " with:")
      print(">>> "+' '.join(cmd)+"<<<")
      print(retvals["stderr"])
      return True
    else:
      return False

  def __getattr__(self, method_name):

    @auto_doc(method_name, self)
    def get(self, *args,**kwargs):
      operator          = [method_name]
      operatorPrintsOut = re.search(self.outputOperatorsPattern,method_name)

      if args.__len__() != 0:
        for arg in args:
          operator.append(arg.__str__())

      #build the cdo command
      #1. the cdo command
      cmd = [self.CDO]
      #2. options
      if 'options' in kwargs:
          cmd += kwargs['options'].split()
      #3. operator(s)
      cmd.append(','.join(operator))
      #4. input files or operators
      if 'input' in kwargs:
        if isinstance(kwargs["input"], basestring):
            cmd.append(kwargs["input"])
        else:
            #we assume it's either a list, a tuple or any iterable.
            cmd += kwargs["input"]

      if not kwargs.__contains__("force"):
        kwargs["force"] = self.forceOutput

      if operatorPrintsOut:
        retvals = self.call(cmd)
        if ( not self.hasError(method_name,cmd,retvals) ):
          r = map(string.strip,retvals["stdout"].split(os.linesep))
          return r[:len(r)-1]
        else:
          if self.returnNoneOnError:
            return None
          else:
            raise CDOException(**retvals)
      else:
        if kwargs["force"] or \
           (kwargs.__contains__("output") and not os.path.isfile(kwargs["output"])):
          if not kwargs.__contains__("output") or None == kwargs["output"]:
            kwargs["output"] = self.tempfile.path()

          cmd.append(kwargs["output"])

          retvals = self.call(cmd)
          if self.hasError(method_name,cmd,retvals):
            if self.returnNoneOnError:
              return None
            else:
              raise CDOException(**retvals)
        else:
          if self.debug:
            print("Use existing file'"+kwargs["output"]+"'")

      if not kwargs.__contains__("returnCdf"):
        kwargs["returnCdf"] = False

      if not None == kwargs.get("returnArray"):
        return self.readArray(kwargs["output"],kwargs["returnArray"])
      elif not None == kwargs.get("returnMaArray"):
        return self.readMaArray(kwargs["output"],kwargs["returnMaArray"])
      elif self.returnCdf or kwargs["returnCdf"]:
        if not self.returnCdf:
          self.loadCdf()
        return self.readCdf(kwargs["output"])
      else:
        return kwargs["output"]

    if ((method_name in self.__dict__) or (method_name in self.operators)):
      if self.debug:
        print("Found method:" + method_name)

      #cache the method for later
      setattr(self.__class__, method_name, get)
      return get.__get__(self)
    else:
      # If the method isn't in our dictionary, act normal.
      print("#=====================================================")
      print("Cannot find method:" + method_name)
      raise AttributeError, "Unknown method '" + method_name +"'!"

  def getOperators(self):
    import os
    proc = subprocess.Popen([self.CDO,'-h'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
    ret  = proc.communicate()
    l    = ret[1].find("Operators:")
    ops  = ret[1][l:-1].split(os.linesep)[1:-1]
    endI = ops.index('')
    s    = ' '.join(ops[:endI]).strip()
    s    = re.sub("\s+" , " ", s)
    return list(set(s.split(" ") + self.undocumentedOperators))

  def loadCdf(self):
    try:
      import scipy.io.netcdf as cdf
      self.cdf    = cdf
      self.cdfMod = "scipy"
    except:
      try:
        import netCDF4 as cdf
        self.cdf    = cdf
        self.cdfMod = "netcdf4"
      except:
        raise ImportError,"scipy or python-netcdf4 module is required to return numpy arrays."

  def getSupportedLibs(self,force=False):
    proc = subprocess.Popen('cdo -V',
        shell  = True,
        stderr = subprocess.PIPE,
        stdout = subprocess.PIPE)
    retvals = proc.communicate()

    withs     = re.findall('with: (.*)',retvals[1])[0].split(' ')
    libs      = re.findall('(\w+) library version : (\d+\.\d+\.\d+)',retvals[1])
    libraries = dict({})
    for w in withs:
      libraries[w.lower()] = True

    for lib in libs:
      l,v = lib
      libraries[l.lower()] = v

    return libraries

  def setReturnArray(self,value=True):
    self.returnCdf = value
    if value:
      self.loadCdf()


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
      print retvals

  def setCdo(self,value):
    self.CDO       = value
    self.operators = self.getOperators()

  def getCdo(self):
    return self.CDO

  def hasLib(self,lib):
    return lib in self.libs
    return false

  def libsVersion(self,lib):
    if not self.hasLib(lib):
      raise AttributeError, "Cdo does NOT have support for '#{lib}'"
    else:
      if True != self.libs[lib]:
        return self.libs[lib]
      else:
        print "No version information available about '" + lib + "'"
        return False

  #==================================================================
  # Addional operators:
  #------------------------------------------------------------------
  def module_version(self):
    '1.2.1'

  def version(self):
    # return CDO's version
    proc = subprocess.Popen([self.CDO,'-h'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
    ret  = proc.communicate()
    cdo_help   = ret[1]
    match = re.search("CDO version (\d.*), Copyright",cdo_help)
    return match.group(1)

  def boundaryLevels(self,**kwargs):
    ilevels         = map(float,self.showlevel(input = kwargs['input'])[0].split())
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
    if not self.returnCdf:
      self.loadCdf()

    if ( "scipy" == self.cdfMod):
      #making it compatible to older scipy versions
      fileObj =  self.cdf.netcdf_file(iFile, mode='r')
    elif ( "netcdf4" == self.cdfMod ):
      fileObj = self.cdf.Dataset(iFile)
    else:
      raise ImportError,"Could not import data from file '" + iFile + "'"

    retval = fileObj
    fileObj.close()
    return retval

  def readArray(self,iFile,varname):
    """Direcly return a numpy array for a given variable name"""
    filehandle = self.readCdf(iFile)
    if varname in filehandle.variables:
      # return the data array
      return filehandle.variables[varname][:]
    else:
      print "Cannot find variable '" + varname +"'"
      return False

  def readMaArray(self,iFile,varname):
    """Create a masked array based on cdf's FillValue"""
    fileObj =  self.readCdf(iFile)

    #.data is not backwards compatible to old scipy versions, [:] is
    data = fileObj.variables[varname][:]

    # load numpy if available
    try:
      import numpy as np
    except:
      raise ImportError,"numpy is required to return masked arrays."

    if hasattr(fileObj.variables[varname],'_FillValue'):
      #return masked array
      retval = np.ma.array(data,mask=data == fileObj.variables[varname]._FillValue)
    else:
      #generate dummy mask which is always valid
      retval = np.ma.array(data,mask=data != data )

    return retval

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
