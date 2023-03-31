class CdoNG
  def initialize(cdo: 'cdo',
                 returnFalseOnError: false,
                 returnNilOnError: false,
                 forceOutput: true,
                 env: {},
                 debug: false,
                 tempdir: Dir.tmpdir,
                 logging: false,
                 logFile: StringIO.new)
  end
  def run(output: nil,
          returnArray: false,
          returnMaArray: false,
          force: true,
          env: {},
          debug: false)
    return true
  end
end
