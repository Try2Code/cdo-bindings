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
        self.returnArray = False

        self.debug = False

    def __getattr__(self, method_name):
        def get(self, *args,**kwargs):
            operator          = [method_name]
            operatorPrintsOut = re.search('(diff|info|show|griddes)',method_name)

            if args.__len__() != 0:
              for arg in args:
                operator.append(arg.__str__())

              if self.debug:
                print "args:"
                print args
                print operator

            io = []
            if kwargs.__contains__("input"):
              io.append(kwargs["input"])

            if kwargs.__contains__("output"):
              io.append(kwargs["output"])
            else:
              if not operatorPrintsOut:
                kwargs["output"] = MyTempfile().path()
                io.append(kwargs["output"])

            if not kwargs.__contains__("options"):
              kwargs["options"] = ""

            if not kwargs.__contains__("returnArray"):
              kwargs["returnArray"] = False

            call = [self.CDO,kwargs["options"],','.join(operator),' '.join(io)]

            if self.debug:
              print ' '.join(call)

            proc = subprocess.Popen(' '.join(call),
                                    shell  = True,
                                    stderr = subprocess.PIPE,
                                    stdout = subprocess.PIPE)
            retvals = proc.communicate()

            if self.debug:
              print retvals[0]
              print retvals[1]

            if operatorPrintsOut:
              r = map(string.strip,retvals[0].split('\n'))
              return r[:len(r)-1]
            else:
              if self.returnArray or kwargs["returnArray"]:
                if not self.returnArray:
                  self.loadCdf()

                return self.cdf(kwargs["output"])
              else:
                return kwargs["output"]

          

        
        if ((method_name in self.__dict__) or (method_name in self.operators)):
          if self.debug:
            print("Found method:" + method_name)

          return get.__get__(self)
        else:
          # If the method isn't in our dictionary, act normal.
          print("#=====================================================")
          print("Cannot find method:" + method_name)
          raise AttributeError, method_name

    def getOperators(self):
        proc = subprocess.Popen([self.CDO,'-h'],stderr = subprocess.PIPE,stdout = subprocess.PIPE)
        ret  = proc.communicate()
        l    = ret[1].find("Operators:")
        ops  = ret[1][l:-1].split("\n")[1:-1]
        endI = ops.index('')
        s    = ' '.join(ops[:endI]).strip()
        s    = re.sub("\s+" , " ", s)
        return list(set(s.split(" ") + self.undocumentedOperators))

    def loadCdf(self):
      try:
        import pycdf as cdf
        self.cdf         = cdf.CDF
      except ImportError:
        raise ImportError,"Module pycdf is required to return numpy arrays."

    def setReturnArray(self,value=True):
      self.returnArray = value
      if value:
        self.loadCdf()


    def unsetReturnArray(self):
      self.setReturnArray(False)

    def setCDO(self,value):
      self.CDO       = value
      self.operators = self.getOperators()

    #==================================================================
    # Addional operators:
    #------------------------------------------------------------------
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
      if not self.returnArray:
        self.loadCdf()

      return self.cdf(iFile)



# Helper module for easy temp file handling
class MyTempfile(object):
  def __init__(self):
    self.persistent_tempfile = False

  def setPersist(self,value):
    self.persistent_tempfiles = value

  def path(self):
    if not self.persistent_tempfile:
      t = tempfile.NamedTemporaryFile(delete=False)
      t.close
      return t.name
    else:
      N =10000000 
      t = "_"+random.randint(N).__str__()
