module PaxosProposerModule
    bootstrap do
      # connect to acceptors
      for i in 1..PaxosProtocol::NUM_ACCEPTORS
        acceptor_addr = "#{PaxosProtocol::LOCALHOST}:#{(PaxosProtocol::ACCEPTOR_START_PORT + i).to_s}"
        acceptors <= [[slot_to_partition(i), acceptor_addr]]
        connect <~ [[acceptor_addr, ip_port, @id, "proposer"]]
      end
      for i in 0...PaxosProtocol::NUM_ACCEPTOR_GROUPS
        ballot_table <= [[i, @id, 1]]
        leader_table <= [[i, false]]
      end
      slot_table <= [[0]]
      id_table <= [[@id]]
    end
  
    bloom do
      # buffer payloads
      unslotted_payloads <= client_to_proposer { |incoming| [incoming.client, incoming.payload] }
      stdio <~ client_to_proposer { |incoming| ["client sent: #{incoming.payload}"] }
  
      # send p1a TODO1 wait on heartbeats
      current_ballot <= ballot_table.argmax([], :num)
                                    .argmax([], :id) do |partition, num, id|
        if id == @id
          [partition, num] # we are leader, don't increment
        else
          [partition, num + 1] # increment
        end
      end

      p1a_buffer <= (acceptors * current_ballot * leader_table)
                      .combos(acceptors.partition => leader_table.partition,
                              acceptors.partition => current_ballot.partition) do |acceptor, ballot, is_leader|
        [acceptor.addr, ip_port, acceptor.partition, @id, ballot.num] unless is_leader.bool
      end
      p1a <~ p1a_buffer.notin(p1a_sent)
      p1a_sent <+ p1a_buffer
  
      # process p1b
      p1b_received <= p1b
      #  NOTE: Match partition here because ballot is partitioned
      leader_accept_table <= (p1b_received * current_ballot * id_table)
                               .combos(p1b_received.partition => current_ballot.partition,
                                       p1b_received.sent_ballot_num => current_ballot.num,
                                       p1b_received.ballot_num => current_ballot.num,
                                       p1b_received.id => id_table.id) do |incoming, ballot, id|
        [incoming.partition, incoming.acceptor]
      end
      num_accept_table <= leader_accept_table.group([:partition], count)
      leader_table <= num_accept_table { |partition, num_accept| [partition, num_accept.num >= majority_acceptors] }
      # on (potential) rejection
      ballot_table <= p1b_received { |incoming| [incoming.partition, incoming.id, incoming.ballot_num] }
      # parse logs received in p1b
      # Note: this always returns nil; but acceptor_logs is on lhs to show dependence NOTE: Partition here because ballot is partitioned
      acceptor_logs <+ (p1b * current_ballot * id_table)
                         .combos(p1b.partition => current_ballot.partition,
                                 p1b.sent_ballot_num => current_ballot.num,
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
      stdio <~ leader_table { |is_leader| ["Is leader #{is_leader.bool.to_s} for partition #{is_leader.partition.to_s}"] }
      # acceptor_logs' size is strictly increasing. Ignore logs for ballots smaller than the current one
      # TODO we want to filter by map(slot) = partition, but can't write that in pairs. NOTE: Partition here because ballot is partitioned
      relevant_acceptor_logs <= (acceptor_logs * current_ballot).pairs(:sent_ballot_num => :num) do |log, ballot|
        puts "Relevant acceptor log added" # Note: This print is necessary for code execution, for some reason
        [log.acceptor, log.slot, log.id, log.ballot_num, log.payload] if ballot.partition == slot_to_partition(log.slot)
      end
  
      # max ballot (with payload) per slot
      max_ballot_acceptor_log <= relevant_acceptor_logs.argmax([:slot], :ballot_num)
                                                       .argmax([:slot], :id)
      # num distinct acceptors per slot with the max ballot
      counts_acceptor_log <= max_ballot_acceptor_log.group([:slot, :id, :ballot_num, :payload], count(:acceptor))
      # TODO1 change majority_acceptors into lattice quorum
      # resend uncommitted logs TODO1 only do once per leader election (will currently run continuously after getting majority)
      # TODO we want to filter by map(slot) = partition, but can't write that in pairs
      payloads_to_send_p2a <= (leader_table * counts_acceptor_log).pairs do |is_leader, log|
        [log.slot, "", log.payload] if is_leader.partition == slot_to_partition(log.slot) &&
          is_leader.bool && log.num_distinct < majority_acceptors
      end
      # discard client commands that are the same slot as an uncommitted command
      # TODO1 don't do that ^, reschedule instead
      # TODO1 might be a monotonic way to do this
      # sent_payloads <- (uncommitted_acceptor_logs * sent_payloads).pairs(:slot => :slot) { |log, payload| [log.slot] }
      # payload_acks <- (uncommitted_acceptor_logs * payload_acks).pairs(:slot => :slot) { |log, payload| [log.slot] }
  
      # TODO1 allow triggering hole-filling (from the replicas?)
      # send p2a. Use the slot # that's larger than the largest assigned locally & the largest slot in acceptor logs
      max_local_slot <= slot_table.group([], max(:num))
      max_acceptor_log_slot <= counts_acceptor_log.group([], max(:slot))
      current_slot <= (max_local_slot * max_acceptor_log_slot).pairs {|slot_local, slot_acceptor| [slot_local, slot_acceptor].max }
  
      random_unslotted_payload <= unslotted_payloads.group([:payload], choose_rand(:client))
      # TODO we want to filter by map(slot + 1) = partition, but can't write that in combos
      payloads_to_send_p2a <= (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
        [slot.num + 1, p.client, p.payload] if is_leader.partition == slot_to_partition(slot.num + 1) && is_leader.bool
      end
      # TODO we want to filter by map(slot + 1) = partition, but can't write that in combos
      unslotted_payloads <- (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
        [p.client, p.payload] if is_leader.partition == slot_to_partition(slot.num + 1) && is_leader.bool
      end
      # TODO we want to filter by map(slot + 1) = partition, but can't write that in combos
      slot_table <+ (random_unslotted_payload * leader_table * current_slot).combos do |p, is_leader, slot|
        [slot.num + 1] if is_leader.partition == slot_to_partition(slot.num + 1) && is_leader.bool
      end
      sent_payloads <+ payloads_to_send_p2a { |p| [p.slot, p.client, p.payload] }
      # TODO we want map(slot) = partition, but can't write that in combos
      p2a <~ (acceptors * payloads_to_send_p2a * current_ballot).combos do |acceptor, p, ballot|
        [acceptor.addr, ip_port, acceptor.partition, @id, ballot.num, p.payload, p.slot] if acceptor.partition == slot_to_partition(p.slot)
      end
  
      # process p2b
      stdio <~ p2b { |incoming| ["p2b id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, slot: #{incoming.slot.to_s}"] }
      # NOTE: Partition here because ballot is partitioned
      payload_acks <= (p2b * current_ballot).pairs(:partition => :partition) do |incoming, ballot|
        [incoming.slot, incoming.acceptor_client] if incoming.ballot_num == ballot.num && incoming.id == @id
      end
      acks_per_slot <= payload_acks.group([:slot], count)
      committed_slots_buffer <= acks_per_slot { |acks| [acks.slot] if acks.num_acks >= majority_acceptors }
      # on (potential) reject
      ballot_table <= p2b { |incoming| [incoming.partition, incoming.id, incoming.ballot_num] }
  
      # send to client
      newly_committed_slots <= committed_slots_buffer.notin(committed_slots_sent)
      proposer_to_client <~ (sent_payloads * newly_committed_slots).pairs(:slot => :slot) do |p, new_slot|
        [p.client, p.payload, p.slot] unless p.client == "" # Empty client for repaired slots
      end
      committed_slots_sent <+ committed_slots_buffer
    end
  
    def majority_acceptors
      PaxosProtocol::NUM_ACCEPTORS / 2 + 1
    end

    def slot_to_partition(slot)
      slot % PaxosProtocol::NUM_ACCEPTOR_GROUPS
    end
  end
  