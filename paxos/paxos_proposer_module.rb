module PaxosProposerModule
  bootstrap do
    # connect to acceptors
    for i in 1..PaxosProtocol::NUM_ACCEPTORS
      acceptor_addr = "#{PaxosProtocol::LOCALHOST}:#{(PaxosProtocol::ACCEPTOR_START_PORT + i).to_s}"
      acceptors <= [[acceptor_addr]]
      connect <~ [[acceptor_addr, ip_port, @id, "proposer"]]
    end
    ballot_table <= [[1]]
    leader_table <= [[false]]
    id_table <= [[@id]]
    dummy_table <= [[true]]
  end

  bloom do
    payloads <= client_to_proposer.payloads
    p1b_received <= p1b.payloads
    p1b_log_received <= p1b_log.payloads
    p2b_received <= p2b.payloads

    ######################## stable leader election
    current_ballot <= ballot_table.group([], max(:num))
    matching_p1bs <= (p1b_received * current_ballot * id_table).combos(p1b_received.id => id_table.id, p1b_received.ballot_num => current_ballot.num) do |incoming, b, i|
      [incoming.acceptor]
    end
    count_matching_p1bs <= matching_p1bs.group([], count(:acceptor))
    count_matching_p1bs_def <= count_matching_p1bs
    count_matching_p1bs_def <= dummy_table { |d| [0] if !count_matching_p1bs.exists? }
    max_p1b_ballot <= p1b_received.argmax([], :ballot_num)
      .group([:ballot_num], max(:id))
    max_p1b_ballot_def <= max_p1b_ballot
    max_p1b_ballot_def <= dummy_table { |d| [0, 0] if !max_p1b_ballot.exists? }
    max_p2b_ballot <= p2b_received.argmax([], :ballot_num)
      .group([:ballot_num], max(:id))
    max_p2b_ballot_def <= max_p2b_ballot
    max_p2b_ballot_def <= dummy_table { |d| [0, 0] if !max_p2b_ballot.exists? }
    leader_table <= (count_matching_p1bs_def * max_p1b_ballot_def * max_p2b_ballot_def * id_table * current_ballot).combos do |c, p1b_max, p2b_max, id, ballot|
      [c.num >= quorum && ballot_geq(id.id, ballot.num, p1b_max.id, p1b_max.num) && ballot_geq(id.id, ballot.num, p2b_max.id, p2b_max.num)]
    end

    # only resend p1a if we're not leader AND timeout counter reaches some magic number
    new_ballot <= (leader_table * id_table * current_ballot * timeout_counter).combos do |is_leader, id, ballot, timer|
      [ballot.num + 1] if !is_leader.bool && timer.val.sec == id.id # assumes id is < 60
    end
    p1a <~ (new_ballot * id_table * acceptors).combos do |ballot, id, a|
      [a.addr, ip_port, id.id, ballot.num]
    end
    ballot_table <+ new_ballot
    ######################## end stable leader election



    ######################## reconcile p1b log with local log
    # cannot send new p2as until all p1b acceptor logs are received; otherwise might miss pre-existing entry
    relevant_p1b_logs <= (p1b_log_received * id_table * current_ballot).combos(p1b_log_received.id => id_table.id, p1b_log_received.ballot_num => current_ballot.num) do |incoming, id, ballot|
      [incoming.acceptor, incoming.payload, incoming.slot, incoming.payload_id, incoming.payload_ballot_num]
    end
    relevant_p1bs <= (p1b_received * id_table * current_ballot).combos(p1b_received.id => id_table.id, p1b_received.ballot_num => current_ballot.num) do |incoming, id, ballot|
      [incoming.acceptor, incoming.log_size]
    end
    p1b_log_from_acceptor <= relevant_p1b_logs.group([:acceptor], count(:slot))
    # account for p1bs where no logs have been received yet (so p1bs_from_acceptor will not match)
    p1b_received_no_logs <= relevant_p1bs.notin(p1b_log_from_acceptor, :acceptor => :acceptor)
    p1b_received_logs <= p1b_received_no_logs { |p1b| [p1b.acceptor, 0] }
    p1b_received_logs <= p1b_log_from_acceptor
    p1b_acceptor_log_received <= (p1b_received_logs * relevant_p1bs).pairs(:acceptor => :acceptor, :num => :log_size) do |num_p1bs, p1b|
      [p1b.acceptor]
    end
    p1b_num_acceptors_log_received <= p1b_acceptor_log_received.group([], count(:acceptor))
    can_send_p2a <+- (p1b_num_acceptors_log_received * leader_table).pairs do |num_full_p1b_logs, is_leader|
      [is_leader.bool && num_full_p1b_logs.num >= quorum]
    end

    p1b_matching_entry <= relevant_p1b_logs.group([:payload, :slot, :payload_id, :payload_ballot_num], count(:acceptor))
    # what was committed = store in local log
    proposed_log <= p1b_matching_entry { |p1b| [p1b.payload, p1b.slot] if p1b.num >= quorum }

    # what was not committed = find max ballot, store in local log, resend 
    p1b_slot_received <= relevant_p1b_logs.group([:slot], count(:acceptor))
    p1b_largest_entry_ballot <= relevant_p1b_logs.argmax([:slot], :payload_ballot_num)
      .group([:slot, :payload_ballot_num], max(:payload_id))
    resent_entries_with_overlap <= (p1b_largest_entry_ballot * p1b_matching_entry * leader_table * p1b_slot_received)
          .combos(p1b_largest_entry_ballot.slot => p1b_matching_entry.slot, 
          p1b_largest_entry_ballot.id => p1b_matching_entry.payload_id, 
          p1b_largest_entry_ballot.num => p1b_matching_entry.payload_ballot_num, 
          p1b_largest_entry_ballot.slot => p1b_slot_received.slot) do |ballot, entry, is_leader, c|
      # makes sure that p2as cannot be sent yet (with the exists/element is true check); otherwise resent slots might conflict. Once p2as can be sent, a new p1b log might tell us to propose a payload for the same slot we propose (in parallel) for p2a, which violates an invariant.
      [entry.payload, entry.slot] if is_leader.bool && c >= quorum && !can_send_p2a.exists?{|can_send| can_send.bool}
    end
    resent_entries <= resent_entries_with_overlap.notin(proposed_log, :slot => :slot) 
    proposed_log <+ resent_entries # must be next timestep because proposed_log is negated in resent_entries
    p2a <~ (resent_entries * id_table * current_ballot * acceptors).combos do |entry, id, ballot, acceptor|
      [acceptor.addr, ip_port, id.id, ballot.num, entry.payload, entry.slot]
    end
    # only persist proposed-log if we're the leader. This way, when we lose election, the proposals are refreshed based on p1bs
    proposed_log_del <= (proposed_log * leader_table).pairs { |p, is_leader| [p.payload, p.slot] if !is_leader.bool }
    proposed_log <- proposed_log_del
    ######################## end reconcile p1b log with local log



    ######################## send p2as
    log_no_next <= proposed_log.notin(proposed_log) { |l1, l2| l1.slot + 1 == l2.slot }
    min_log_no_next <= log_no_next.group([], min(:slot))
    min_log_hole <= min_log_no_next { |s| [s.slot + 1] }
    min_log_hole_def <= min_log_hole
    min_log_hole_def <= dummy_table { |d| [0] if !min_log_hole.exists? }

    unproposed_payloads <= payloads.notin(proposed_log, :payload => :payload)
    chosen_payload <= unproposed_payloads.group([], choose(:payload))

    chosen_entry <= (chosen_payload * min_log_hole_def * leader_table * can_send_p2a).combos do |payload, slot, is_leader, can_send|
      [payload.payload, slot.slot] if is_leader.bool && can_send.bool
    end
    p2a <~ (chosen_entry * id_table * current_ballot * acceptors).combos do |entry, id, ballot, acceptor|
      [acceptor.addr, ip_port, id.id, ballot.num, entry.payload, entry.slot]
    end
    proposed_log <+ chosen_entry
    ######################## end send p2as 



    ######################## process p2bs
    matching_p2bs <= (p2b_received * id_table * current_ballot).combos(p2b_received.id => id_table.id, p2b_received.ballot_num => current_ballot.num) do |incoming, id, ballot|
      [incoming.acceptor, incoming.payload, incoming.slot]
    end
    count_matching_p2bs <= matching_p2bs.group([:payload, :slot], count(:acceptor))
    stdio <~ count_matching_p2bs.inspected
    proposer_to_client <~ count_matching_p2bs do |entry|
      (addr, payload) = payload_to_addr_and_string(entry.payload)
      [addr, payload, entry.slot] if entry.num >= quorum
    end
    ######################## end process p2bs
  end

  def quorum 
    PaxosProtocol::NUM_ACCEPTORS / 2 + 1
  end
  def ballot_geq(id1, num1, id2, num2)
    num1 > num2 || (num1 == num2 && id1 >= id2)
  end
  def payload_to_addr_and_string(payload)
    payload.split(PaxosProtocol::DELIMITER)
  end
end
