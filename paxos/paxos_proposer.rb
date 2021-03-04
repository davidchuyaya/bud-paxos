require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'
require_relative 'paxos_proposer_module'

class PaxosProposer
  include Bud
  include PaxosProtocol
  include PaxosProposerModule

  def initialize(id, num_acceptors, opts={})
    @id = id
    @num_acceptors = num_acceptors
    super opts
  end
end

# Arguments: proposer ID (starting from 1), num acceptors
id = ARGV[0].to_i
num_acceptors = ARGV[1].to_i
program = PaxosProposer.new(id, num_acceptors, :stdin => $stdin, :ip => PaxosProtocol::LOCALHOST,
                            :port => PaxosProtocol::PROPOSER_START_PORT + id)
program.run_fg