require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'
require_relative 'paxos_client_module'

class PaxosClient
  include Bud
  include PaxosProtocol
  include PaxosClientModule

  def initialize(num_proposers, opts={})
    @num_proposers = num_proposers
    super opts
  end
end

# Arguments: ID, num proposers
num_proposers = ARGV[0].to_i
program = PaxosClient.new(num_proposers, :stdin => $stdin)
program.run_fg

