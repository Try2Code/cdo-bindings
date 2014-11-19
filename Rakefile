PythonInterpreter = ENV.has_key?('PYTHON') ? ENV['PYTHON'] : 'python'

def pythonTest(name,interpreter: PythonInterpreter)
  cmd = "cd python; PYTHONPATH='.' #{interpreter} test/test_cdo.py"
  cmd << " CdoTest.#{name}" unless name.nil?
end

task :testPython2, :name do |t,args|
  sh pythonTest(args.name,interpreter: 'python2')
end
task :testPython3, :name do |t,args|
  sh pythonTest(args.name,interpreter: 'python3')
end
task :testPython, :name do |t,args|
  sh pythonTest(args.name)
end
