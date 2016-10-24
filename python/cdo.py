from __future__ import print_function
import os,re,subprocess,tempfile,random,sys
from pkg_resources import parse_version
from io import StringIO
import logging as pyLog
try:
    from string import strip
except ImportError:
    strip = str.strip

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
CDO_PY_VERSION  = "1.3.0"

def auto_doc(tool, cdo_self):
    """Generate the __doc__ string of the decorated function by calling the cdo help command"""
    def desc(func):
        func.__doc__ = cdo_self.call([cdo_self.CDO, '-h', tool]).get('stdout')
        return func
    return desc

def getCdoVersion(path2cdo):
    proc = subprocess.Popen([path2cdo,'-V'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
    ret  = proc.communicate()
    cdo_help   = ret[1].decode("utf-8")
    match = re.search("Climate Data Operators version (\d.*) .*",cdo_help)
    return match.group(1)

def setupLogging(logFile):
    logger = pyLog.getLogger(__name__)
    logger.setLevel(pyLog.INFO)

    if isinstance(logFile,str):
        handler = pyLog.FileHandler(logFile)
    else:
        handler = pyLog.StreamHandler(stream=logFile)

    formatter = pyLog.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    return logger


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

  def __init__(self,
               returnCdf=False,
               returnNoneOnError=False,
               forceOutput=True,
               cdfMod=CDF_MOD_NETCDF4,
               env={},
               debug=False,
               logging=False,
               logFile=StringIO()):

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

    if 'CDO' in os.environ:
      self.CDO = os.environ['CDO']
    else:
      self.CDO = 'cdo'

    self.operators              = self.getOperators()
    self.returnCdf              = returnCdf
    self.returnNoneOnError      = returnNoneOnError
    self.tempfile               = MyTempfile()
    self.forceOutput            = forceOutput
    self.cdfMod                 = cdfMod.lower()
    self.env                    = env
    self.debug                  = True if 'DEBUG' in os.environ else debug
    self.outputOperators        = ['cdiread','cmor','codetab','conv_cmor_table','diff','diffc','diffn','diffp','diffv','dump_cmor_table','dumpmap','filedes','ggstat','ggstats','gmtcells','gmtxyz','gradsdes','griddes','griddes2','gridverify','info','infoc','infon','infop','infos','infov','map','ncode','ncode','ndate','ngridpoints','ngrids','nlevel','nmon','npar','ntime','nvar','nyear','output','outputarr','outputbounds','outputboundscpt','outputcenter','outputcenter2','outputcentercpt','outputext','outputf','outputfld','outputint','outputkey','outputsrv','outputtab','outputtri','outputts','outputvector','outputvrml','outputxyz','pardes','partab','partab2','seinfo','seinfoc','seinfon','seinfop','showcode','showdate','showformat','showlevel','showltype','showmon','showname','showparam','showstdname','showtime','showtimestamp','showunit','showvar','showyear','sinfo','sinfoc','sinfon','sinfop','sinfov','spartab','specinfo','tinfo','vardes','vct','vct2','verifygrid','vlist','zaxisdes']
    self.libs                   = self.getSupportedLibs()

    self.logging                = logging
    self.logFile                = logFile
    if (self.logging):
        self.logger = setupLogging(self.logFile)

  def __dir__(self):
    res = dir(type(self)) + list(self.__dict__.keys())
    res.extend(self.operators)
    return res

  def isString(self,myString):
      if (2 == sys.version_info[0]):
          return isinstance(myString,basestring)
      else:
          return isinstance(myString,str)

  def call(self,cmd):
    if self.logging and '-h' != cmd[1]:
      self.logger.info(u' '.join(cmd))

    for k,v in self.env.items():
      os.environ[k] = v

    proc = subprocess.Popen(' '.join(cmd),
                            shell  = True,
                            stderr = subprocess.PIPE,
                            stdout = subprocess.PIPE)

    retvals = proc.communicate()
    stdout  = retvals[0].decode("utf-8")
    stderr  = retvals[1].decode("utf-8")

    if self.debug:
      print('# DEBUG - start =============================================================')
      if {} != self.env:
        for k,v in list(self.env.items()):
          print("ENV: " + k + " = " + v)
      print('CALL  :' + ' '.join(cmd))
      print('STDOUT:')
      if (0 != len(stdout.strip())):
        print(stdout)
      print('STDERR:')
      if (0 != len(stderr.strip())):
        print(stderr)
      print('# DEBUG - end ===============================================================')

    return {"stdout"     : stdout
           ,"stderr"     : stderr
           ,"returncode" : proc.returncode}

  def hasError(self,method_name,cmd,retvals):
    if (self.debug):
      print("RETURNCODE:"+retvals["returncode"].__str__())
    if ( 0 != retvals["returncode"] ):
      print("Error in calling operator " + method_name + " with:")
      print(">>> "+' '.join(cmd)+"<<<")
      print('STDOUT:' + retvals["stdout"])
      print('STDERR:' + retvals["stderr"])

      if self.logging:
          self.logger.error(cmd + " with:" + retvals["stderr"])
      return True
    else:
      return False

  def __getattr__(self, method_name):

    @auto_doc(method_name, self)
    def get(self, *args,**kwargs):
      operator          = [method_name]
      operatorPrintsOut = method_name in self.outputOperators

      if args.__len__() != 0:
        for arg in args:
          operator.append(arg.__str__())

      #build the cdo command
      #0. the cdo command
      cmd = [self.CDO]
      #1. OVERWRITE EXISTING FILES
      cmd.append('-O')
      #2. options
      if 'options' in kwargs:
          cmd += kwargs['options'].split()
      #3. operator(s)
      cmd.append(','.join(operator))
      #4. input files or operators
      if 'input' in kwargs:
        if self.isString(kwargs["input"]):
            cmd.append(kwargs["input"])
        else:
            #we assume it's either a list, a tuple or any iterable.
            cmd += kwargs["input"]

      if not kwargs.__contains__("force"):
        kwargs["force"] = self.forceOutput

      if operatorPrintsOut:
        retvals = self.call(cmd)
        if ( not self.hasError(method_name,cmd,retvals) ):
          r = list(map(strip,retvals["stdout"].split(os.linesep)))
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
          if kwargs.__contains__("env"):
            for k,v in kwargs["env"].items():
              os.environ[k] = v

          retvals = self.call(cmd)
          if self.hasError(method_name,cmd,retvals):
            if self.returnNoneOnError:
              return None
            else:
              raise CDOException(**retvals)
        else:
          if self.debug:
            print(("Use existing file'"+kwargs["output"]+"'"))

      if not kwargs.__contains__("returnCdf"):
        kwargs["returnCdf"] = False

      if not None == kwargs.get("returnArray"):
        return self.readArray(kwargs["output"],kwargs["returnArray"])
      elif not None == kwargs.get("returnMaArray"):
        return self.readMaArray(kwargs["output"],kwargs["returnMaArray"])
      elif self.returnCdf or kwargs["returnCdf"]:
        return self.readCdf(kwargs["output"])
      else:
        return kwargs["output"]

    if ((method_name in self.__dict__) or (method_name in self.operators)):
      if self.debug:
        print(("Found method:" + method_name))

      #cache the method for later
      setattr(self.__class__, method_name, get)
      return get.__get__(self)
    elif (method_name == "cdf"):
        # initialize cdf module implicitly
        self.loadCdf()
        return self.cdf
    else:
      # given method might match part of know operators: autocompletion
      if (len(list(filter(lambda x : re.search(method_name,x),self.operators))) == 0):
          # If the method isn't in our dictionary, act normal.
          raise AttributeError("Unknown method '" + method_name +"'!")

  def getOperators(self):
    import os
    if (parse_version(getCdoVersion(self.CDO)) > parse_version('1.7.0')):
        proc = subprocess.Popen([self.CDO,'--operators'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
        ret  = proc.communicate()
        ops  = list(map(lambda x : x.split(' ')[0], ret[0].decode("utf-8")[0:-1].split(os.linesep)))

        return ops

    else:
        proc = subprocess.Popen([self.CDO,'-h'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
        ret  = proc.communicate()
        l    = ret[1].decode("utf-8").find("Operators:")
        ops  = ret[1].decode("utf-8")[l:-1].split(os.linesep)[1:-1]
        endI = ops.index('')
        s    = ' '.join(ops[:endI]).strip()
        s    = re.sub("\s+" , " ", s)

        return list(set(s.split(" ") + self.undocumentedOperators))

  def loadCdf(self):
    if self.cdfMod == CDF_MOD_SCIPY:
      try:
        from scipy.io.netcdf import netcdf_file as cdf
        self.cdf    = cdf
      except:
        print("Could not load scipy.io.netcdf")
        raise

    elif self.cdfMod == CDF_MOD_NETCDF4:
      try:
        from netCDF4 import Dataset as cdf
        self.cdf    = cdf
      except:
        print("Could not load netCDF4")
        raise
    else:
        raise ImportError("scipy or python-netcdf4 module is required to return numpy arrays.")

  def getSupportedLibs(self,force=False):
    proc = subprocess.Popen(self.CDO + ' -V',
        shell  = True,
        stderr = subprocess.PIPE,
        stdout = subprocess.PIPE)
    retvals = proc.communicate()

    withs     = list(re.findall('(with|Features): (.*)',
                     retvals[1].decode("utf-8"))[0])[1].split(' ')
    # do an additional split, if the entry has a / and collect everything into a flatt list
    withs     =  list(map(lambda x : x.split('/') if re.search('\/',x) else x, withs))
    allWiths  = []
    for _withs in withs:
        if isinstance(_withs,list):
            for __withs in _withs:
                allWiths.append(__withs)
        else:
            allWiths.append(_withs)
    withs     = allWiths

    libs      = re.findall('(\w+) library version : (\d+\.\S+) ',
                           retvals[1].decode("utf-8"))
    libraries = dict({})
    for w in withs:
      libraries[w.lower()] = True

    for lib in libs:
      l,v = lib
      libraries[l.lower()] = v

    return libraries

  def setReturnArray(self,value=True):
    self.returnCdf = value


  def unsetReturnArray(self):
      self.setReturnArray(False)

  def collectLogs(self):
      if isinstance(self.logFile,str):
          content = []
          with open(self.logFile,'r') as f:
              content.append(f.read())
          return ''.join(content)
      else:
          self.logFile.flush()
          return self.logFile.getvalue()

  def showLog(self):
      print(self.collectLogs())

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
    return getCdoVersion(self.CDO)

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
