module PaxosAcceptorModule
  bootstrap do
    acceptor_ballot_table <= [[0, 0]]
  end

  bloom do
    stdio <~ p1a { |incoming| ["p1a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"] }
    stdio <~ p2a { |incoming| ["p2a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, payload: #{incoming.payload}, slot: #{incoming.slot.to_s}"] }

    # update ballot to whatever largest value we get
    acceptor_ballot_table <- (p1a * acceptor_ballot_table).pairs do |incoming, ballot|
      [ballot.id, ballot.num] if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
    end
    acceptor_ballot_table <+ (p1a * acceptor_ballot_table).pairs do |incoming, ballot|
      [incoming.id, incoming.ballot_num] if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
    end
    acceptor_ballot_table <- (p2a * acceptor_ballot_table).pairs do |incoming, ballot|
      [ballot.id, ballot.num] if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
    end
    acceptor_ballot_table <+ (p2a * acceptor_ballot_table).pairs do |incoming, ballot|
      [incoming.id, incoming.ballot_num] if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
    end

    # process p1a
    p1b <~ (p1a * acceptor_ballot_table).pairs do |incoming, ballot|
      if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, log.inspected]
      else
        [incoming.proposer_client, ip_port, ballot.id, ballot.num, log.inspected]
      end
    end


    # process p2a
    p2b <~ (p2a * acceptor_ballot_table).pairs do |incoming, ballot|
      if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, incoming.slot]
      else
        [incoming.proposer_client, ip_port, ballot.id, ballot.num, incoming.slot]
      end
    end
    log <+- (p2a * acceptor_ballot_table).pairs do |incoming, ballot|
      [[incoming.slot, incoming.id, incoming.ballot_num, incoming.payload]] if incoming.ballot_num >= ballot.num && incoming.id >= ballot.id
    end
  end
end
