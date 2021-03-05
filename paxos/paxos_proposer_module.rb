module PaxosProposerModule
  bootstrap do
    # connect to acceptors
    for i in 1..PaxosProtocol::NUM_ACCEPTORS
      acceptor_addr = "#{PaxosProtocol::LOCALHOST}:#{(PaxosProtocol::ACCEPTOR_START_PORT + i).to_s}"
      acceptors <= [[acceptor_addr]]
      connect <~ [[acceptor_addr, ip_port, @id, "proposer"]]
    end
    ballot_table <= [[0]]
    leader_table <= [[false]]
    slot_table <= [[0]]
  end

  bloom do
    # buffer payloads
    unslotted_payloads <= client_to_proposer { |incoming| [incoming.client, incoming.payload] }
    stdio <~ client_to_proposer { |incoming| ["client sent: #{incoming.payload}"] }

    # send p1a TODO wait on heartbeats
    current_ballot <= ballot_table.group([:num], max(:num))
    p1a <~ (acceptors * current_ballot * leader_table).combos do |acceptor, ballot, is_leader|
      [acceptor.addr, ip_port, @id, ballot[0]] if !is_leader.bool && !sent_p1a_for_ballot.include?([ballot[0]])
    end
    sent_p1a_for_ballot <+ current_ballot { |ballot| [ballot[0]] }

    # process p1b
    p1b_received <+- p1b { |incoming| [incoming.acceptor_client, incoming.id, incoming.ballot_num, incoming.log] }
    leader_accept_table <= (p1b_received * current_ballot).pairs do |incoming, ballot|
      [incoming.acceptor] if incoming.id == @id && incoming.ballot_num == ballot[0]
    end
    leader_reject_table <= (p1b_received * current_ballot).pairs do |incoming, ballot|
      [incoming.acceptor, incoming.ballot_num] if incoming.ballot_num > ballot[0] || (incoming.id > @id && incoming.ballot_num == ballot[0])
    end
    num_accept_table <= leader_accept_table.group(nil, count)
    leader_table <= num_accept_table { |num_accept| [num_accept[0] >= majority_acceptors && !leader_reject_table.exists?] }
    # on rejection
    max_reject_ballot <= leader_reject_table.group([:ballot_num], max(:ballot_num))
    ballot_table <+ max_reject_ballot { |max_ballot| [max_ballot[0] + 1] }
    # parse logs received in p1b
    # Note: this always returns nil; but acceptor_logs is on lhs to show dependence
    acceptor_logs <+ p1b do |incoming|
      # sample log: [["[1000, 0, 0, \"Test\"]"], ["[2000, 0, 0, \"test 2\"]"]]
      # strip string of unwanted characters: [ , " ] \
      # Note: will delete these from input if it was a part of the input. Assumes input is clean
      stripped = incoming.log.to_s.gsub(/[\["\]\\]/, '')
      splitted = stripped.split(', ')
      # Put into :acceptor_logs, [:slot] => [:id, :ballot_num, :payload, :num]
      for i in 0...(splitted.length/4)
        $offset = 4*i
        $slot = splitted[$offset].to_i
        $id = splitted[$offset+1].to_i
        $ballot_num = splitted[$offset+2].to_i
        $payload = splitted[$offset+3]
        puts "Inserting slot:#{$slot.to_s}, ballot: [#{$id.to_s},#{$ballot_num.to_s}], payload: #{$payload}"
        if acceptor_logs.exists?{|prev_log| prev_log.slot == $slot} # not sure why, but "include" doesn't work here
          acceptor_logs <+- acceptor_logs do |existing_log|
            if existing_log.slot == $slot
              if existing_log.ballot_num == $ballot_num && existing_log.id == $id
                [$slot, $id, $ballot_num, $payload, existing_log.num + 1] # same ballot
              elsif existing_log.ballot_num < $ballot_num || (existing_log.ballot_num == $ballot_num && existing_log.id < $id)
                [$slot, $id, $ballot_num, $payload, 1] # overwrite
              end
            end
          end
        else
          acceptor_logs <= [[$slot, $id, $ballot_num, $payload, 1]]
        end
      end
      puts "accepted id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"
      nil
    end
    stdio <~ leader_table { |is_leader| ["Is leader: #{is_leader.bool.to_s}"] }
    stdio <~ acceptor_logs.inspected
    # resend uncommitted logs
    payloads_to_send_p2a <= (leader_table * acceptor_logs).combos do |is_leader, log|
      [log.slot, "", log.payload] if is_leader.bool && log.num <= majority_acceptors && !payloads.include?([log.slot])
    end

    # send p2a
    current_slot <= slot_table.group(nil, max(:num))
    random_unslotted_payload <= unslotted_payloads.group([:payload], choose_rand(:client))
    payloads_to_send_p2a <= (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
      # only send payloads when we're not repairing (acceptor logs doesn't include an uncommitted slot that we haven't sent)
      [slot[0] + 1, p[1], p[0]] if is_leader.bool && !acceptor_logs.exists?{ |log| !payloads.include?([log.slot]) }
    end
    unslotted_payloads <- (random_unslotted_payload * leader_table).combos do |p, is_leader|
      [p[1], p[0]] if is_leader.bool && !acceptor_logs.exists?{ |log| !payloads.include?([log.slot]) }
    end
    slot_table <+ (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
      [slot[0] + 1] if is_leader.bool && !acceptor_logs.exists?{ |log| !payloads.include?([log.slot]) }
    end
    # TODO reassign existing payload to a different slot if it's part of uncommitted OR committed log
    payloads <+ payloads_to_send_p2a { |p| [p.slot, p.client, p.payload, 0] }
    p2a <~ (acceptors * payloads_to_send_p2a * current_ballot).combos { |acceptor, p, ballot|
      [acceptor.addr, ip_port, @id, ballot[0], p.payload, p.slot] }

    # process p2b
    stdio <~ p2b { |incoming| ["p2b id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, slot: #{incoming.slot.to_s}"] }
    payloads <+- (p2b * payloads * current_ballot).combos(p2b.slot => payloads.slot) do |incoming, p, ballot|
      [p.slot, p.client, p.payload, p.num_accept + 1] if incoming.ballot_num == ballot[0] && incoming.id == @id
    end
    newly_committed_slots <= payloads { |p| [p.slot] if p.num_accept + 1 >= majority_acceptors }
    # on reject
    ballot_table <+ (p2b * current_ballot).pairs { |incoming, ballot| incoming.ballot_num if incoming.ballot_num > ballot[0] }

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
