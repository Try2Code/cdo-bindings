load 'info.rb'
class CdoNG
  attr_reader :options, :cdo, :forceOutput
  attr_accessor :returnFalseOnError, :returnNilOnError, :debug, :logging, :logFile, :tempdir

  def initialize(executable: 'cdo',
                 returnFalseOnError: false,
                 returnNilOnError: false,
                 forceOutput: true,
                 env: {},
                 debug: false,
                 tempdir: Dir.tmpdir,
                 logging: false,
                 logFile: StringIO.new)

    @executable         = executable
    @returnFalseOnError = returnFalseOnError
    @returnNilOnError   = returnNilOnError
    @forceOutput        = forceOutput
    @env                = env
    @debug              = debug
    @tempdir            = tempdir
    @logging            = logging
    @logFile            = logFile

    @commands = []
    @operators = CdoInfo.operators(@executable)

  end
  def run(output: nil,
          returnArray: false,
          returnMaArray: false,
          force: true,
          env: {},
          debug: false)
    return true
  end
  def method_missing(sym, *args, **kwargs)
    operatorName = sym.to_s
    puts "Operator #{operatorName} is called" if @debug

    # exit eary on missing operator
    unless @operators.include?(operatorName)
      return false if @returnFalseOnError
      raise ArgumentError,"Operator #{operatorName} not found"
    end

    # check of kwargs, raise error on missing or unknown
    #   output is invalid
    #   options might be valid (special operatiors need options attached)
    #
    # append operator incl parameters
  end
end
