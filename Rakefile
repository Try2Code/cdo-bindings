require 'rake/clean'
require 'pp'

CLEAN.include("**/*.pyc")
CLEAN.include("**/*.log")
CLEAN.include("**/*.log.[0-9]*")
CLEAN.include("{ruby,python}/*.{grb,nc,png,svg}")

PythonInterpreter = ENV.has_key?('PYTHON') ? ENV['PYTHON'] : 'python'
RubyInterpreter   = ENV.has_key?('RUBY')   ? ENV['RUBY']   : 'ruby'

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
  fileExtension = {Ruby: 'rb',Python: 'py'}[lang.to_sym]
  desc "list #{lang} tests"
  task "list#{lang}".to_sym do
    File.open("#{lang.downcase}/test/test_cdo.#{fileExtension}").readlines.grep(/^ *def test/).map(&:strip).sort.each {|line|
      md = /def (test_*\w+)/.match(line)
      unless md.nil?
        puts md[1]
      end
    }
  end
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

task :default => :testRuby
