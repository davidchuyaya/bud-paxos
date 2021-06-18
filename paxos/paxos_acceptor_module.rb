module PaxosAcceptorModule
  bootstrap do
    acceptor_ballot_table <= [[0, 0]]
    log <= [[0, 1, 1, "hi"]]
  end

  bloom do
    stdio <~ p1a { |incoming| ["p1a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"] }
    stdio <~ p2a { |incoming| ["p2a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, payload: #{incoming.payload}, slot: #{incoming.slot.to_s}"] }

    acceptor_ballot_table <= p1a { |incoming| [incoming.id, incoming.ballot_num] }
    acceptor_ballot_table <= p2a { |incoming| [incoming.id, incoming.ballot_num] }
    # update ballot to whatever largest value we get (partial order)
    max_acceptor_ballot <= acceptor_ballot_table.group([:id, :num], max(:num))
                                                .group([:num], max(:id)) { |num, id| [id, num] }

    # TODO reduce concurrency in processing; must update acceptor_ballot_table before p1b or p2b responses
    # Then we can also remove the if statements and just return the current max ballot

    # process p1a
    p1b <~ (p1a * max_acceptor_ballot).pairs do |incoming, ballot|
      if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, incoming.ballot_num, log.inspected]
      else
        [incoming.proposer_client, ip_port, ballot.id, ballot.num, incoming.ballot_num, log.inspected]
      end
    end

    # process p2a
    p2b <~ (p2a * max_acceptor_ballot).pairs do |incoming, ballot|
      if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, incoming.slot]
      else
        [incoming.proposer_client, ip_port, ballot.id, ballot.num, incoming.slot]
      end
    end
    log <+- (p2a * max_acceptor_ballot).pairs do |incoming, ballot|
      [[incoming.slot, incoming.id, incoming.ballot_num, incoming.payload]] if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
    end
  end
end
