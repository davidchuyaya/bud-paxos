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
    slot_table <= [[0]]
  end

  bloom do
    # buffer payloads
    unslotted_payloads <= client_to_proposer { |incoming| [incoming.client, incoming.payload] }
    stdio <~ client_to_proposer { |incoming| ["client sent: #{incoming.payload}"] }

    # send p1a TODO wait on heartbeats
    current_ballot <= ballot_table.group([], max(:num))
    p1a <~ (acceptors * current_ballot * leader_table).combos do |acceptor, ballot, is_leader|
      [acceptor.addr, ip_port, @id, ballot.num] if !is_leader.bool && !sent_p1a_for_ballot.include?([ballot.num])
    end
    sent_p1a_for_ballot <+ current_ballot { |ballot| [ballot.num] }

    # process p1b
    p1b_received <+- p1b { |incoming| [incoming.acceptor_client, incoming.id, incoming.ballot_num, incoming.log] }
    leader_accept_table <= (p1b_received * current_ballot).pairs do |incoming, ballot|
      [incoming.acceptor] if incoming.id == @id && incoming.ballot_num == ballot.num
    end
    leader_reject_table <= (p1b_received * current_ballot).pairs do |incoming, ballot|
      [incoming.acceptor, incoming.ballot_num] if incoming.ballot_num > ballot.num || (incoming.id > @id && incoming.ballot_num == ballot.num)
    end
    num_accept_table <= leader_accept_table.group([], count)
    leader_table <= num_accept_table { |num_accept| [num_accept.num >= majority_acceptors && !leader_reject_table.exists?] }
    # on rejection
    max_reject_ballot <= leader_reject_table.group([], max(:ballot_num))
    ballot_table <+ max_reject_ballot { |max_ballot| [max_ballot.ballot_num + 1] }
    # parse logs received in p1b
    # Note: this always returns nil; but acceptor_logs is on lhs to show dependence
    acceptor_logs <+ (p1b * current_ballot).pairs do |incoming, ballot|
      if incoming.id == @id && incoming.ballot_num == ballot.num # No need to store logs if we're not the leader
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
          puts "Inserting slot:#{$slot.to_s}, ballot: [#{$id.to_s},#{$ballot_num.to_s}], payload: #{$payload}"
          acceptor_logs <= [[incoming.ballot_num, incoming.acceptor_client, $slot, $id, $ballot_num, $payload]]
        end
        puts "accepted id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"
        nil
      end
    end
    stdio <~ leader_table { |is_leader| ["Is leader: #{is_leader.bool.to_s}"] }
    stdio <~ acceptor_logs.inspected
    # resend uncommitted logs
    relevant_acceptor_logs <= (acceptor_logs * current_ballot).pairs(:p1a_ballot => :num) do |log, ballot|
      puts "Relevant acceptor log added" # Note: This print is necessary for code execution, for some reason
      [log.acceptor, log.slot, log.id, log.ballot_num, log.payload]
    end
    uncommitted_acceptor_logs <= relevant_acceptor_logs.reduce({}) do |memo, log|
      # memo, [:slot] => array [:num, :id, :ballot_num, :payload]
      memo[log.slot] ||= [0, 0, 0, ""]
      if memo[log.slot][2] < log.ballot_num || (memo[log.slot][2] == log.ballot_num && memo[log.slot][1] < log.id)
        memo[log.slot][1] = log.id
        memo[log.slot][2] = log.ballot_num # overwrite ballot
        if memo[log.slot][3] != log.payload
          memo[log.slot][0] = 0
          memo[log.slot][3] = log.payload # overwrite payload
        end
      end
      if memo[log.slot][3] == log.payload
        memo[log.slot][0] += 1 # increment count
      end
      memo
    end
    stdio <~ relevant_acceptor_logs.inspected
    stdio <~ uncommitted_acceptor_logs.inspected
    payloads_to_send_p2a <= (leader_table * uncommitted_acceptor_logs).pairs do |is_leader, log|
      [log.slot, "", log.data[3]] if is_leader.bool && log.data[0] <= majority_acceptors
    end
    # discard client commands that are the same slot as an uncommitted command
    payloads <- (uncommitted_acceptor_logs * payloads).pairs(:slot => :slot) { |log, payload| [log.slot] }

    # send p2a
    max_local_slot <= slot_table.group([], max(:num))
    max_acceptor_log_slot <= uncommitted_acceptor_logs.group([], max(:slot))
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
    payloads <+ payloads_to_send_p2a { |p| [p.slot, p.client, p.payload, 0] }
    p2a <~ (acceptors * payloads_to_send_p2a * current_ballot).combos { |acceptor, p, ballot|
      [acceptor.addr, ip_port, @id, ballot.num, p.payload, p.slot] }

    # process p2b
    stdio <~ p2b { |incoming| ["p2b id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, slot: #{incoming.slot.to_s}"] }
    payloads <+- (p2b * payloads * current_ballot).combos(p2b.slot => payloads.slot) do |incoming, p, ballot|
      # TODO fix num_accept count
      [p.slot, p.client, p.payload, p.num_accept + 1] if incoming.ballot_num == ballot.num && incoming.id == @id
    end
    newly_committed_slots <= payloads { |p| [p.slot] if p.num_accept + 1 >= majority_acceptors }
    # on reject
    ballot_table <+ (p2b * current_ballot).pairs do |incoming, ballot|
      [incoming.ballot_num] if incoming.ballot_num > ballot.num || (incoming.ballot_num == ballot.num && incoming.id > @id)
    end

    # send to client
    proposer_to_client <~ (payloads * newly_committed_slots).pairs(:slot => :slot) do |p, new_slot|
      [p.client, p.payload, p.slot] unless (committed_slots.include?([p.slot]) || p.client == "") # only send once. Empty client for repaired slots
    end
    committed_slots <+ newly_committed_slots { |new_slot| [new_slot.slot] }
  end

  def majority_acceptors
    PaxosProtocol::NUM_ACCEPTORS / 2 + 1
  end
end
