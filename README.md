# Cdo.{rb,py} - Use Ruby/Python to access the power of CDO

[![Build Status](https://travis-ci.org/Try2Code/cdo-bindings.svg?branch=master)](https://travis-ci.org/Try2Code/cdo-bindings) (Ruby 2.x/Python 2.7/Python 3.x)

Welcome to the scripting interfaces of [CDO](https://code.zmaw.de/projects/cdo/wiki)!
This repository contains interfaces for [Ruby](http://www.ruby-lang.org) and [Python](https://www.python.org). If you are not sure, wether this is useful or not, please have a look at:
[Why the .... should I use this???](https://code.zmaw.de/projects/cdo/wiki/Cdo%7Brbpy%7D#Why-the-)

## Installation

Releases are distributed via [pypi](https://pypi.org/project/cdo) and [rubygems](https://rubygems.org/gems/cdo):

*  Ruby
```
    gem install cdo (--user-install)
```
*  Python
```
    pip install cdo (--user)
```

### Requirements

Cdo.{rb,py} requires a working CDO binary and Ruby 2.x or Python 2.7/3.x

Multi-dimensional arrays (numpy for python, narray for ruby) require addtional
netcdf-io modules. These are [scipy](https://docs.scipy.org/doc/scipy/reference/io.html) or [python-netcdf4](https://pypi.python.org/pypi/netCDF4) for python and
[ruby-netcdf](https://rubygems.org/gems/ruby-netcdf) for ruby. Because scipy has some difficulties with netcdf, I strongly recommend python-netCDF4.

Thx to Alexander Winkler there is also an IO option for XArray.

## Usage

You can find a lot of examples in the unit tests for both languages. Here are the direct links to the [ruby tests](https://github.com/Try2Code/cdo-bindings/blob/master/ruby/test/test_cdo.rb) and the [python tests](https://github.com/Try2Code/cdo-bindings/blob/master/python/test/test_cdo.py).

The following describes the basic features for both languages

### Run operators

Befor calling operators, you have to create an object first:

```ruby
    cdo = Cdo.new   #ruby
```
```python
    cdo = Cdo()     #python
```

Please check the documentation for constructor paramaters. I try to have equal interfaces in both languages for all public methods.

### Choose CDO binary

By default the cdo-bindings use the 'cdo' binary found in your $PATH variable. To change that, you can

* load a module before calling your script(```module command``` or another package manager like ```conda``` or ```spack```)
* use the CDO environment variable to set the path to be used
* use the python/ruby method ```cdo.setCdo('/path/to/the/CDO/executable/you/want')```. By this technique you can create different objects for different CDO versions.

### Debugging

For debugging purpose, both interfaces provide a "debug" attribute. If it is set to a boolian true, the complete commands and the return values will be printed during execution

```ruby
    cdo.debug = true    #ruby
```
```python
    cdo.debug = True    #python
```

The default is false of cause.

#### File information
```ruby
    cdo.infov(input: ifile)        #ruby
    cdo.showlevels(input: ifile)

```
```python
    cdo.infov(input=ifile)         #python
    cdo.showlevels(input=ifile)
```

#### Operators with user defined regular output files
```ruby
    cdo.timmin(input: ifile ,output: ofile)       #ruby
```
```python
    cdo.timmin(input = ifile,output = ofile)      #python
```
By default the return value of each call is the name of the output files (no matter if its a temporary file or not)

#### Use temporary output files
If the output key is left out, one or more (depending on the operator) temporary files are generated and used as return value(s). In a regular script or a regularly closed interactive session, these files are removed at the end automatically.

```ruby
    tminFile = cdo.timmin(input: ifile)  #ruby
```
```python
    tminFile = cdo.timmin(input = ifile) #python
```
However these tempfiles remain if the session/script is killed with SIGKILL or if the bindings are used via Jupyter notebooks. Those session are usually long lasting and the heavy usage if tempfiles can easily fill the system tempdir - your system will become unusable then.
The bindings offer two ways to cope with that
* Set another directory for storing tempfiles with a constructor option and remove anything left in there when you experienced a crash or something like this
```python
   cdo = Cdo(tempdir=tempPath)      #python
   cdo = Cdo.new(tempdir: tempPath) #ruby
```
* remove all tempfiles created by this or former usage of the cdo-bindings belonging to your current Unix-user with (taking into account user-defined ```tempdir``` from above
```
   cdo.cleanTempDir() #python
   cdo.cleanTempDir   #ruby
```
   
#### Operators with parameter
```ruby
    cdo.remap([gridfile,weightfile],input:   ifile, output: ofile)   #ruby
```
```python
    cdo.remap([gridfile,weightfile],input => ifile, output => ofile) #python
```

#### logging
```ruby
    cdo = Cdo.new(logging: true, logFile: 'cdo_commands.log') #ruby
```
```python
    cdo = Cdo(logging=True, logFile='cdo_commands.log')       #python
```

#### Set global CDO options
```ruby
    cdo.copy(input:  ifile, output:  ofile,options:  "-f nc4")     #ruby
```
```python
    cdo.copy(input = ifile, output = ofile,options = "-f nc4")     #python
```

#### Set environment variables
```ruby
    cdo.splitname(input: ifile.join(' '),
                  output: 'splitTag',
                  env: {'CDO_FILE_SUFFIX' => '.nc'}) #or
    cdo.env = {'CDO_FILE_SUFFIX' => '.nc'}
```
```python
    cdo.splitname(input = ' '.join(ifiles),
                  output =  'splitTag', 
                  env={"CDO_FILE_SUFFIX": ".nc"})   #or
    cdo.env = {'CDO_FILE_SUFFIX': '.nc'}
```

#### Return multi-dimension arrrays
```ruby
    t = cdo.fldmin(:input => ifile,:returnArray => true).var('T').get  #rb, version <  1.2.0
    t = cdo.fldmin(:input => ifile,:returnCdf => true).var('T').get    #rb, version >= 1.2.0
    t = cdo.fldmin(:input => ifile,:returnArray => 'T')                #rb, version >= 1.2.0
```
```python
    t = cdo.fldmin(input = ifile,returnArray = True).variables['T'][:] #py, version <  1.2.0
    t = cdo.fldmin(input = ifile,returnCdf = True).variables['T'][:]   #py, version >= 1.2.0
    t = cdo.fldmin(input = ifile,returnArray = 'T')                    #py, version >= 1.2.0
```

Other options are so-called _masked arrays_ (use ```returnMaArray```) for ruby and python and XArray/XDataset for python-only: use ```returnXArray``` or ```returnXDataset``` for that.

*) If you use scipy >= 0.14 as netcdf backend, you have to use following code
instead to avoid possible segmentation faults:
```python
    cdf = cdo.fldmin(input = ifile,returnCdf = True)
    temperatures = cdf.variables['T'][:]
```
More examples can be found in test/cdo-examples.rb and [on the
homepage](https://code.zmaw.de/projects/cdo/wiki/Cdo%7Brbpy%7D)

### Avoid re-processing

If you do not want to re-compute files, you can set

*  the instance attribute 'forceOutput' to false: this will effect all later
   call of that instance **or**
*  the operator option 'forceOutput' to false: this will only effect this
   operator call of this instance

For more information, please have a look at the unit tests.

## Support, Issues, Bugs, ...

Please use the forum or ticket system of CDOs official web page:
http://code.zmaw.de/projects/cdo

## Changelog
* **1.5.0** API change :
  - simplify the interface:
    - remove returnCdf from constructor, only use it with operator calls
    - remove methods setReturnArray/unsetReturnArray: I fear it's not used anyway, but 'returnArray' in each call
    - remove the optional dependency to scipy since it offers less functionality than netCDF4 and just blows up the code
    - new attributes: hasNetcdf, hasXArray for checking for the respective support
    - fix for cdo-1.9.6: allow non-zero return code for diff operators
* **1.4.0** API change :
  - the ```operators``` atribute is no longer a list, but a dict (python) or hash (ruby) holding the number of output streams as value
  - finally fix #16 (missing tempfile generation for more than one output streams)
  - fix #19 (thx @pgierz for the input)
* **1.3.6**: 
  - bugfix for non-finding the CDO binary on some systems
  - fix hasCdo (py)
  - add hasCdo (rb)
* **1.3.5**:
  - read/write support for XArray datasets - thx to @pinplex!
  - **drop ruby support for 1.9 and older**
  - **remove module interface from the ruby version**
* **1.3.3**:
  - return arrays/lists of output files, which are created by split* operators
    suggestion from Karl-Hermann Wieners :ocean:
    **NOTE**: __this is done by simple globbing! Any other files with the appropriate name will be included in the list!__
  - use [six](https://pypi.python.org/pypi/six) for python2 and 3 compatibility (thanks to @jvegasbsc)
  - drop full support of CDO version older then 1.5.4: undocumented operators
    in these version will not be callable
  - new keyword for operators which write to stdout: autoSplit. When set, each
    line will be split with the given value of the keyword to avoid the need
    for manual splitting. Nested return arrays of (outer) size 1 are flattened.
    See #11, thx to @beatorizu
* **1.3.2**
  - improvened stdout/stderr handling, thx to jvegasbsc
* **1.3.1**
  - fix environment handling per call (ruby version)
* **1.3.0**
  - require ruby-2.*
  - support for upcomming CDO release 1.7.1
  - improve loggin for ruby
  - introduce logging for python
  - unicode bugfix - thanks to Sebastian Illing (illing2005) [python-only]
* **1.2.7**
  - Added class interface for ruby version 2.x, mainly for thread safety
* **1.2.6**
  - bugfix for autocompletion in interactive usage [python-only]
* **1.2.5**
  - bugfix for environment handling (Thanks philipp) [python-only]
  - add logging [ruby-only]
* **1.2.4**
  - support python3: Thanks to @jhamman
  - bugfix for scipy: Thanks to @martinclaus
  - docu fixes: Thanks to @guziy
  - allow environment setting via call and object construction (see test_env in test_cdo.py)
* **1.2.3**
  - bugfix release: adjust library/feature check to latest cdo-1.6.2  release
* **1.2.2**
  - allow arrays in additions to strings for input argument
  - add methods for checking the IO libraries of CDO and their versions
  - optionally return None on error (suggestion from Alex Loew, python only)
* **1.2.1**
  - new return option: Masked Arrays
    if the new keyword returnMaArray is given, its value is taken as variable
    name and a masked array wrt to its FillValues is returned
    contribution for python by Alex Loew
  - error handling: return stderr in case of non-zero return value + raise exception
    contribution for python from Estanislao Gonzalez
  - autocompletion and built-in documentation through help() for interactive use
    contribution from Estanislao Gonzalez [python]
  - Added help operator for displaying help interactively [ruby]
* **1.2.0** API change:
  - Ruby now uses the same keys like the python interface, i.e. :input and :output
    instead of :in and :out
  - :returnArray will accept a variable name, for which the multidimesional
    array is returned
* **1.1.0** API change:
  - new option :returnCdf : will return the netcdf file handle, which was formerly
    done via :returnArray
  - new options :force : if set to true the cdo call will be run even if the given
    output file is presen, default: false

---

## [Thanks to all contributors!](https://github.com/Try2Code/cdo-bindings/graphs/contributors)

## License

Cdo.{rb,py} makes use of the GPLv2 License, see COPYING
