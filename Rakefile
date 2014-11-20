PythonInterpreter = ENV.has_key?('PYTHON') ? ENV['PYTHON'] : 'python'

def pythonTest(name: nil,interpreter: PythonInterpreter)
  cmd = "cd python; PYTHONPATH='.' #{interpreter} test/test_cdo.py"
  cmd << " CdoTest.#{name}" unless name.nil?
  cmd
end

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
