module PaxosProposerModule
  bootstrap do
    # connect to acceptors
    for i in 1..PaxosProtocol::NUM_ACCEPTORS
      acceptor_addr = "#{PaxosProtocol::LOCALHOST}:#{(PaxosProtocol::ACCEPTOR_START_PORT + i).to_s}"
      acceptors <= [[acceptor_addr]]
      connect <~ [[acceptor_addr, ip_port, @id, "proposer"]]
    end
    ballot_table <= [[@id, 1]]
    leader_table <= [[false]]
    slot_table <= [[0]]
    id_table <= [[@id]]
  end

  bloom do
    # buffer payloads
    unslotted_payloads <= client_to_proposer { |incoming| [incoming.client, incoming.payload] }
    stdio <~ client_to_proposer { |incoming| ["client sent: #{incoming.payload}"] }

    # send p1a TODO wait on heartbeats
    current_ballot <= ballot_table.argmax([], :num)
                                  .argmax([], :id) do |num, id|
      if id == @id
        [num] # we are leader, don't increment
      else
        [num + 1] # increment
      end
    end
    p1a <~ (acceptors * current_ballot * leader_table).combos do |acceptor, ballot, is_leader|
      [acceptor.addr, ip_port, @id, ballot.num] if !is_leader.bool && !sent_p1a_for_ballot.include?([ballot.num])
    end
    # TODO is this correct? Want to make sure that we do not resend p1a (assumes reliable channels)
    # Need this to execute after we send p1a
    sent_p1a_for_ballot <+ current_ballot { |ballot| [ballot.num] }

    # process p1b
    p1b_received <= p1b { |incoming| [incoming.acceptor_client, incoming.sent_ballot_num, incoming.id,
                                      incoming.ballot_num, incoming.log] }
    leader_accept_table <= (p1b_received * current_ballot * id_table)
                             .combos(p1b_received.sent_ballot_num => current_ballot.num,
                                     p1b_received.ballot_num => current_ballot.num,
                                     p1b_received.id => id_table.id) { |incoming, ballot, id| [incoming.acceptor] }
    num_accept_table <= leader_accept_table.group([], count)
    leader_table <= num_accept_table { |num_accept| [num_accept.num >= majority_acceptors] }
    # on (potential) rejection
    ballot_table <= p1b_received { |incoming| [incoming.id, incoming.ballot_num] }
    # parse logs received in p1b
    # Note: this always returns nil; but acceptor_logs is on lhs to show dependence
    acceptor_logs <+ (p1b * current_ballot * id_table)
                       .combos(p1b.sent_ballot_num => current_ballot.num,
                               p1b.ballot_num => current_ballot.num,
                               p1b.id => id_table.id) do |incoming, ballot, id|
      # sample log: [["[1000, 0, 0, \"Test\"]"], ["[2000, 0, 0, \"test 2\"]"]]
      # strip string of unwanted characters: [ , " ] \
      # Note: will delete these from input if it was a part of the input. Assumes input is clean
      stripped = incoming.log.to_s.gsub(/[\["\]\\]/, '')
      splitted = stripped.split(', ')
      for i in 0...(splitted.length/4)
        $offset = 4*i
        $slot = splitted[$offset].to_i
        $id = splitted[$offset+1].to_i
        $ballot_num = splitted[$offset+2].to_i
        $payload = splitted[$offset+3]
        puts "Inserting slot: #{$slot.to_s}, ballot: [#{$id.to_s},#{$ballot_num.to_s}], payload: #{$payload}"
        acceptor_logs <= [[incoming.ballot_num, incoming.acceptor_client, $slot, $id, $ballot_num, $payload]]
      end
      nil
    end
    stdio <~ leader_table { |is_leader| ["Is leader: #{is_leader.bool.to_s}"] }
    # acceptor_logs' size is strictly increasing. Ignore logs for ballots smaller than the current one
    relevant_acceptor_logs <= (acceptor_logs * current_ballot).pairs(:sent_ballot_num => :num) do |log, ballot|
      puts "Relevant acceptor log added" # Note: This print is necessary for code execution, for some reason
      [log.acceptor, log.slot, log.id, log.ballot_num, log.payload]
    end

    # max ballot (with payload) per slot
    max_ballot_acceptor_log <= relevant_acceptor_logs.argmax([:slot], :ballot_num)
                                                     .argmax([:slot], :id)
    # num distinct acceptors per slot with the max ballot
    counts_acceptor_log <= max_ballot_acceptor_log.group([:slot, :id, :ballot_num, :payload], count(:acceptor))
    # TODO change majority_acceptors into lattice quorum
    # resend uncommitted logs TODO only do once per leader election (will currently run continuously after getting majority)
    payloads_to_send_p2a <= (leader_table * counts_acceptor_log).pairs do |is_leader, log|
      [log.slot, "", log.payload] if is_leader.bool && log.num_distinct < majority_acceptors
    end
    # discard client commands that are the same slot as an uncommitted command
    # TODO don't do that ^, reschedule instead
    # TODO might be a monotonic way to do this
    # sent_payloads <- (uncommitted_acceptor_logs * sent_payloads).pairs(:slot => :slot) { |log, payload| [log.slot] }
    # payload_acks <- (uncommitted_acceptor_logs * payload_acks).pairs(:slot => :slot) { |log, payload| [log.slot] }

    # TODO allow triggering hole-filling (from the replicas?)
    # send p2a. Use the slot # that's larger than the largest assigned locally & the largest slot in acceptor logs
    max_local_slot <= slot_table.group([], max(:num))
    max_acceptor_log_slot <= counts_acceptor_log.group([], max(:slot))
    current_slot <= (max_local_slot * max_acceptor_log_slot).pairs {|slot_local, slot_acceptor| [slot_local, slot_acceptor].max }

    random_unslotted_payload <= unslotted_payloads.group([:payload], choose_rand(:client))
    payloads_to_send_p2a <= (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
      [slot.num + 1, p.client, p.payload] if is_leader.bool
    end
    unslotted_payloads <- (random_unslotted_payload * leader_table).pairs do |p, is_leader|
      [p.client, p.payload] if is_leader.bool
    end
    slot_table <+ (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
      [slot.num + 1] if is_leader.bool
    end
    sent_payloads <+ payloads_to_send_p2a { |p| [p.slot, p.client, p.payload] }
    p2a <~ (acceptors * payloads_to_send_p2a * current_ballot).combos { |acceptor, p, ballot|
      [acceptor.addr, ip_port, @id, ballot.num, p.payload, p.slot] }

    # process p2b
    stdio <~ p2b { |incoming| ["p2b id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, slot: #{incoming.slot.to_s}"] }
    payload_acks <= (p2b * current_ballot).pairs do |incoming, ballot|
      [incoming.slot, incoming.acceptor_client] if incoming.ballot_num == ballot.num && incoming.id == @id
    end
    acks_per_slot <= payload_acks.group([:slot], count)
    newly_committed_slots <= acks_per_slot { |acks| [acks.slot] if acks.num_acks >= majority_acceptors }
    # on (potential) reject
    ballot_table <= p2b { |incoming| [incoming.id, incoming.ballot_num] }

    # send to client
    proposer_to_client <~ (sent_payloads * newly_committed_slots).pairs(:slot => :slot) do |p, new_slot|
      [p.client, p.payload, p.slot] unless (committed_slots.include?([p.slot]) || p.client == "") # only send once. Empty client for repaired slots
    end
    committed_slots <+ newly_committed_slots { |new_slot| [new_slot.slot] }
  end

  def majority_acceptors
    PaxosProtocol::NUM_ACCEPTORS / 2 + 1
  end
end
