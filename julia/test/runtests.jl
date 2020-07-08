# {{{ some steps before
# import Pkg
# Pkg.add("PyCall")
# }}}

# basic trick: use the PyCall module
using PyCall
pycdo = pyimport("cdo")
cdo = pycdo.Cdo()

print(cdo.topo())

numpy_data = cdo.topo(;returnArray="topo")
#print(numpy_data)

xarray_data = cdo.topo(;returnXArray="topo")
#print(xarray_data)

# chains
masked_data = cdo.setrtomiss(-100000,0;input="-expr,'logTopo=log(abs(topo)+0.1)' -topo,r10x10", returnArray="logTopo")
print(masked_data)
