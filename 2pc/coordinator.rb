require 'rubygems'
require 'bud'
require_relative '2pc_protocol'
require_relative 'coordinator_module'

class Coordinator
  include Bud
  include TwoPcProtocol
  include CoordinatorModule

  def initialize(opts={})
    super
  end
end

program = Coordinator.new(:stdin => $stdin, :ip => TwoPcProtocol::LOCALHOST,
                            :port => TwoPcProtocol::COORDINATOR_PORT)
program.run_fg
