module PaxosAcceptorModule
  bootstrap do
    acceptor_ballot_table <= [[0, 1]]
    log <= [[0, 1, 2, "hi"]]
  end

  bloom do
    stdio <~ p1a { |incoming| ["p1a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"] }
    stdio <~ p2a { |incoming| ["p2a id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, payload: #{incoming.payload}, slot: #{incoming.slot.to_s}"] }



    # For each entry, only the payload with the max ballot should be kept
    log_entry_max_ballot <= log.argmax([:slot], :ballot_num)
      .group([:slot, :ballot_num], max(:id))
    log <- (log * log_entry_max_ballot).pairs(:slot => :slot) do |l, ballot|
      [l.slot, l.id, l.ballot_num, l.payload] if l.id != ballot.id || l.ballot_num != ballot.num
    end
    # See correctness argument in dedalus-paxos/acceptor.txt



    ######################## reply to p1a 
    acceptor_ballot_table <= p1a { |incoming| [incoming.id, incoming.ballot_num] }
    max_acceptor_ballot <= acceptor_ballot_table.argmax([], :num)
      .argmax([], :id)
    log_size <= log.group([], count(:slot))
    p1b <~ (p1a * log_size * max_acceptor_ballot).combos do |incoming, size, ballot| 
      [incoming.proposer, ip_port, ballot.id, ballot.num, size.num]
    end
    
    # send back entire log
    p1b_log <~ (p1a * log * max_acceptor_ballot).combos do |incoming, l, ballot|
      [incoming.proposer, ip_port, l.slot, l.payload, l.id, l.ballot_num, ballot.id, ballot.num]
    end
    ######################## end reply to p1a 
  


    ######################## reply to p2a
    acceptor_ballot_table <= p2a { |incoming| [incoming.id, incoming.ballot_num] }
    log <= (p2a * max_acceptor_ballot).pairs do |incoming, ballot|
      [incoming.slot, incoming.id, incoming.ballot_num, incoming.payload] if incoming.ballot_num > ballot.num || (incoming.ballot_num == ballot.num && incoming.id >= ballot.id)
    end 
    p2b <~ (p2a * max_acceptor_ballot).pairs do |incoming, ballot|
      [incoming.proposer, ip_port, ballot.id, ballot.num, incoming.payload, incoming.slot]
    end
    ######################## end reply to p2a
  end
end
