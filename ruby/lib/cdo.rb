require 'pp'

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
  State = {
    :debug       => false,
    :returnArray => false,
    :operators   => []
  }
  @@CDO = ENV['CDO'].nil? ? '/usr/bin/cdo' : ENV['CDO']

  # Since cdo-1.5.4 undocumented operators are given with the -h option. For
  # earlier version, they have to be provided manually
  @@undocumentedOperators = %w[anomaly beta boxavg change_e5lsm change_e5mask
    change_e5slm chisquare chvar cloudlayer cmd com command complextorect
    covar0 covar0r daycount daylogs del29feb delday delete deltap deltap_fl
    delvar diffv divcoslat dumplogo dumplogs duplicate eca_r1mm enlargegrid
    ensrkhistspace ensrkhisttime eof3d eof3dspatial eof3dtime export_e5ml
    export_e5res fc2gp fc2sp fillmiss fisher fldcovar fldrms fourier fpressure
    gather gengrid geopotheight ggstat ggstats globavg gp2fc gradsdes
    gridverify harmonic hourcount hpressure ifs2icon import_e5ml import_e5res
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

  private
  def Cdo.call(cmd)
    if (State[:debug])
      puts '# DEBUG ====================================================================='
      puts cmd
      puts '# DEBUG ====================================================================='
      puts IO.popen(cmd).read
    else
      system(cmd + ' 1>/dev/null 2>&1 ')
    end
  end
  def Cdo.run(cmd,ofile=nil,options='',returnArray=false)
    cmd = "#{@@CDO} -O #{options} #{cmd} "
    case ofile
    when $stdout
      cmd << " 2>/dev/null"
      return IO.popen(cmd).readlines.map {|l| l.chomp.strip}
    when nil
      ofile = Tempfile.new("Cdo.rb").path
    end
    cmd << "#{ofile}"
    call(cmd)
    if returnArray or State[:returnArray]
      Cdo.loadCdf unless State[:returnArray]
      return NetCDF.open(ofile)
    else
      return ofile
    end
  end
  def Cdo.loadCdf
    begin
      require "numru/netcdf"
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
  def Cdo.setReturnArray(value=true)
    if value
      Cdo.loadCdf
    end
    State[:returnArray] = value
  end
  def Cdo.unsetReturnArray
    setReturnArray(false)
  end
  def Cdo.returnArray
    State[:returnArray]
  end

  # test if @@CDO can be used
  def Cdo.checkCdo
    unless (File.exists?(@@CDO) and File.executable?(@@CDO))
      warn "Testing application #@@CDO is not available!"
      exit 1
    else
      puts "Using CDO: #@@CDO"
      puts IO.popen(@@CDO + " -V").readlines
    end
  end
  def Cdo.setCdo(cdo)
    puts "Will use #{cdo} instead of #@@CDO" if Cdo.debug
    @@CDO = cdo
    Cdo.getOperators(true)
  end

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
    State[:operators] = (help[help.index("Operators:")+1].split + @@undocumentedOperators).uniq
  end

  def Cdo.method_missing(sym, *args, &block)
    # args is expected to look like [opt1,...,optN,:in => iStream,:out => oStream] where
    # iStream could be another CDO call (timmax(selname(Temp,U,V,ifile.nc))
    puts "Operator #{sym.to_s} is called" if State[:debug]
    if getOperators.include?(sym.to_s)
      io = args.find {|a| a.class == Hash}
      args.delete_if {|a| a.class == Hash}
      if /(diff|info|show|griddes)/.match(sym)
        run(" -#{sym.to_s} #{io[:in]} ",$stdout)
      else
        opts = args.empty? ? '' : ',' + args.reject {|a| a.class == Hash}.join(',')
        run(" -#{sym.to_s}#{opts} #{io[:in]} ",io[:out],io[:options],io[:returnArray])
      end
    else
      warn "Operator #{sym.to_s} not found"
    end
  end

  #==================================================================
  # Addional operotors:
  #------------------------------------------------------------------
  def Cdo.boundaryLevels(args)
    ilevels         = Cdo.showlevel(:in => args[:in])[0].split.map(&:to_f)
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
      t.path
    else
      t = "_"+rand(@@N).to_s
      @@_tempfiles << t
      t
    end
  end
end
