from __future__ import print_function
import os,re,subprocess,tempfile,random,sys,glob
from pkg_resources import parse_version
from io import StringIO
import logging as pyLog
import six

try:
    from string import strip
except ImportError:
    strip = str.strip

try:
    import xarray
    loadedXarray = True
except:
    print("Could not load xarray")
    loadedXarray = False

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
CDO_PY_VERSION  = "1.3.6"

def auto_doc(tool, cdo_self):
    """Generate the __doc__ string of the decorated function by calling the cdo help command"""
    def desc(func):
        func.__doc__ = cdo_self.call([cdo_self.CDO, '-h', tool]).get('stdout')
        return func
    return desc

def getCdoVersion(path2cdo,verbose=False):
    proc = subprocess.Popen([path2cdo,'-V'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
    ret  = proc.communicate()
    cdo_help   = ret[1].decode("utf-8")
    if verbose:
        return cdo_help
    match = re.search("Climate Data Operators version (\d.*) .*",cdo_help)
    return match.group(1)

def setupLogging(logFile):
    logger = pyLog.getLogger(__name__)
    logger.setLevel(pyLog.INFO)

    if isinstance(logFile, six.string_types):
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
               env=os.environ,
               debug=False,
               logging=False,
               logFile=StringIO()):

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
    self.noOutputOperators      = self.getNoOutputOperators()
    self.libs                   = self.getSupportedLibs()

    self.logging                = logging
    self.logFile                = logFile
    if (self.logging):
        self.logger = setupLogging(self.logFile)

  def __dir__(self):
    res = dir(type(self)) + list(self.__dict__.keys())
    res.extend(self.operators)
    return res

  def call(self,cmd,envOfCall={}):
    if self.logging and '-h' != cmd[1]:
      self.logger.info(u' '.join(cmd))

    env = dict(self.env)
    env.update(envOfCall)

    proc = subprocess.Popen(' '.join(cmd),
                            shell  = True,
                            stderr = subprocess.PIPE,
                            stdout = subprocess.PIPE,
                            env    = env)

    retvals = proc.communicate()
    stdout  = retvals[0].decode("utf-8")
    stderr  = retvals[1].decode("utf-8")

    if self.debug:
      print('# DEBUG - start =============================================================')
      if {} != env:
        for k,v in list(env.items()):
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
      operatorPrintsOut = method_name in self.noOutputOperators

      self.envByCall = {}

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
        if isinstance(kwargs["input"], six.string_types):
            cmd.append(kwargs["input"])
        elif type(kwargs["input"]) == list:
            cmd.append(' '.join(kwargs["input"]))
        elif (True == loadedXarray and type(kwargs["input"]) == xarray.core.dataset.Dataset):

            # create a temp nc file from input data
            tempfile = MyTempfile()
            _tpath = tempfile.path()
            kwargs["input"].to_netcdf(_tpath)
            kwargs["input"] = _tpath
            print(kwargs['input'])
            cmd.append(kwargs["input"])
        else:
            #we assume it's either a list, a tuple or any iterable.
            cmd.append(kwargs["input"])

      #5. handle rewrite of existing output files
      if not kwargs.__contains__("force"):
        kwargs["force"] = self.forceOutput

      #6. handle environment setup per call
      envOfCall = {}
      if kwargs.__contains__("env"):
        for k,v in kwargs["env"].items():
          envOfCall[k] = v

      if operatorPrintsOut:
        retvals = self.call(cmd,envOfCall)
        if ( not self.hasError(method_name,cmd,retvals) ):
          r = list(map(strip,retvals["stdout"].split(os.linesep)))
          if "autoSplit" in kwargs:
            splitString = kwargs["autoSplit"]
            _output = [x.split(splitString) for x in r[:len(r)-1]]
            if (1 == len(_output)):
                return _output[0]
            else:
                return _output
          else:
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

          retvals = self.call(cmd,envOfCall)
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

      elif loadedXarray and not None == kwargs.get("returnXArray"):
        return self.readXArray(kwargs["output"],kwargs.get("returnXArray"))

      elif loadedXarray and not None == kwargs.get("returnXDataset"):
        return self.readXDataset(kwargs["output"])

      elif ('split' == method_name[0:5]):
        return glob.glob(kwargs["output"]+'*')

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

        return list(set(s.split(" ")))

  def getNoOutputOperators(self):
    if ( \
            parse_version(getCdoVersion(self.CDO)) > parse_version('1.8.0') and \
            parse_version(getCdoVersion(self.CDO)) < parse_version('1.9.0') ):
      proc = subprocess.Popen([self.CDO,'--operators_no_output'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
      ret  = proc.communicate()
      return list(map(lambda x : x.split(' ')[0], ret[0].decode("utf-8")[0:-1].split(os.linesep)))
    else:
      return ['cdiread','cmor','codetab','conv_cmor_table','diff','diffc','diffn','diffp'
              ,'diffv','dump_cmor_table','dumpmap','filedes','ggstat','ggstats','gmtcells'
              ,'gmtxyz','gradsdes','griddes','griddes2','gridverify','info','infoc','infon'
              ,'infop','infos','infov','map','ncode','ncode','ndate','ngridpoints','ngrids'
              ,'nlevel','nmon','npar','ntime','nvar','nyear','output','outputarr','outputbounds'
              ,'outputboundscpt','outputcenter','outputcenter2','outputcentercpt','outputext'
              ,'outputf','outputfld','outputint','outputkey','outputsrv','outputtab','outputtri'
              ,'outputts','outputvector','outputvrml','outputxyz','pardes','partab','partab2'
              ,'seinfo','seinfoc','seinfon','seinfop','showcode','showdate','showformat','showlevel'
              ,'showltype','showmon','showname','showparam','showstdname','showtime','showtimestamp'
              ,'showunit','showvar','showyear','sinfo','sinfoc','sinfon','sinfop','sinfov'
              ,'spartab','specinfo','tinfo','vardes','vct','vct2','verifygrid','vlist','zaxisdes']


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
    if isinstance(self.logFile, six.string_types):
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

    cmd = [path," -V",'>/dev/null 2>&1']

    executable = (0 == self.call(cmd)["returncode"])
    fullpath = (os.path.isfile(path) and os.access(path, os.X_OK))

    return (executable or fullpath)

  def check(self):
    if not self.hasCdo():
      return False
    if self.debug:
      print(self.call([self.CDO,' -V']))
    return True

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
  def version(self,verbose=False):
    # return CDO's version
    return getCdoVersion(self.CDO,verbose)

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

  def readXArray(self,ifile,varname):
    dataSet = xarray.open_dataset(ifile)
    return dataSet[varname]

  def readXDataset(self,ifile):
    return xarray.open_dataset(ifile)

  def __version__(self):
    return CDO_PY_VERSION

  def __print__(self,context=''):
    if '' != context:
      print('CDO:CONTEXT '+context)
    print("CDO:ID  = "+str(id(self)))
    print("CDO:ENV = "+str(self.env))

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
