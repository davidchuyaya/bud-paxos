require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'

class PaxosClient
  include Bud
  include PaxosProtocol

  def initialize(num_proposers, opts={})
    @num_proposers = num_proposers
    super opts
  end

  state do
    table :proposers, [:addr]
  end

  bootstrap do
    # connect to proposers
    for i in 1..@num_proposers
      proposer_addr = PaxosProtocol::LOCALHOST + ":" + (PaxosProtocol::PROPOSER_START_PORT + i).to_s
      proposers <= [[proposer_addr]]
      connect <~ [[proposer_addr, ip_port, 1, "client"]] # dummy value for id
    end
  end

  bloom do
    client_to_proposer <~ (proposers * stdio).pairs { |proposer, io| [proposer.addr, ip_port, io.line] }
    stdio <~ proposer_to_client { |incoming| [incoming.slot.to_s + ") " + incoming.payload] }
  end
end

# Arguments: ID, num proposers
num_proposers = ARGV[0].to_i
program = PaxosClient.new(num_proposers, :stdin => $stdin)
program.run_fg

