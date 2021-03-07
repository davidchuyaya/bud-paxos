require 'rubygems'
require 'bud'
require_relative '2pc_protocol'

class Participant
  include Bud
  include TwoPcProtocol

  def initialize(opts={})
    super
  end

  bootstrap do
    connect <~ [[COORDINATOR_ADDR, ip_port]]
  end

  bloom do
    vote_response <~ vote_request { |incoming| [COORDINATOR_ADDR, incoming.payload, true] }
    commit_ack <~ commit { |incoming| [COORDINATOR_ADDR, incoming.payload, incoming.commit_bool] }
    stdio <~ vote_request { |incoming| ["Voting for: #{incoming.payload}"] }
    stdio <~ commit { |incoming| ["Committing for: #{incoming.payload}"] }
  end
end

program = Participant.new(:stdin => $stdin)
program.run_fg