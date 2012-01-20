import unittest,os
from cdo import *

cdo = Cdo()

class CdoTest(unittest.TestCase):

    def testCDO(self):
        print(cdo.CDO)
        self.assertEqual('cdo',cdo.CDO)
        newCDO="/usr/bin/cdo"
        cdo.setCDO(newCDO)
        self.assertEqual(newCDO,cdo.CDO)
        cdo.setCDO('cdo')

    def testDbg(self):
        self.assertEqual(False,cdo.debug)
        cdo.debug = True
        self.assertEqual(True,cdo.debug)
        cdo.debug = False

    def testOps(self):
        self.assertIn("sinfov",cdo.operators)
        self.assertIn("for",cdo.operators)
        self.assertIn("mask",cdo.operators)
        self.assertIn("studentt",cdo.operators)

    def test_getOperators(self):
        for op in ['random','stdatm','info','showlevel','sinfo','remap','geopotheight','mask','topo','thicknessOfLevels']:
            if 'thicknessOfLevels' != op:
                self.assertIn(op,cdo.operators)
            else:
                self.assertIn(op,dir(cdo))

    def test_simple(self):
        s   = cdo.sinfov(input="-topo",options="-f nc")
        s   = cdo.sinfov(input="-remapnn,r36x18 -topo",options="-f nc")
        f   = 'ofile.nc'
        cdo.expr("'z=log(abs(topo+1))*9.81'",input="-topo",output = f,options="-f nc")
        s   = cdo.infov(input=f)
        cdo.stdatm("0",output=f,options="-f nc")

    def test_info(self):
        levels = cdo.showlevel(input = "-stdatm,0")
        info   = cdo.sinfo(input = "-stdatm,0")
        print(levels)
        self.assertEqual([0,0],map(float,levels))
        self.assertEqual("File format: GRIB",info[0])

    def test_bndLevels(self):
        ofile = MyTempfile().path()
        cdo.stdatm(25,100,250,500,875,1400,2100,3000,4000,5000,output = ofile,options = "-f nc")
        self.assertEqual([0, 50.0, 150.0, 350.0, 650.0, 1100.0, 1700.0, 2500.0, 3500.0, 4500.0, 5500.0],
                    cdo.boundaryLevels(input = "-selname,T " + ofile))
        self.assertEqual([50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0, 1000.0, 1000.0, 1000.0],
                     cdo.thicknessOfLevels(input = ofile))

    def test_CDO_options(self):
        names = cdo.showname(input = "-stdatm,0",options = "-f nc")
        self.assertEqual(["P T"],names)
        ofile = MyTempfile().path()
        cdo.topo(output = ofile,options = "-z szip")
        self.assertEqual(["GRIB SZIP"],cdo.showformat(input = ofile))

    def test_chain(self):
        ofile     = MyTempfile().path()
        cdo.setname("veloc", input=" -copy -random,r1x1",output = ofile,options = "-f nc")
        self.assertEqual(["veloc"],cdo.showname(input = ofile))

    def test_diff(self):
        diffv = cdo.diffn(input = "-random,r1x1 -random,r1x1")
        self.assertEqual(diffv[1].split(' ')[4],"random")
        self.assertEqual(diffv[1].split(' ')[-1],"0.53060")
        diff  = cdo.diff(input = "-random,r1x1 -random,r1x1")
        self.assertEqual(diff[1].split(' ')[-1],"0.53060")

    def test_returnArray(self):
        ofile = MyTempfile().path()
        press = cdo.stdatm("0",output=ofile,options="-f nc")
        self.assertEqual(ofile,press)
        press = cdo.stdatm("0",options="-f nc",returnArray=True).var("P").get()
        self.assertEqual(1013.25,press.min())
        press = cdo.stdatm("0",output=ofile,options="-f nc")
        self.assertEqual(ofile,press)
        cdo.setReturnArray()
        outfile = 'test.nc'
        press = cdo.stdatm("0",output=outfile,options="-f nc").var("P").get()
        self.assertEqual(1013.25,press.min())
        cdo.unsetReturnArray()
        press = cdo.stdatm("0",output=outfile,options="-f nc")
        self.assertEqual(press,outfile)
        press = cdo.stdatm("0",output=outfile,options="-f nc",returnArray=True).var("P").get()
        self.assertEqual(1013.25,press.min())
        print("press = "+press.min().__str__())
        cdo.unsetReturnArray()
        press = cdo.stdatm("0",output=ofile,options="-f nc")
        self.assertEqual(ofile,press)


    def test_combine(self):
        o   = MyTempfile().path()
        stdatm = cdo.stdatm("0",options = "-f nc",output=o)
        self.assertEqual(o,stdatm)
        o   = MyTempfile().path()
        o_  = MyTempfile().path()
        sum = cdo.fldsum(input = stdatm,output = o)
        sum = cdo.fldsum(input = stdatm)
        sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"))
        sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"),returnArray=True)
        self.assertEqual(288.0,sum.var("T").get().min())

    def test_cdf(self):
        self.assertNotIn("cdf",cdo.__dict__)
        cdo.setReturnArray()
        self.assertIn("cdf",cdo.__dict__)
        cdo.setReturnArray(False)
        sum = cdo.fldsum(input = cdo.stdatm("0",options="-f nc"),returnArray=True)
        self.assertEqual(1013.25,sum.var("P").get().min())
        cdo.unsetReturnArray()

    def test_thickness(self):
        levels            = "25 100 250 500 875 1400 2100 3000 4000 5000".split(' ')
        targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
        self.assertEqual(targetThicknesses, cdo.thicknessOfLevels(input = "-selname,T -stdatm,"+ ','.join(levels)))

    if 'thingol' == os.popen('hostname').read().strip():
        def testCall(self):
            print cdo.sinfov(input='/home/ram/data/icon/oce.nc')

        def test_verticalLevels(self):
            iconpath          = "/home/ram/src/git/icon/grids"
            # check, if a given input files has vertival layers of a given thickness array
            targetThicknesses = [50.0,  100.0,  200.0,  300.0,  450.0,  600.0,  800.0, 1000.0, 1000.0, 1000.0]
            ifile             = '/'.join([iconpath,"ts_phc_annual-iconR2B04-L10_50-1000m.nc"])
            self.assertEqual(["25 100 250 500 875 1400 2100 3000 4000 5000",
                              "25 100 250 500 875 1400 2100 3000 4000 5000"],cdo.showlevel(input = ifile))
            thicknesses = cdo.thicknessOfLevels(input = ifile)
            self.assertEqual(targetThicknesses,thicknesses)

        def test_readCdf(self):
            input= "-settunits,days  -setyear,2000 -for,1,4"
            cdfFile = cdo.copy(options="-f nc",input=input)
            cdf     = cdo.readCdf(cdfFile)
            self.assertEqual(['lat','lon','for','time'],cdf.variables().keys())

if __name__ == '__main__':
    unittest.main()

# vim:sw=4
