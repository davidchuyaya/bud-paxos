module PaxosClientModule
  bootstrap do
    # connect to proposers
    for i in 1..PaxosProtocol::NUM_PROPOSERS
      proposer_addr = "#{PaxosProtocol::LOCALHOST}:#{(PaxosProtocol::PROPOSER_START_PORT + i).to_s}"
      proposers <= [[proposer_addr]]
      connect <~ [[proposer_addr, ip_port, 1, "client"]] # dummy value for id
    end
  end

  bloom do
    client_to_proposer <~ (proposers * stdio).pairs { |proposer, io| [proposer.addr, ip_port, io.line] }
    stdio <~ proposer_to_client { |incoming| ["#{incoming.slot.to_s}) #{incoming.payload}"] }
  end
end
