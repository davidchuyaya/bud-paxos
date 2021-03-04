require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'
require_relative 'paxos_acceptor_module'

class PaxosAcceptor
  include Bud
  include PaxosProtocol
  include PaxosAcceptorModule

  def initialize(opts={})
    super opts
  end
end

# Arguments: acceptor ID (starting from 1)
id = ARGV[0].to_i
program = PaxosAcceptor.new(:stdin => $stdin, :ip => PaxosProtocol::LOCALHOST,
                            :port => PaxosProtocol::ACCEPTOR_START_PORT + id.to_i)
program.run_fg
