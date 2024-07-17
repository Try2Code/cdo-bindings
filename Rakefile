require 'rake/clean'
require 'colorize'
require 'facets/string'
require 'pp'

CLEAN.include("**/*.pyc")
CLEAN.include("**/*.log")
CLEAN.include("**/*.log.[0-9]*")
CLEAN.include("{ruby,python}/*.{grb,nc,png,svg}")
CLEAN.include("python/tempPy*")
CLEAN.include("ruby/tempRb*")
CLEAN.include("ruby/doc")
CLEAN.include("/tmp/Cdorb*")
CLEAN.include("python/test/tempPy*")
CLEAN.include("python/tempPy_*")
CLEAN.include("python/__pycache__")
CLEAN.include("python/test/__pycache__")
CLEAN.include("python/test/*bla")
CLEAN.include("python/{A,B}_*")
CLEAN.include("doc")
CLEAN.include("**/*.orig")
CLEAN.include("python/dist")
CLEAN.include("python/cdo.egg-info")
CLEAN.include("*.bla")
CLEAN.include("const.grb")

PythonInterpreter = ENV.has_key?('PYTHON') ? ENV['PYTHON'] : 'python'
RubyInterpreter   = ENV.has_key?('RUBY')   ? ENV['RUBY']   : 'ruby'
SpackEnv          = "$HOME/src/spack/share/spack/setup-env.sh"

String.disable_colorization = (ENV.has_key?('NO_COLOR'))
@debug                      = (ENV.has_key?('DEBUG'))

# following test should not be run in parallel with other tests
SERIAL_TESTS = %w[test_system_tempdir]

spackEnvCommand = lambda {|modhash|
  lambda {|command| [". #{SpackEnv}" ,
                     "spack load /#{modhash}",
                     command,
                     "spack unload /#{modhash}"].join(';')
  }
}

def getCdoPackagesFromSpack
  # list possible cdo modules provided by spack
  info = IO.popen([". #{SpackEnv}" ,
                   'spack find -lp cdo | grep cdo'].join(';')).readlines#.map(&:chomp).map(&:split).transpose
  puts info
# retval = {
#   hash:    info[0],
#   version: info[1],
#   path:    info[2],
# }
  return info #retval
end

desc "run each CDO binary from the regression tests"
task :checkRegression do |t|
  info = getCdoPackagesFromSpack
  info[:hash].each_with_index {|spackHash,i|
    puts info[:version][i].colorize(:green)
    sh spackEnvCommand[spackHash]["cdo -V"]
  }
end
desc "list spack modules available for regression testing"
task :listRegressionModules do |t|
  pp getCdoPackagesFromSpack[:version]
end

def pythonTest(name: nil,interpreter: PythonInterpreter)
  cmd = "cd python; #{interpreter} test/test_cdo.py"
  cmd << " CdoTest.#{name}" unless name.nil?
  cmd
end
def rubyTest(name: nil,interpreter: RubyInterpreter, testFile: nil)

  testFile = 'test/test_cdo.rb' if testFile.nil?

  # Run everything but the test that need serial execution
  cmd = "cd ruby; #{interpreter} #{testFile}"
  cmd << " --name=#{name}" unless name.nil?

  if name.nil? then
    SERIAL_TESTS.each {|test| cmd << " --exclude #{test}"}

    # now the rest if the whole suite supposed to be run
    SERIAL_TESTS.each {|test|
      cmd << "; #{interpreter} #{testFile} --name=#{test}"
    }
  end

  cmd
end


%w[Ruby Python].each {|lang|
  # create target for listing all tests for a given language
  fileExtension = {Ruby: 'rb',Python: 'py'}[lang.to_sym]
  desc "list #{lang} tests"
  task "list#{lang}Test".to_sym do
    File.open("#{lang.downcase}/test/test_cdo.#{fileExtension}").readlines.grep(/^ *def test/).map(&:strip).sort.each {|line|
      md = /def (test_*\w+)/.match(line)
      unless md.nil?
        puts md[1]
      end
    }
  end

  desc "test for correct tempfile deletion (#{lang})"
  task "test#{lang}_tempfiles".to_sym do |t|
    # make sure no other testing process has already created cdo-tempfile
    unless Dir.glob("/tmp/Cdo*").empty? then
      warn "Cannot run temp file test - target dir /tmp is no empty"
      exit(1)
    end
    sh "rake test#{lang}"

    unless Dir.glob("/tmp/Cdo*").empty? then
      warn "Found remaining temfiles!"
      exit(1)
    end
  end

  # create regression tests for Ruby and Pythonwith different cdo version (managed by spack)
  desc "run regresssion for multiple CDO releases in #{lang}"
  task "test#{lang}Regression".to_sym, :name do |t,args|
    runTests = args.name.nil? ? "rake test#{lang}" : "rake test#{lang}[#{args.name}]"
    spackInfo = getCdoPackagesFromSpack
    spackInfo[:hash].each_with_index {|spackModule,i|
      cmd = spackEnvCommand[spackModule][runTests]
      puts "#{spackInfo[:version][i]}(#{spackModule.colorize(:green)})"
      sh cmd
    }
  end
  %w[2 3].each {|pythonRelease|
    desc "run regresssion for multiple CDO releases in #{lang}#{pythonRelease}"
    task "test#{lang}#{pythonRelease}Regression".to_sym, :name do |t,args|
      runTests = args.name.nil? \
        ? "rake test#{lang}#{pythonRelease}" \
        : "rake test#{lang}#{pythonRelease}[#{args.name}]"
      getCdoPackagesFromSpack[:hash].each {|spackModule|
        cmd = spackEnvCommand[spackModule][runTests]
        puts spackModule.split.last.colorize(:green)
        sh cmd
      }
    end
    desc "test for correct tempfile deletion (#{lang}#{pythonRelease})"
    task "test#{lang}#{pythonRelease}_tempfiles".to_sym do |t|
      # make sure no other testing process has already created cdo-tempfile
      unless Dir.glob("/tmp/Cdo*").empty? then
        warn "Cannot run temp file test - target dir /tmp is no empty"
        exit(1)
      end
      sh "rake test#{lang}#{pythonRelease}"
      unless Dir.glob("/tmp/Cdo*").empty? then
        warn "Found remaining temfiles!"
        exit(1)
      end
    end
  } if 'Python' == lang
}

desc "execute one/all test(s) with python2"
task :testPython2, :name do |t,args|
  sh pythonTest(name: args.name,interpreter: 'python2')
end

desc "execute one/all test(s) with python3"
task :testPython3, :name do |t,args|
  sh pythonTest(name: args.name,interpreter: 'python3')
end

desc "execute one/all test(s) with python or the given env: PythonInterpreter"
task :testPython, :name do |t,args|
  sh pythonTest(name: args.name)
end

desc "execute one/all test(s) with ruby or the given env: RubyInterpreter"
task :testRuby, :name do |t,args|
  sh rubyTest(name: args.name)
end

task :default => :testRuby
