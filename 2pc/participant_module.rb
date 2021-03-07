module ParticipantModule
  bootstrap do
    connect <~ [[TwoPcProtocol::COORDINATOR_ADDR, ip_port]]
  end

  bloom do
    vote_response <~ vote_request { |incoming| [TwoPcProtocol::COORDINATOR_ADDR, incoming.payload, true] }
    commit_ack <~ commit { |incoming| [TwoPcProtocol::COORDINATOR_ADDR, incoming.payload, incoming.commit_bool] }
    stdio <~ vote_request { |incoming| ["Voting for: #{incoming.payload}"] }
    stdio <~ commit { |incoming| ["Committing for: #{incoming.payload}"] }
  end
end