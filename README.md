# Cdo.{rb,py} - Use Ruby/Python to access the power of CDO

This package contains the module Cdo, which implements a ruby/python style
access to the Climate Data operators CDO. CDO is a command line tool for
processing gridded data. Its main focus if climate data, but it can by used
for other purposes to. It accepts input formats GRIB1, GRIB2, NetCDF and
several Fortran binary formats.

[Why the .... should I use this???](https://code.zmaw.de/projects/cdo/wiki/Cdo%7Brbpy%7D#Why-the-)

## Installation

### Ruby Installation

Download and install cdo.rb via rubygems:

    gem install cdo

### Python Installation

Download and install cdo.py via pypi:

    pip install cdo

### Requirements

Cdo.{rb,py} requires a working CDO binary, but has not special requirement to
ruby or python. Both python2 and python3 are fully supported. The class
interface of the ruby version requires at least ruby-2.x, the module interface
(available in 'cdo_lib') works with ruby-1.9.x, too. For returning
multi-dimensional arrays (numpy for python, narray for ruby) addtional
netcdf-io modules are needed. These are scipy/netcdf4 for python and
ruby-netcdf for ruby.

## Usage

### Run operators

The Ruby module can be used directly after loading it. For python and the ruby
class interface an instance has to be created first

```ruby
    cdo = Cdo.new
```
```python
    cdo = Cdo()
```

Please check the documentation for constructor paramaters

*   File information
```ruby
        Cdo.infov(:input => ifile)       #ruby, module interface
        Cdo.showlevels(:input => ifile)

        cdo.infov(input: ifile)          #ruby-2.*, class interface
        cdo.showlevels(input: ifile)

```
```python
        cdo.infov(input=ifile)         #python
        cdo.showlevels(input=ifile)
```

*   Operators with user defined regular output files
```ruby
        Cdo.timmin(:input => ifile ,:output => ofile) #ruby
        cdo.timmin(input: ifile ,output: ofile)       #ruby-2.*, class interface
```
```python
        cdo.timmin(input = ifile,output = ofile)      #python
```

*   Use temporary output files
```ruby
        tminFile = Cdo.timmin(:input => ifile) #ruby
        tminFile = cdo.timmin(input: ifile)    #ruby-2.*, class interface
```
```python
        tminFile = cdo.timmin(input = ifile) #python
```

*   Operators with options
```ruby
        Cdo.remap([gridfile,weightfile],:input => ifile, :output => ofile) #ruby
        cdo.remap([gridfile,weightfile],input:   ifile, output:   ofile)   #ruby-2.x, class interface
```
```python
        cdo.remap([gridfile,weightfile],input => ifile, output => ofile) #python
```

*   logging
```ruby
        cdo = Cdo.new(logging: true, logFile: 'cdo_commands.log') #ruby-2.x
```
```python
        cdo = Cdo(logging=True, logFile='cdo_commands.log')       #python
```

*   Set global CDO options

        Cdo.copy(:input => ifile, :output => ofile,:options => "-f nc4") (ruby)
        cdo.copy(input:  ifile, output:  ofile,options:  "-f nc4")     (ruby-2.x, class interface)
        cdo.copy(input = ifile, output = ofile,options = "-f nc4")     (python)

*   Set environment variables

        Cdo.splitname(:input => ifile.join(' '), :output => 'splitTag',:env {'CDO_FILE_SUFFIX' => '.nc'}) (ruby)
        or Cdo.env = {'CDO_FILE_SUFFIX' => '.nc'}
        xdo.splitname(input:    ifile.join(' '), output:    'splitTag',env: {'CDO_FILE_SUFFIX' => '.nc'}) (ruby-2.x, class interface)
        or Cdo.env = {'CDO_FILE_SUFFIX' => '.nc'}
        cdo.splitname(input = ' '.join(ifiles) ,  output =  'splitTag', env={"CDO_FILE_SUFFIX": ".nc"})   (python)
        or Cdo.env = {'CDO_FILE_SUFFIX': '.nc'}

*   Return multi-dimension arrrays
```
        temperatures = Cdo.fldmin(:input => ifile,:returnArray => true).var('T').get   (rb, version < 1.2.0)
        temperatures = cdo.fldmin(input = ifile,returnArray = True).variables['T'][:] (py, version < 1.2.0)

        temperatures = Cdo.fldmin(:input => ifile,:returnCdf => true).var('T').get    (rb, version >= 1.2.0)
        temperatures = cdo.fldmin(input = ifile,returnCdf = True).variables['T'][:]   (py, version >= 1.2.0)*

        temperatures = Cdo.fldmin(:input => ifile,:returnArray => 'T')                (rb, version >= 1.2.0)
        temperatures = cdo.fldmin(input = ifile,returnArray = 'T')                   (py, version >= 1.2.0)
```


*) If you use scipy >= 0.14 as netcdf backend, you have use following code
instead to avoid possible segmentation faults:

    cdf = cdo.fldmin(input = ifile,returnCdf = True)
    temperatures = cdf.variables['T'][:]

More examples can be found in test/cdo-examples.rb and [on the homepage](https://code.zmaw.de/projects/cdo/wiki/Cdo%7Brbpy%7D)

### Tempfile helpers

Cdo.{rb,py} includes a simple tempfile wrapper, which make live easier, when
write your own scripts

## Support, Issues, Bugs, ...

Please use the forum or ticket system of CDOs official web page:
http://code.zmaw.de/projects/cdo

## Changelog
*   next:
        - return arrays/lists of output files, which are created by split* operators
          suggestion from Karl-Hermann Wieners :ocean:

*   1.3.2 [2016-10-24]
        - improvened stdout/stderr handling, thx to jvegasbsc

*   1.3.1
        - fix environment handling per call (ruby version)

*   1.3.0
        - require ruby-2.*
        - support for upcomming CDO release 1.7.1
        - improve loggin for ruby
        - introduce logging for python
        - unicode bugfix - thanks to Sebastian Illing (illing2005) [python-only]

*   1.2.7
        - Added class interface for ruby version 2.x, mainly for thread safety

*   1.2.6
        - bugfix for autocompletion in interactive usage [python-only]

*   1.2.5
        - bugfix for environment handling (Thanks philipp) [python-only]
        - add logging [ruby-only]

*   1.2.4
        - support python3: Thanks to @jhamman
        - bugfix for scipy: Thanks to @martinclaus
        - docu fixes: Thanks to @guziy
        - allow environment setting via call and object construction (see test_env in test_cdo.py)

*   1.2.3
        - bugfix release: adjust library/feature check to latest cdo-1.6.2  release

*   1.2.2
        - allow arrays in additions to strings for input argument
        - add methods for checking the IO libraries of CDO and their versions
        - optionally return None on error (suggestion from Alex Loew, python only)

*   1.2.1:
        - new return option: Masked Arrays
          if the new keyword returnMaArray is given, its value is taken as variable
          name and a masked array wrt to its FillValues is returned
          contribution for python by Alex Loew
        - error handling: return stderr in case of non-zero return value + raise exception
          contribution for python from Estanislao Gonzalez
        - autocompletion and built-in documentation through help() for interactive use
          contribution from Estanislao Gonzalez [python]
        - Added help operator for displaying help interactively [ruby]

*   1.2.0: API change:
        - Ruby now uses the same keys like the python interface, i.e. :input and :output
          instead of :in and :out
        - :returnArray will accept a variable name, for which the multidimesional
          array is returned

*   1.1.0: API change:
        - new option :returnCdf : will return the netcdf file handle, which was formerly
          done via :returnArray
        - new options :force : if set to true the cdo call will be run even if the given
          output file is presen, default: false


## [Thanks to all contributors!](https://github.com/Try2Code/cdo-bindings/graphs/contributors)


## License

Cdo.{rb,py} makes use of the GPLv2 License, see COPYING

---

# Other stuff

Author
:   Ralf Mueller <stark.dreamdetective@gmail.com>
Requires
:   CDO version 1.5.x or newer
License
:   Copyright 2011-2017 by Ralf Mueller Released under GPLv2 license.  See the
    COPYING file included in the distribution.

