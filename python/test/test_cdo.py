from __future__ import print_function
import unittest,os,tempfile,sys,glob,subprocess,multiprocessing,time
from pkg_resources import parse_version
import numpy as np
from matplotlib import pylab as pl

# add local dir to search path
sys.path.append(os.path.dirname(sys.path[0]))
from cdo import Cdo,CDOException


if 'CDF_MOD' in os.environ:
  CDF_MOD = os.environ['CDF_MOD']
else:
  CDF_MOD = 'netcdf4'

HOSTNAME       = 'luthien'
DATA_DIR       = os.environ.get('HOME')+'/local/data'

SHOW           = 'SHOW' in os.environ
DEBUG          = 'DEBUG' in os.environ

MAINTAINERMODE = 'MAINTAINERMODE' in os.environ

def plot(ary,ofile=False,title=None):
    if not SHOW:
      return

    pl.grid(True)

    if not None == title:
      pl.title(title)

    if 1 == ary.ndim:
      pl.plot(ary)
    else:
      pl.imshow(ary,origin='lower',interpolation='nearest')

    if not ofile:
      pl.show()
    else:
      pl.savefig(ofile,bbox_inches='tight',dpi=200)
      subprocess.Popen('sxiv {0}.{1} &'.format(ofile,'png'), shell=True, stderr=subprocess.STDOUT)

def rm(files):
  for f in files:
    if os.path.exists(f):
      os.system("rm "+f)

class CdoTest(unittest.TestCase):

    def testVersions(self):
        cdo = Cdo()
        self.assertEqual('1.3.8',cdo.__version__())
        self.assertTrue(parse_version('1.7.0') <= parse_version(cdo.version()))

    def testCDO(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        newCDO="/usr/bin/cdo"
        if os.path.isfile(newCDO):
            cdo.setCdo(newCDO)
            self.assertEqual(newCDO,cdo.getCdo())
            cdo.setCdo('cdo')

    def testDbg(self):
        if not 'DEBUG' in os.environ:
          cdo = Cdo(cdfMod=CDF_MOD)
          self.assertEqual(False,cdo.debug)
          cdo.debug = True
          self.assertEqual(True,cdo.debug)
          cdo.debug = False

    def test_V(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        print(cdo.version(verbose=True))

    def test_hasCdo(self):
        cdo = Cdo()
        self.assertTrue(cdo.hasCdo())
        cdo.CDO='cccccccc'
        self.assertFalse(cdo.hasCdo())
        cdo.CDO='/bin/cdo'
        if os.path.isfile(cdo.CDO):
          self.assertTrue(cdo.hasCdo())

    def test_check(self):
        cdo = Cdo()
        self.assertTrue(cdo.check())
        cdo.CDO='cvcvcvcvc'
        self.assertFalse(cdo.check())

    def testOps(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertTrue("sinfov" in cdo.operators)
        self.assertTrue("for" in cdo.operators)
        self.assertTrue("mask" in cdo.operators)
        if (parse_version('1.7.0') >= parse_version(cdo.version())):
            self.assertTrue("studentt" in cdo.operators)
        self.assertTrue(len(cdo.operators) > 700)

    def test_getOperators(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        for op in ['random','stdatm','for','cdiwrite','info','showlevel','sinfo','remap','geopotheight','mask','topo','thicknessOfLevels']:
            if 'thicknessOfLevels' != op:
                self.assertTrue(op in cdo.operators)
            else:
                self.assertTrue(op in dir(cdo))

    def test_listAllOperators(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        operators = cdo.operators
        operators.sort()
        #print "\n".join(operators)

    def test_simple(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        s   = cdo.sinfov(input="-topo",options="-f nc")
        s   = cdo.sinfov(input="-remapnn,r36x18 -topo",options="-f nc")
        f   = 'test_ofile.nc'
        cdo.expr("'z=log(abs(topo)+1)*9.81'",input="-topo", output=f, options="-f nc")
        s   = cdo.infov(input=f)
        cdo.stdatm("0",output=f,options="-f nc")
        rm([f,])

    def test_outputOperators(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        levels = cdo.showlevel(input = "-stdatm,0")
        info   = cdo.sinfo(input = "-stdatm,0")
        self.assertEqual([0,0],list(map(float,levels)))
        self.assertEqual("GRIB",info[0].split(' ')[-1])

        values = cdo.outputkey("value",input="-stdatm,0")[1::]
        self.assertEqual(["1013.25", "288"],values)
        values = cdo.outputkey("value",input="-stdatm,0,10000")[1::]
        self.assertEqual(["1013.25", "271.913", "288", "240.591"],values)
        values = cdo.outputkey("lev",input="-stdatm,0,10000")[1::]
        self.assertEqual(["0", "10000","0", "10000"],values)

        # test autoSplit usage
        levels = cdo.showlevel(input="-stdatm,0,10,20",autoSplit=' ')
        self.assertEqual([['0','10','20'],['0','10','20']],levels)

        timesExpected = ['2001-01-01T12:00:00',
          '2001-01-01T13:00:00',
          '2001-01-01T14:00:00',
          '2001-01-01T15:00:00',
          '2001-01-01T16:00:00',
          '2001-01-01T17:00:00',
          '2001-01-01T18:00:00',
          '2001-01-01T19:00:00',
          '2001-01-01T20:00:00',
          '2001-01-01T21:00:00']
        self.assertEqual(timesExpected,
                         cdo.showtimestamp(input="-settaxis,2001-01-01,12:00,1hour -for,1,10", autoSplit='  '))

        self.assertEqual(['P T'],cdo.showname(input="-stdatm,0"))
        self.assertEqual(['P','T'],cdo.showname(input="-stdatm,0",autoSplit=' '))

    def test_bndLevels(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ofile = cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,options = "-f nc")
        self.assertEqual([0, 50.0, 150.0, 350.0, 650.0, 1100.0, 1700.0, 2500.0, 3500.0, 4500.0, 5500.0],
                    cdo.boundaryLevels(input = "-selname,T " + ofile))
        self.assertEqual([50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0, 1000.0, 1000.0, 1000.0],
                     cdo.thicknessOfLevels(input = ofile))

    def test_CDO_options(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        names = cdo.showname(input = "-stdatm,0",options = "-f nc")
        self.assertEqual(["P T"],names)
        if cdo.hasLib("sz"):
          ofile = cdo.topo(options = "-z szip")
          #self.assertEqual(["GRIB SZIP"],cdo.showformat(input = ofile))

    def test_chain(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ofile = cdo.setname("veloc", input=" -copy -random,r1x1",options = "-f nc")
        self.assertEqual(["veloc"],cdo.showname(input = ofile))

    def test_diff(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        diffv = cdo.diffn(input = "-random,global_0.1 -random,global_0.1")
        print(diffv)
        self.assertEqual(diffv[1].split(' ')[-1],"random")
        self.assertEqual(diffv[1].split(' ')[-3],"1.0000")

    def test_returnCdf(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ofile = tempfile.NamedTemporaryFile(delete=True,prefix='cdoPy').name
        press = cdo.stdatm("0",output=ofile,options="-f nc")
        self.assertEqual(ofile,press)
        variables = cdo.stdatm("0",options="-f nc",returnCdf=True).variables
        print(variables)
        cdf = cdo.stdatm("0",options="-f nc",returnCdf=True)
        press = cdf.variables['P'][:]
        self.assertEqual(1013.25,press.min())
        press = cdo.stdatm("0",output=ofile,options="-f nc")
        self.assertEqual(ofile,press)
        cdo.setReturnArray()
        outfile = 'test_returnCdf.nc'
        cdf = cdo.stdatm("0",output=outfile,options="-f nc")
        press = cdf.variables["P"][:]
        self.assertEqual(1013.25,press.min())
        cdo.unsetReturnArray()
        press = cdo.stdatm("0",output=outfile,options="-f nc")
        self.assertEqual(press,outfile)
        cdf = cdo.stdatm("0",output=outfile,options="-f nc",returnCdf=True)
        press = cdf.variables["P"][:]
        self.assertEqual(1013.25,press.min())
        print("press = "+press.min().__str__())
        cdo.unsetReturnArray()
        press = cdo.stdatm("0",output=ofile,options="-f nc")
        self.assertEqual(ofile,press)
        rm([outfile, ])
        rm([ofile,])


    def test_forceOutput(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        outs = []
        # tempfiles
        outs.append(cdo.stdatm("0,10,20"))
        outs.append(cdo.stdatm("0,10,20"))
        self.assertNotEqual(outs[0],outs[1])
        outs = []

        # deticated output, force = true (=defaut setting)
        ofile = 'test_force'
        outs.append(cdo.stdatm("0,10,20",output = ofile))
        mtime0 = os.stat(ofile).st_mtime
        #to make it compatible with systems providing no nanos.
        time.sleep(1)
        outs.append(cdo.stdatm("0,10,20",output = ofile))
        mtime1 = os.stat(ofile).st_mtime
        self.assertNotEqual(mtime0,mtime1)
        self.assertEqual(outs[0],outs[1])
        os.remove(ofile)
        outs = []
 
        # dedicated output, force = false
        ofile = 'test_force_false'
        outs.append(cdo.stdatm("0,10,20",output = ofile,force=False))
        mtime0 = os.stat(outs[0]).st_mtime
        outs.append(cdo.stdatm("0,10,20",output = ofile,force=False))
        mtime1 = os.stat(outs[1]).st_mtime
        self.assertEqual(mtime0,mtime1)
        self.assertEqual(outs[0],outs[1])
        os.remove(ofile)
        outs = []

        # dedicated output, global force setting
        ofile = 'test_force_global'
        cdo.forceOutput = False
        outs.append(cdo.stdatm("0,10,20",output = ofile))
        mtime0 = os.stat(outs[0]).st_mtime
        outs.append(cdo.stdatm("0,10,20",output = ofile))
        mtime1 = os.stat(outs[1]).st_mtime
        self.assertEqual(mtime0,mtime1)
        self.assertEqual(outs[0],outs[1])
        os.remove(ofile)
        outs = []

    def test_combine(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        stdatm  = cdo.stdatm("0",options = "-f nc")
        stdatm_ = cdo.stdatm("0",options = "-f nc")
       #print(cdo.diff(input=stdatm + " " + stdatm_))
       #sum = cdo.fldsum(input = stdatm)
       #sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"),returnCdf=True)
       #self.assertEqual(288.0,sum.variables["T"][:])

    def test_cdf(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertTrue(hasattr(cdo, "cdf"))# not in cdo.__dict__)
        cdo.setReturnArray()
        self.assertTrue(hasattr(cdo, "cdf"))#"cdf" in cdo.__dict__)
        cdo.setReturnArray(False)
        sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"),returnCdf=True)
        self.assertEqual(1013.25,sum.variables["P"][:])
        cdo.unsetReturnArray()

    def test_cdf_mod(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.setReturnArray()
        print('cdo.cdfMod:' + cdo.cdfMod)
        self.assertEqual(cdo.cdfMod, CDF_MOD)

    def test_thickness(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        levels            = "25 100 250 500 875 1400 2100 3000 4000 5000".split(' ')
        targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
        self.assertEqual(targetThicknesses, cdo.thicknessOfLevels(input = "-selname,T -stdatm,"+ ','.join(levels)))

    def test_showlevels(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        sourceLevels = "25 100 250 500 875 1400 2100 3000 4000 5000".split()
        self.assertEqual(' '.join(sourceLevels), 
                        cdo.showlevel(input = "-selname,T " + cdo.stdatm(','.join(sourceLevels),options = "-f nc"))[0]) 

    def test_verticalLevels(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        # check, if a given input files has vertival layers of a given thickness array
        targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
        sourceLevels = "25 100 250 500 875 1400 2100 3000 4000 5000".split()
        thicknesses = cdo.thicknessOfLevels(input = "-selname,T " + cdo.stdatm(','.join(sourceLevels),options = "-f nc")) 
        self.assertEqual(targetThicknesses,thicknesses)


    def test_returnArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        self.assertEqual(False, cdo.stdatm(0,options = '-f nc', returnArray = 'TT'))
        temperature = cdo.stdatm(0,options = '-f nc', returnArray = 'T')
        self.assertEqual(288.0,temperature.flatten()[0])
#TODO       pressure = cdo.stdatm("0,1000",options = '-f nc -b F64',returnArray = 'P')
#TODO       self.assertEqual("[ 1013.25         898.54345604]",pressure.flatten().__str__())

    def test_returnMaArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        topo = cdo.topo(options='-f nc',returnMaArray='topo')
        self.assertEqual(-1890.0,round(topo.mean()))
        bathy = cdo.setrtomiss(0,10000,
            input = cdo.topo(options='-f nc'),returnMaArray='topo')
        self.assertEqual(-3386.0,round(bathy.mean()))
        oro = cdo.setrtomiss(-10000,0,
            input = cdo.topo(options='-f nc'),returnMaArray='topo')
        self.assertEqual(1142.0,round(oro.mean()))
        bathy = cdo.remapnn('r2x2',input = cdo.topo(options = '-f nc'), returnMaArray = 'topo')
        self.assertEqual(-4298.0,bathy[0,0])
        self.assertEqual(-2669.0,bathy[0,1])
        ta = cdo.remapnn('r2x2',input = cdo.topo(options = '-f nc'))
        tb = cdo.subc(-2669.0,input = ta)
        withMask = cdo.div(input=ta+" "+tb,returnMaArray='topo')
        self.assertEqual('--',withMask[0,1].__str__())
        self.assertEqual(False,withMask.mask[0,0])
        self.assertEqual(False,withMask.mask[1,0])
        self.assertEqual(False,withMask.mask[1,1])
        self.assertEqual(True,withMask.mask[0,1])

#   def test_XrDataset(self):
#       cdo = Cdo(cdfMod=CDF_MOD)
#       self.assertTrue(hasattr(cdo, "cdf"))# not in cdo.__dict__)
#       cdo.setReturnArray()
#       self.assertTrue(hasattr(cdo, "cdf"))#"cdf" in cdo.__dict__)
#       cdo.setReturnArray(False)
#       sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"),returnXrDataset=True)
#       self.assertEqual(1013.25,sum.variables["P"][:])
#       cdo.unsetReturnArray()

#   def test_returnXrArray(self):
#       cdo = Cdo(cdfMod=CDF_MOD)
#       cdo.debug = DEBUG
#       topo = cdo.topo(options='-f nc',returnXrArray='topo')
#       self.assertEqual(-1890.0,round(topo.mean()))
#       bathy = cdo.setrtomiss(0,10000,
#           input = cdo.topo(options='-f nc'),returnXrArray='topo')
#       self.assertEqual(-3386.0,round(bathy.mean()))
#       oro = cdo.setrtomiss(-10000,0,
#           input = cdo.topo(options='-f nc'),returnXrArray='topo')
#       self.assertEqual(1142.0,round(oro.mean()))
#       bathy = cdo.remapnn('r2x2',input = cdo.topo(options = '-f nc'), returnXrArray = 'topo')
#       self.assertEqual(-4298.0,bathy[0,0])
#       self.assertEqual(-2669.0,bathy[0,1])
#       ta = cdo.remapnn('r2x2',input = cdo.topo(options = '-f nc'))
#       tb = cdo.subc(-2669.0,input = ta)
#       withMask = cdo.div(input=ta+" "+tb,returnXrArray='topo')
#       self.assertEqual('--',withMask[0,1].__str__())
#       self.assertEqual(False,withMask.mask[0,0])
#       self.assertEqual(False,withMask.mask[1,0])
#       self.assertEqual(False,withMask.mask[1,1])
#       self.assertEqual(True,withMask.mask[0,1])

    def test_errorException(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.__print__('test_errorException')
        self.assertFalse(hasattr(cdo, 'nonExistingMethod'))
        self.failUnlessRaises(CDOException, cdo.max)
        try:
            cdo.max()
        except CDOException as e:
            self.assertTrue(e.returncode != 0)
            self.assertTrue(len(e.stderr) > 1)
            self.assertTrue(hasattr(e, 'stdout'))

        try:
            cdo.stdatm(0,10,input="",output="")
        except CDOException as e:
            self.assertTrue(e.returncode != 0)
            self.assertTrue(len(e.stderr) > 1)
            self.assertTrue(hasattr(e, 'stdout'))

    def test_inputArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        # check for file input
        fileA = cdo.stdatm(0,output='A')
        fileB = cdo.stdatm(0,output='B')
        files = [fileA,fileB]
        self.assertEqual(cdo.diffv(input = ' '.join(files)), cdo.diffv(input = files))
        self.assertEqual([],cdo.diffv(input = files))
        # check for operator input
        self.assertEqual([],cdo.diffv(input = ["-stdatm,0","-stdatm,0"]))
        # check for operator input and files
        self.assertEqual([],cdo.diffv(input = ["-stdatm,0",fileB]))
        rm([fileA, fileB])

    def test_splitOps(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        pattern = 'stdAtm'
        cdo.__print__('test_splitOps')
        resultsFiles = cdo.splitname(input = '-stdatm,0',output = pattern)
        self.assertTrue(2 <= len(resultsFiles))
        if DEBUG:
          print(resultsFiles)
        for var in ['T','P']:
          print(pattern+var+'.grb')
          self.assertTrue(pattern+var+'.grb' in resultsFiles)
        rm(resultsFiles)

        pattern = 'sel'
        resultsFiles = cdo.splitsel(1,input = '-for,0,9',output = pattern)
        if DEBUG:
          print(resultsFiles)
        self.assertTrue(10 <= len(resultsFiles))
        rm(resultsFiles)
        for var in range(0,10):
          self.assertTrue(pattern+'00000'+str(var)+'.grb' in resultsFiles)
        rm(resultsFiles)

        pattern = 'lev'
        resultsFiles = cdo.splitlevel(input = '-stdatm,100,2000,5000',output = pattern)
        self.assertTrue(3 <= len(resultsFiles))
        if DEBUG:
          print(resultsFiles)
        rm(resultsFiles)
        for var in ['0100','2000','5000']:
          self.assertTrue(pattern+'00'+str(var)+'.grb' in resultsFiles)
        rm(resultsFiles)

    def test_output_set_to_none(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertEqual(str,type(cdo.topo(output = None)))
        self.assertEqual("GRIB",cdo.sinfov(input = "-topo", output = None)[0].split(' ')[-1])

    def test_libs(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        if DEBUG:
          print(cdo.libs)
        self.assertTrue(cdo.hasLib("nc4"),"netcdf4 support missing")
        self.assertTrue(cdo.hasLib("netcdf"),"netcdf support missing")
        self.assertTrue(cdo.hasLib("udunits2"),"netcdf support missing")
        self.assertFalse(cdo.hasLib("udunits"),'boost is not a CDO dependency')
        self.assertFalse(cdo.hasLib("boost"),'boost is not a CDO dependency')
        self.assertRaises(AttributeError, cdo.libsVersion,"foo")

    def test_returnNone(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertFalse(cdo.returnNoneOnError,"'returnNoneOnError' is _not_ False after initialization")
        cdo.returnNoneOnError = True
        self.assertTrue(cdo.returnNoneOnError,"'returnNoneOnError' is _not_ True after manual setting")
        ret  = cdo.sinfo(input="-topf")
        self.assertEqual(None,ret)
        if DEBUG:
          print(ret)

        cdo_ = Cdo(cdfMod=CDF_MOD, returnNoneOnError=True)
        self.assertTrue(cdo_.returnNoneOnError)
        ret  = cdo_.sinfo(input=" ifile.grb")
        self.assertEqual(None,ret)
        if DEBUG:
          print(ret)

    def test_initOptions(self):
        cdo = Cdo(cdfMod=CDF_MOD, debug=True)
        self.assertTrue(cdo.debug)
        cdo = Cdo(forceOutput=False)
        self.assertFalse(cdo.forceOutput)
        cdo = Cdo(True,True, cdfMod=CDF_MOD)
        self.assertTrue(cdo.returnCdf)
        cdo.returnCdf = False
        self.assertTrue(not cdo.returnCdf)
        self.assertTrue(cdo.returnNoneOnError)

    def test_env(self):
        # clean up
        tag = 'test___env_test'
        files = glob.glob(tag+'*')
        rm(files)
        files = glob.glob(tag+'*')
        self.assertEqual([],files)

        # setup
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        self.assertEqual(os.environ,cdo.env)

        cdo.__print__('test_env')
        # cdf default
        ifile = cdo.stdatm(10,20,50,100,options='-f nc')
        cdo.splitname(input=ifile,output=tag)
        files = glob.glob(tag+'*')
        files.sort()
        self.assertEqual(['%sP.nc'%(tag), '%sT.nc'%(tag)],files)
        rm(files)

        # manual setup to nc2 via operator call
        cdo.splitname(input=ifile,output=tag,env={"CDO_FILE_SUFFIX": ".foo"})
        cdo.env = {}
        files = glob.glob(tag+'*')
        files.sort()
        self.assertEqual(['%sP.foo'%(tag), '%sT.foo'%(tag)],files)
        rm(files)

        # manual setup to nc2 via object setup
        cdo.__print__('test_env:VOR BLA')
        cdo.env = {"CDO_FILE_SUFFIX": ".bla"}
        cdo.splitname(input=ifile,output=tag)
        cdo.splitname(input=ifile,output='bla')
        cdo.__print__('test_env:NACH BLA')
        cdo.env = {}
        files = glob.glob(tag+'*')
        files.sort()
        self.assertEqual(['%sP.bla'%(tag), '%sT.bla'%(tag)],files)
        rm(files)
        cdo.__print__('test_env:ENDE')

    def test_showMaArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        if DEBUG:
          print(cdo)
        bathy = cdo.setrtomiss(0,10000,
                               input = cdo.topo(options='-f nc'),returnMaArray='topo')
        plot(bathy)
        oro = cdo.setrtomiss(-10000,0,
                             input = cdo.topo(options='-f nc'),returnMaArray='topo')
        plot(oro)
        random = cdo.setname('test_maArray',
                             input = "-setrtomiss,0.4,0.8 -random,r180x90 ",
                             returnMaArray='test_maArray',
                             options = "-f nc")
        plot(random)

    def test_cdf_mods(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        if 'CDF_MOD' in os.environ:
          self.assertEqual(os.environ['CDF_MOD'],cdo.cdfMod)
        else:
          self.assertEqual('netcdf4',cdo.cdfMod)

    def test_fillmiss(self):
        cdo = Cdo(cdfMod='netcdf4')
        if 'CDO' in os.environ:
          cdo.setCdo(os.environ.get('CDO'))

        cdo.debug = DEBUG
        rand = cdo.setname('v',input = '-random,r25x25 ', options = ' -f nc',output = '/tmp/rand.nc')
        cdf  = cdo.openCdf(rand)
        var  = cdf.variables['v']
        vals = var[:]
        ni,nj = np.shape(vals)
        for i in range(0,ni):
          for j in range(0,nj):
            vals[i,j] = np.abs((ni/2-i)**2 + (nj/2-j)**2)

        vals = vals/np.abs(vals).max()
        var[:] = vals
        cdf.close()

        missRange = '0.25,0.85'
        withMissRange = 'test_withMissRange.nc'
        arOrg = cdo.copy(input = rand,returnMaArray = 'v')
        arWmr = cdo.setrtomiss(missRange,input = rand,output = withMissRange,returnMaArray='v')
        arFm  = cdo.fillmiss(            input = withMissRange,returnMaArray = 'v')
        arFm1s= cdo.fillmiss2(2,         input = withMissRange,returnMaArray = 'v',output='test_foo.nc')
        if 'setmisstonn' in cdo.operators:
          arM2NN= cdo.setmisstonn(         input = withMissRange,returnMaArray = 'v',output='test_foo.nc')

        pool = multiprocessing.Pool(8)
        pool.apply_async(plot, (arOrg, ),{"title":'org'      })#ofile='fmOrg')
        pool.apply_async(plot, (arWmr, ),{"title":'missing'  })#ofile='fmWmr')
        pool.apply_async(plot, (arFm,  ),{"title":'fillmiss' })#ofile= 'fmFm')
        pool.apply_async(plot, (arFm1s,),{"title":'fillmiss2'})#ofile='fmFm2')
        if 'setmisstonn' in cdo.operators:
          pool.apply_async(plot, (arM2NN,), {"title":'setmisstonn'})#, ofile='fmsetMNN')

        pool.close()
        pool.join()

        rm([rand])

    def test_keep_coordinates(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ifile = '/pool/data/ICON/ocean_data/ocean_grid/iconR2B02-ocean_etopo40_planet.nc'
        if (os.path.isfile(ifile)):
          ivar  = 'ifs2icon_cell_grid'
          varIn = cdo.readCdf(ifile)
          varIn = varIn.variables[ivar]
          if ('scipy' == cdo.cdfMod ):
            expected = b'clon clat'
          else:
            expected =  'clon clat'

          self.assertEqual(expected,varIn.coordinates)

          varOut =cdo.readCdf(cdo.selname(ivar,input=ifile))
          varOut = varOut.variables[ivar]
          expected = expected.split(' ')
          expected.reverse()
          self.assertEqual(expected,varOut.coordinates.split(' '))

#   def testTmp(self):
#       cdo = Cdo(cdfMod=CDF_MOD)
#       tempDir = tempfile.gettempdir()
#       tempfilesStart = glob.glob('{0}/cdoPy*'.format(tempDir))
#       tempfilesStart.sort()
#       tempfilesEnd   = tempfilesStart
#       self.assertEqual(tempfilesStart,tempfilesEnd)
#
#       self.test_combine()
#       tempfilesEnd = glob.glob('{0}/cdoPy**'.format(tempDir))
#       tempfilesEnd.sort()
#       self.assertEqual(tempfilesStart,tempfilesEnd)
    def test_readArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ifile = cdo.enlarge('r44x35',
                            input=' -stdatm,0,100,1000',
                            options='-f nc')
        self.assertEqual((3,35,44), cdo.readArray(ifile, 'T').shape)

    def test_log(self):
        cmd = '-fldmean -mul -random,r20x20 -topo,r20x20'
        if DEBUG:
          print('# logging with a real file')
        cdo = Cdo(cdfMod=CDF_MOD,logging = True,logFile='foo.log')
        cdo.topo()
        cdo.temp()
        cdo.sinfov(input=cmd)
        if DEBUG:
          cdo.showLog()

        cmd = '-fldmean -mul -random,r20x20 -topo,r20x20'
        if DEBUG:
          print('# logging with a real file, passed as unicode string')
        cdo = Cdo(cdfMod=CDF_MOD, logging=True, logFile=u'foo.log')
        cdo.topo()
        cdo.temp()
        cdo.sinfov(input=cmd)
        if DEBUG:
          cdo.showLog()

        if DEBUG:
          print('# logging with in-memory stringio')
        cdo = Cdo(cdfMod=CDF_MOD,logging = True)
        cdo.topo()
        cdo.temp()
        cdo.sinfov(input=cmd)
        if DEBUG:
          cdo.showLog()

    def test_noOutputOps(self):
      cdo = Cdo(cdfMod=CDF_MOD)
      opCount = len(cdo.noOutputOperators)
      self.assertTrue(opCount > 50)
      self.assertTrue(opCount < 200)

    def test_cdiMeta(self):
      cdo = Cdo()
      ofile = cdo.stdatm("0", options = "-f nc", returnCdf = True)
      if DEBUG:
        print(ofile)
      ofile = cdo.stdatm("0", options = "-f nc4", returnCdf = True)
      if DEBUG:
        print(ofile)
      ofile = cdo.stdatm("0", options = "-f nc", returnXArray = 'T')
      if DEBUG:
        print(ofile)
        print(ofile.attrs)
      ofile = cdo.stdatm("0", options = "-f nc", returnXDataset=True)
      if DEBUG:
        print(ofile)
        print(ofile.attrs)

    def testTempdir(self):
      # manual set path
      tempPath = os.path.abspath('.')+'/tempPy'
      cdo = Cdo(tempdir=tempPath)
      cdo.topo('r10x10',options = '-f nc')
      self.assertEqual(1,len(os.listdir(tempPath)))
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      self.assertEqual(3,len(os.listdir(tempPath)))
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      self.assertEqual(5,len(os.listdir(tempPath)))
      cdo.cleanTempDir()
      self.assertEqual(0,len(os.listdir(tempPath)))

      # automatic path
      tempPath = tempfile.gettempdir()
      cdo = Cdo()
      cdo.topo('r10x10',options = '-f nc')
      self.assertEqual(1,len([ f for f in os.listdir(tempPath) if 'cdoPy' in f]))
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      self.assertEqual(3,len([ f for f in os.listdir(tempPath) if 'cdoPy' in f]))
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      cdo.topo('r10x10',options = '-f nc')
      self.assertEqual(12,len([ f for f in os.listdir(tempPath) if 'cdoPy' in f]))
      cdo.cleanTempDir()
      self.assertEqual(0,len([ f for f in os.listdir(tempPath) if 'cdoPy' in f]))


    if MAINTAINERMODE:

      def test_longChain(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ifile = "-enlarge,global_0.3 -settaxis,2000-01-01 -expr,'t=sin(for*3.141529/180.0)' -for,1,10"
        t = cdo.fldmax(input="-div -sub -timmean -seltimestep,2,3 %s -seltimestep,1 %s -gridarea %s"%(ifile,ifile,ifile),returnArray="T")
        self.assertEqual(8.9813e-09,t[0])

      def test_icon_coords(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ifile = DATA_DIR +'/icon/oce_AquaAtlanticBoxACC.nc'
        ivar  = 't_acc'
        varIn = cdo.readCdf(ifile)
        varIn = varIn.variables[ivar]
        if ('scipy' == cdo.cdfMod ):
          expected = b'clon clat'
        else:
          expected =  u'clon clat'
        self.assertEqual(expected,varIn.coordinates)

        varOut =cdo.readCdf(cdo.selname(ivar,input=ifile))
        varOut = varOut.variables[ivar]
        expected =  u'clat clon'
        self.assertEqual(expected,varOut.coordinates)
      def testCall(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        if DEBUG:
          print(cdo.sinfov(input=DATA_DIR+'/icon/oce.nc'))
      def test_readCdf(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        input= "-settunits,days  -setyear,2000 -for,1,4"
        cdfFile = cdo.copy(options="-f nc",input=input)
        cdf     = cdo.readCdf(cdfFile)

        self.assertEqual(sorted(['lat','lon','for','time']),sorted(list(cdf.variables.keys())))


      def test_phc(self):
        ifile = DATA_DIR+'/icon/phc.nc'
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = DEBUG
        #cdo.merge(input='/home/ram/data/icon/input/phc3.0/PHC__3.0__TempO__1x1__annual.nc /home/ram/data/icon/input/phc3.0/PHC__3.0__SO__1x1__annual.nc',
        #          output=ifile,
        #          options='-O')
        s = cdo.sellonlatbox(0,30,0,90, input="-chname,SO,s,TempO,t " + ifile,output='test_my_phc.nc',returnMaArray='s',options='-f nc')
        plot(np.flipud(s[0,:,:]),ofile='org',title='original')
        sfmo = cdo.sellonlatbox(0,30,0,90, input="-fillmiss -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
        plot(np.flipud(sfmo[0,:,:]),ofile='fm',title='fillmiss')
        sfm = cdo.sellonlatbox(0,30,0,90, input="-fillmiss2 -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
        plot(np.flipud(sfm[0,:,:]),ofile='fm2',title='fillmiss2')
        ssetmisstonn = cdo.sellonlatbox(0,30,0,90, input="-setmisstonn -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
        plot(np.flipud(ssetmisstonn[0,:,:]),ofile='setmisstonn',title='setmisstonn')
        if (parse_version(cdo.version()) >= parse_version('1.7.2')):
          smooth = cdo.sellonlatbox(0,30,0,90, input="-smooth -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
          plot(np.flipud(ssetmisstonn[0,:,:]),ofile='smooth',title='smooth')
        #global plot
        #s_global = cdo.chname('SO,s,TempO,t',input=ifile,output='my_phc.nc',returnMaArray='s',options='-f nc')
        #plot(s_global[0,:,:],ofile='org_global',title='org_global')
        #sfmo_global = cdo.fillmiss(input=" -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
        #plot(sfmo_global[0,:,:],ofile='fm_global',title='fm_global')
        #sfm_global = cdo.fillmiss2(input=" -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
        #plot(sfm_global[0,:,:],ofile='fm2_global',title='fm2_global')
        #ssetmisstonn_global = cdo.setmisstonn(input=" -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
        #plot(ssetmisstonn_global[0,:,:],ofile='setmisstonn_global',title='setmisstonn_global')

      def test_smooth(self):
        cdo = Cdo(cdfMod='netcdf4')
        if (parse_version(cdo.version()) >= parse_version('1.7.2')):
          ifile = DATA_DIR+'/icon/phc.nc'
          cdo = Cdo(cdfMod=CDF_MOD)
          cdo.debug = DEBUG
          #cdo.merge(input='/home/ram/data/icon/input/phc3.0/PHC__3.0__TempO__1x1__annual.nc /home/ram/data/icon/input/phc3.0/PHC__3.0__SO__1x1__annual.nc',
          #          output=ifile,
          #          options='-O')
          smooth = cdo.smooth(input=" -sellonlatbox,0,30,0,90 -chname,SO,s,TempO,t " + ifile, returnMaArray='s',options='-f nc')
          plot(np.flipud(smooth[0,:,:]),ofile='smooth',title='smooth')

          smooth2 = cdo.smooth('nsmooth=2',input="-sellonlatbox,0,30,0,90 -chname,SO,s,TempO,t " + ifile, returnMaArray='s',options='-f nc')
          plot(np.flipud(smooth2[0,:,:]),ofile='smooth2',title='smooth,nsmooth=2')

          smooth4 = cdo.smooth('nsmooth=4',input="-sellonlatbox,0,30,0,90 -chname,SO,s,TempO,t " + ifile, returnMaArray='s',options='-f nc')
          plot(np.flipud(smooth4[0,:,:]),ofile='smooth4',title='smooth,nsmooth=4')

          smooth9 = cdo.smooth9(input="-sellonlatbox,0,30,0,90 -chname,SO,s,TempO,t " + ifile, returnMaArray='s',options='-f nc')
          plot(np.flipud(smooth9[0,:,:]),ofile='smooth9',title='smooth9')

          smooth3deg = cdo.smooth('radius=6deg',input="-sellonlatbox,0,30,0,90 -chname,SO,s,TempO,t " + ifile, returnMaArray='s',options='-f nc')
          plot(np.flipud(smooth3deg[0,:,:]),ofile='smooth3deg',title='smooth,radius=6deg')

          smooth20 = cdo.smooth('nsmooth=20',input="-sellonlatbox,0,30,0,90 -chname,SO,s,TempO,t " + ifile, returnMaArray='s',options='-f nc')
          plot(np.flipud(smooth20[0,:,:]),ofile='smooth20',title='smooth,nsmooth=20')

      def test_xarray_input(self):
        cdo = Cdo(cdfMod='netcdf4')
        try:
          import xarray
        except:
          print("no xarray installation available!")
          return

        dataSet = xarray.open_dataset(cdo.topo('global_0.1',options = '-f nc'))

        if DEBUG:
          print(type(dataSet).__name__)

        dataSet['topo'] = 1.0 + np.abs(dataSet['topo'])

        #check the changes withing xarray
        self.assertEqual(1.0,np.min(dataSet['topo']))

        xarrayFile = 'test_xarray_topoAbs.nc'
        dataSet.to_netcdf(xarrayFile)

        #check change via cdo
        minByCdo = cdo.fldmin(input=xarrayFile,returnArray='topo').min()
        self.assertEqual(1.0,minByCdo)

        #do the same without explicit tempfile
        self.assertEqual(1.0,cdo.fldmin(input=dataSet,returnArray='topo').min())


      def test_xarray_output(self):
        cdo = Cdo(cdfMod='netcdf4')
        try:
          import xarray
        except:
          print("no xarray installation available!")
          return

        tArray = cdo.topo('global_10.0',options = '-f nc',returnXArray = 'topo')
        if DEBUG:
          print(tArray)

      def test_xdataset_output(self):
        cdo = Cdo(cdfMod='netcdf4')
        try:
          import xarray
        except:
          print("no xarray installation available!")
          return

        tDataset = cdo.topo('global_10.0',options = '-f nc',returnXDataset = True)
        if DEBUG:
          print(tDataset)
#===============================================================================
if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromTestCase(CdoTest)
#   print(suite)
    unittest.main()
#   unittest.TextTestRunner(verbosity=2).run(suite)

# vim:sw=2
# vim:fdm=syntax
