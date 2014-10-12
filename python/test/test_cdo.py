from __future__ import print_function
import unittest,os,tempfile,sys,glob
from stat import *
from cdo import *
import numpy as np
from matplotlib import pylab as pl

# add local dir to search path

CDF_MOD = CDF_MOD_SCIPY

def plot(ary,ofile=False,title=None):
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

def rm(files):
  for f in files:
    if os.path.exists(f):
      os.system("rm "+f)

class CdoTest(unittest.TestCase):

    def testCDO(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        newCDO="/usr/bin/cdo"
        if os.path.isfile(newCDO):
            cdo.setCdo(newCDO)
            self.assertEqual(newCDO,cdo.getCdo())
            cdo.setCdo('cdo')

    def testDbg(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertEqual(False,cdo.debug)
        cdo.debug = True
        self.assertEqual(True,cdo.debug)
        cdo.debug = False

    def testOps(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertTrue("sinfov" in cdo.operators)
        self.assertTrue("for" in cdo.operators)
        self.assertTrue("mask" in cdo.operators)
        self.assertTrue("studentt" in cdo.operators)

    def test_mod_version(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertEqual('1.2.3',cdo.module_version())

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
        cdo.debug = True
        s   = cdo.sinfov(input="-topo",options="-f nc")
        s   = cdo.sinfov(input="-remapnn,r36x18 -topo",options="-f nc")
        f   = 'ofile.nc'
        cdo.expr("'z=log(abs(topo+1))*9.81'",input="-topo", output=f, options="-f nc")
        s   = cdo.infov(input=f)
        cdo.stdatm("0",output=f,options="-f nc")
        rm([f,])

    def test_outputOperators(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        levels = cdo.showlevel(input = "-stdatm,0")
        info   = cdo.sinfo(input = "-stdatm,0")
        self.assertEqual([0,0],list(map(float,levels)))
        self.assertEqual("File format: GRIB",info[0])

        values = cdo.outputkey("value",input="-stdatm,0")
        self.assertEqual(["1013.25", "288"],values)
        values = cdo.outputkey("value",input="-stdatm,0,10000")
        self.assertEqual(["1013.25", "271.913", "288", "240.591"],values)
        values = cdo.outputkey("level",input="-stdatm,0,10000")
        self.assertEqual(["0", "10000","0", "10000"],values)

    def test_bndLevels(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        ofile = cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,options = "-f nc")
        self.assertEqual([0, 50.0, 150.0, 350.0, 650.0, 1100.0, 1700.0, 2500.0, 3500.0, 4500.0, 5500.0],
                    cdo.boundaryLevels(input = "-selname,T " + ofile))
        self.assertEqual([50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0, 1000.0, 1000.0, 1000.0],
                     cdo.thicknessOfLevels(input = ofile))

    def test_CDO_options(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = True
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
        cdo.debug = True
        diffv = cdo.diffn(input = "-random,r1x1 -random,r1x1")
        print(diffv)
        self.assertEqual(diffv[1].split(' ')[-1],"random")
        self.assertEqual(diffv[1].split(' ')[-3],"0.53060")
        diff  = cdo.diff(input = "-random,r1x1 -random,r1x1")
        self.assertEqual(diff[1].split(' ')[-3],"0.53060")

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
        outfile = 'test.nc'
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


    def test_forceOutput(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = True
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
        import time
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
        cdo.debug = True
        stdatm  = cdo.stdatm("0",options = "-f nc")
        stdatm_ = cdo.stdatm("0",options = "-f nc")
        print(cdo.diff(input=stdatm + " " + stdatm_))
        sum = cdo.fldsum(input = stdatm)
        sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"),returnCdf=True)
        self.assertEqual(288.0,sum.variables["T"][:])

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
        cdo.debug = True
        self.assertEqual(False, cdo.stdatm(0,options = '-f nc', returnArray = 'TT'))
        temperature = cdo.stdatm(0,options = '-f nc', returnArray = 'T')
        self.assertEqual(288.0,temperature.flatten()[0])
        pressure = cdo.stdatm("0,1000",options = '-f nc -b F64',returnArray = 'P')
        self.assertEqual("[ 1013.25         898.54345604]",pressure.flatten().__str__())

    def test_returnMaArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = True
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

    def test_errorException(self):
        cdo = Cdo(cdfMod=CDF_MOD)
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
        cdo.debug = 'DEBUG' in os.environ
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

    def test_output_set_to_none(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertEqual(str,type(cdo.topo(output = None)))
        self.assertEqual("File format: GRIB",cdo.sinfov(input = "-topo", output = None)[0])

    def test_libs(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = True
        self.assertTrue(cdo.hasLib("cdi"),"CDI support missing")
        self.assertTrue(cdo.hasLib("nc4"),"netcdf4 support missing")
        self.assertTrue(cdo.hasLib("netcdf"),"netcdf support missing")
        self.assertFalse(cdo.hasLib("boost"),'boost is not a CDO dependency')
        self.assertRaises(AttributeError, cdo.libsVersion,"foo")

    def test_returnNone(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        self.assertFalse(cdo.returnNoneOnError,"'returnNoneOnError' is _not_ False after initialization")
        cdo.returnNoneOnError = True
        self.assertTrue(cdo.returnNoneOnError,"'returnNoneOnError' is _not_ True after manual setting")
        ret  = cdo.sinfo(input="-topf")
        self.assertEqual(None,ret)
        print(ret)

        cdo_ = Cdo(cdfMod=CDF_MOD, returnNoneOnError=True)
        self.assertTrue(cdo_.returnNoneOnError)
        ret  = cdo_.sinfo(input=" ifile.grb")
        self.assertEqual(None,ret)
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
        tag = '__env_test'
        files = glob.glob(tag+'*')
        rm(files)
        files = glob.glob(tag+'*')
        self.assertEqual([],files)

        # setup
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = 'DEBUG' in os.environ

        # cdf default
        ifile = cdo.stdatm(10,20,50,100,options='-f nc')
        cdo.splitname(input=ifile,output=tag)
        files = glob.glob(tag+'*')
        files.sort()
        self.assertEqual(['__env_testP.nc', '__env_testT.nc'],files)
        rm(files)

        # manual setup to nc2 via operator call
        cdo.splitname(input=ifile,output=tag,env={"CDO_FILE_SUFFIX": ".nc2"})
        files = glob.glob(tag+'*')
        files.sort()
        self.assertEqual(['__env_testP.nc2', '__env_testT.nc2'],files)
        rm(files)

        # manual setup to nc2 via object setup
        cdo.env = {"CDO_FILE_SUFFIX": ".foo"}
        cdo.splitname(input=ifile,output=tag)
        files = glob.glob(tag+'*')
        files.sort()
        self.assertEqual(['__env_testP.foo', '__env_testT.foo'],files)
        rm(files)

    def test_showMaArray(self):
        cdo = Cdo(cdfMod=CDF_MOD)
        cdo.debug = True
        bathy = cdo.setrtomiss(0,10000,
            input = cdo.topo(options='-f nc'),returnMaArray='topo')
        pl.imshow(bathy,origin='lower')
        pl.show()
        oro = cdo.setrtomiss(-10000,0,
            input = cdo.topo(options='-f nc'),returnMaArray='topo')
        pl.imshow(oro,origin='lower')
        pl.show()
        random = cdo.setname('test_maArray',
                             input = "-setrtomiss,0.4,0.8 -random,r180x90 ",
                             returnMaArray='test_maArray',
                             options = "-f nc")
        pl.imshow(random,origin='lower')
        pl.show()
        rand = cdo.setname('v',input = '-random,r5x5 ', options = ' -f nc',output = '/tmp/rand.nc')

    def test_fillmiss(self):
      cdo = Cdo(cdfMod='netcdf4')
      if 'thingol' == os.popen('hostname').read().strip():
        if 'CDO' in os.environ:
          cdo.setCdo(os.environ.get('CDO'))

        cdo.debug = True
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
        withMissRange = 'withMissRange.nc'
        arOrg = cdo.copy(input = rand,returnMaArray = 'v')
        arWmr = cdo.setrtomiss(missRange,input = rand,output = withMissRange,returnMaArray='v')
        arFm  = cdo.fillmiss(            input = withMissRange,returnMaArray = 'v')
        arFm1s= cdo.fillmiss2(2,        input = withMissRange,returnMaArray = 'v',output='foo.nc')

        plot(arOrg,title='org'        )#ofile='fmOrg.svg')
        plot(arWmr,title='missing'    )#ofile='fmWmr.svg')
        plot(arFm,title='fillmiss'    )#ofile='fmFm.svg')
        plot(arFm1s,title='fillmiss1s')#ofile='fmFm2.svg')
        #        os.system("convert +append %s %s %s %s fm_all.png "%('fm_org.png','fm_wmr.png','fm_fm.png','fm_fm1s.png

    if os.popen('hostname -d').read().strip() == 'zmaw.de' or os.popen('hostname -d').read().strip() == 'mpi.zmaw.de':
        def test_keep_coordinates(self):
            #cdo = Cdo(cdfMod='netcdf4')
            cdo = Cdo()
            cdo.setCdo('../../src/cdo')
            ifile = '/pool/data/ICON/ocean_data/ocean_grid/iconR2B02-ocean_etopo40_planet.nc'
            ivar  = 'ifs2icon_cell_grid'
            varIn = cdo.readCdf(ifile)
            varIn = varIn.variables[ivar]
            self.assertEqual('clon clat',varIn.coordinates)

            varOut =cdo.readCdf(cdo.selname(ivar,input=ifile))
            varOut = varOut.variables[ivar]
            self.assertEqual('clon clat',varOut.coordinates)


    if 'thingol' == os.popen('hostname').read().strip():
        def test_icon_coords(self):
            cdo = Cdo()
            cdo.setCdo('../../src/cdo')
            ifile = os.environ.get('HOME')+'/data/icon/oce_r2b7.nc'
            ivar  = 't_acc'
            varIn = cdo.readCdf(ifile)
            varIn = varIn.variables[ivar]
            self.assertEqual('clon clat',varIn.coordinates)

            varOut =cdo.readCdf(cdo.selname(ivar,input=ifile))
            varOut = varOut.variables[ivar]
            self.assertEqual('clon clat',varOut.coordinates)
        def testCall(self):
            cdo = Cdo()
            print(cdo.sinfov(input='/home/ram/data/icon/oce.nc'))
        def test_readCdf(self):
            cdo = Cdo()
            input= "-settunits,days  -setyear,2000 -for,1,4"
            cdfFile = cdo.copy(options="-f nc",input=input)
            cdf     = cdo.readCdf(cdfFile)
            self.assertEqual(['lat','lon','for','time'],list(cdf.variables.keys()))

        def testTmp(self):
            cdo = Cdo()
            import glob
            tempfilesStart = glob.glob('/tmp/cdoPy*')
            tempfilesStart.sort()
            tempfilesEnd   = glob.glob('/tmp/cdoPy**')
            tempfilesEnd.sort()
            self.assertEqual(tempfilesStart,tempfilesEnd)

            self.test_combine()
            tempfilesEnd = glob.glob('/tmp/cdoPy**')
            tempfilesEnd.sort()
            self.assertEqual(tempfilesStart,tempfilesEnd)
        def test_readArray(self):
            cdo = Cdo()
            ifile = '/home/ram/data/examples/EH5_AMIP_1_TSURF_1991-1995.nc'
            self.assertEqual((10, 96, 192),
                cdo.readArray(cdo.seltimestep('1/10',
                  input=ifile),
                  'tsurf').shape)

        def test_phc(self):
           ifile = '/home/ram/data/icon/input/phc3.0/phc.nc'
           cdo = Cdo(cdfMod='netcdf4')
           cdo = Cdo(cdfMod='scipy')
           if 'CDO' in os.environ:
             cdo.setCdo(os.environ.get('CDO'))

           cdo.debug = True
           #cdo.merge(input='/home/ram/data/icon/input/phc3.0/PHC__3.0__TempO__1x1__annual.nc /home/ram/data/icon/input/phc3.0/PHC__3.0__SO__1x1__annual.nc',
           #          output=ifile,
           #          options='-O')
           s = cdo.sellonlatbox(0,30,0,90, input="-chname,SO,s,TempO,t " + ifile,output='my_phc.nc',returnMaArray='s',options='-f nc')
           plot(s[0,:,:],ofile='org',title='org')
           sfmo = cdo.sellonlatbox(0,30,0,90, input="-fillmiss -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
           plot(sfmo[0,:,:],ofile='fm',title='fm')
           sfm = cdo.sellonlatbox(0,30,0,90, input="-fillmiss2 -chname,SO,s,TempO,t " + ifile,returnMaArray='s',options='-f nc')
           plot(sfm[0,:,:],ofile='fm2',title='fm2')
           for im in ['org.png','fm2.png','fm.png']:
             os.system("eog "+im+" &")

            

if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromTestCase(CdoTest)
    unittest.TextTestRunner(verbosity=2).run(suite)

# vim:sw=2
