require 'rake/clean'
require 'colorize'
require 'facets/string'
require 'pp'

CLEAN.include("**/*.pyc")
CLEAN.include("**/*.log")
CLEAN.include("**/*.log.[0-9]*")
CLEAN.include("{ruby,python}/*.{grb,nc,png,svg}")

PythonInterpreter = ENV.has_key?('PYTHON') ? ENV['PYTHON'] : 'python'
RubyInterpreter   = ENV.has_key?('RUBY')   ? ENV['RUBY']   : 'ruby'

String.disable_colorization = (not ENV.has_key?('NO_COLOR'))


@cdoPackages = {
  "clang@5.0.1" => ["cdo@1.9.0", "cdo@1.9.1", "cdo@1.9.2", "cdo@1.9.3"],
  "gcc@6.4.1"   => ["cdo@1.7.2", "cdo@1.8.2", "cdo@1.8.2", "cdo@1.9.0", "cdo@1.9.1", "cdo@1.9.2", "cdo@1.9.3"],
  "gcc@7.2.0"   => ["cdo@1.7.2", "cdo@1.8.2", "cdo@1.9.0", "cdo@1.9.1", "cdo@1.9.2", "cdo@1.9.3"]
}

def pythonTest(name: nil,interpreter: PythonInterpreter)
  cmd = "cd python; #{interpreter} test/test_cdo.py"
  cmd << " CdoTest.#{name}" unless name.nil?
  cmd
end
def rubyTest(name: nil,interpreter: RubyInterpreter, testFile: nil)
  testFile = 'test/test_cdo.rb' if testFile.nil?
  cmd = "cd ruby; #{interpreter} #{testFile}"
  cmd << " --name=#{name}" unless name.nil?
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

  # create regression tests for Ruby and Pythonwith different cdo version (managed by spack)
  desc "run regresssion for multiple CDO releases in #{lang}"
  task "test#{lang}Regression".to_sym, :name do |t,args|
    runTests = args.name.nil? ? "rake test#{lang}" : "rake test#{lang}[#{args.name}]"
    spackEnv = "$HOME/src/tools/spack/share/spack/setup-env.sh"
    @cdoPackages.each {|comp,cdoVersions|
      cdoVersions.each {|cdoVersion|
        cmd = [". #{spackEnv}" ,
               "spack load #{cdoVersion} %#{comp}",
               runTests,
               "spack unload #{cdoVersion} %#{comp}"].join(';')
        puts cmd.colorize(:blue) if ENV.has_key?('DEBUG')
        sh cmd
      }
    }
  end
  %w[2 3].each {|pythonRelease|
    desc "run regresssion for multiple CDO releases in #{lang}#{pythonRelease}"
    task "test#{lang}#{pythonRelease}Regression".to_sym, :name do |t,args|
      runTests = args.name.nil? \
        ? "rake test#{lang}#{pythonRelease}" \
        : "rake test#{lang}#{pythonRelease}[#{args.name}]"
      spackEnv = "$HOME/src/tools/spack/share/spack/setup-env.sh"
      cmd = [". #{spackEnv}" ,
             "for pkg in $(spack find -s cdo  | tail +2)",
             "  do echo $pkg; spack load ${pkg}",
             runTests,
             "  spack unload ${pkg} ",
             "done"].join(';')
      puts cmd.colorize(:blue) if ENV.has_key?('DEBUG')
      sh cmd
    end if 'Python' == lang
  }
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

desc "execute one/all lib-test(s) with ruby or the given env: RubyInterpreter"
task :testRubyLib, :name do |t,args|
  sh rubyTest(name: args.name,testFile: 'test/test_cdo_lib.rb')
end

task :checkRegression do |t|
    spackEnv = "$HOME/src/tools/spack/share/spack/setup-env.sh"
    @cdoPackages.each {|comp,cdoVersions|
      cdoVersions.each {|cdoVersion|
        cmd = [". #{spackEnv}" ,
               "spack load #{cdoVersion} %#{comp}",
               "cdo -V",
               "spack unload #{cdoVersion} %#{comp}"].join(';')
        puts cmd.colorize(:blue) if ENV.has_key?('DEBUG')
        sh cmd
      }
    }
end

task :default => :testRuby
