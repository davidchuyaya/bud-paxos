require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'
require_relative 'paxos_proposer_module'

class PaxosProposer
  include Bud
  include PaxosProtocol
  include PaxosProposerModule

  def initialize(id, opts={})
    @id = id
    super opts
  end
end

# Arguments: proposer ID (starting from 1)
id = ARGV[0].to_i
program = PaxosProposer.new(id, :stdin => $stdin, :ip => PaxosProtocol::LOCALHOST,
                            :port => PaxosProtocol::PROPOSER_START_PORT + id)
program.run_fg