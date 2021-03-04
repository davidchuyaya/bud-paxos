module PaxosAcceptorModule
  bootstrap do
    acceptor_ballot_table <= [[0, 0]]
  end

  bloom do
    stdio <~ p1a { |incoming| ["p1a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"] }
    stdio <~ p2a { |incoming| ["p2a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, payload: #{incoming.payload}, slot: #{incoming.slot.to_s}"] }

    # process p1a
    p1b <~ (p1a * acceptor_ballot_table).pairs do |incoming, ballot|
      if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
        acceptor_ballot_table <- [[ballot.id, ballot.num]]
        acceptor_ballot_table <+ [[incoming.id, incoming.ballot_num]]
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, log.inspected] #TODO figure out how to send log
      else
        [incoming.proposer_client, ip_port, ballot.id, ballot.num]
      end
    end

    # process p2a
    p2b <~ (p2a * acceptor_ballot_table).pairs do |incoming, ballot|
      if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
        acceptor_ballot_table <- [[ballot.id, ballot.num]]
        acceptor_ballot_table <+ [[incoming.id, incoming.ballot_num]]
        log <+- [[incoming.slot, incoming.id, incoming.ballot_num, incoming.payload]]
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, incoming.slot]
      else
        [incoming.proposer_client, ip_port, ballot.id, ballot.num, incoming.slot]
      end
    end
  end
end
