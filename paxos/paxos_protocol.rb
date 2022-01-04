module PaxosProtocol
  state do
    channel :connect, [:@addr, :client] => [:id, :type] # type:string = client, acceptor, or proposer

    channel :client_to_proposer, [:@addr, :payload]
    channel :proposer_to_client, [:@addr, :payload, :slot]
    channel :p1a, [:@addr, :proposer, :id, :ballot_num]
    channel :p1b, [:@addr, :acceptor, :id, :ballot_num, :log_size]
    channel :p1b_log, [:@addr, :acceptor, :slot, :payload, :payload_id, :payload_ballot_num, :id, :ballot_num]
    channel :p2a, [:@addr, :proposer, :id, :ballot_num, :payload, :slot]
    channel :p2b, [:@addr, :acceptor, :id, :ballot_num, :payload, :slot]

    # proposer
    table :payloads, [:payload] # all client payloads ever received
    table :p1b_received, [:acceptor, :id, :ballot_num, :log_size] # all p1bs ever received
    table :p1b_log_received, [:acceptor, :slot, :payload, :payload_id, :payload_ballot_num, :id, :ballot_num]
    table :p2b_received, [:acceptor, :id, :ballot_num, :payload, :slot]

    table :dummy_table # used to insert default values into scratches
    table :acceptors, [:addr]
    table :id_table, [:id] # store @id, useful for joining
    table :ballot_table, [:num] # stores all seen ballots
    periodic :timeout_counter, 0.5
    scratch :new_ballot, [:num]
    scratch :leader_table, [:bool]
    scratch :current_ballot, [:num] # deletion doesn't work as expected, so we're working around deleting ballots by calculating the max
    scratch :matching_p1bs, [:acceptor]
    scratch :count_matching_p1bs, [:num]
    scratch :count_matching_p1bs_def, [:num] # _def = default. Since the count is based on aggregation, nothing is generated if the aggregated table is empty, but we still need a default count (0)
    scratch :max_p1b_ballot, [:num, :id] # Note: weird ordering of columns because that's how group-by sets it
    scratch :max_p1b_ballot_def, [:num, :id] 
    scratch :max_p2b_ballot, [:num, :id]
    scratch :max_p2b_ballot_def, [:num, :id]

    table :proposed_log, [:payload, :slot]
    scratch :relevant_p1bs, [:acceptor, :log_size] # relevant = ballot is our ballot
    scratch :relevant_p1b_logs, [:acceptor, :payload, :slot, :payload_id, :payload_ballot_num]
    scratch :p1b_log_from_acceptor, [:acceptor, :num] # num entries of log arrived from an acceptor who sent a p1b. Does not include acceptors whose log has not arrived (even a single entry)
    scratch :p1b_received_no_logs, [:acceptor, :log_size] # acceptors whose log has not arrived, not even a single entry
    scratch :p1b_received_logs, [:acceptor, :num]
    scratch :p1b_acceptor_log_received, [:acceptor] # acceptors whose entire log has arrived
    scratch :p1b_num_acceptors_log_received, [:num]
    table :can_send_p2a, [] => [:bool] # empty key so update always erases the value

    scratch :p1b_matching_entry, [:payload, :slot, :payload_id, :payload_ballot_num, :num] # Note: different ballots don't count as same payload
    scratch :p1b_slot_received, [:slot, :num]
    scratch :p1b_largest_entry_ballot, [:slot, :num, :id] # Note: weird ordering of columns because that's how group-by sets it
    scratch :resent_entries_with_overlap, [:payload, :slot] # entries to resend for p1b. Not yet checked against proposedLog; should not re-propose
    scratch :resent_entries, [:payload, :slot]
    scratch :proposed_log_del, [:payload, :slot] # _del = everything in the table to delete if we're no longer leader

    scratch :log_no_next, [:payload, :slot] # entries in the log where there is nothing after
    scratch :min_log_no_next, [:slot]
    scratch :min_log_hole, [:slot]
    scratch :min_log_hole_def, [:slot]
    scratch :unproposed_payloads, [:payload]
    scratch :chosen_payload, [:payload]
    scratch :chosen_entry, [:payload, :slot] # only exists if is_leader is true

    scratch :matching_p2bs, [:acceptor, :payload, :slot]
    scratch :count_matching_p2bs, [:payload, :slot, :num]

    # acceptor
    table :log, [:slot, :id, :ballot_num] => [:payload]
    table :acceptor_ballot_table, [:id, :num]
    scratch :log_size, [:num]
    scratch :log_entry_max_ballot, [:slot, :num, :id] # Note: weird ordering of columns because that's how group-by sets it
    scratch :max_acceptor_ballot, [:id, :num]

    # client
    table :proposers, [:addr]
  end

  NUM_ACCEPTORS = 3
  NUM_PROPOSERS = 1
  LOCALHOST = "127.0.0.1"
  PROPOSER_START_PORT = 15000
  ACCEPTOR_START_PORT = 16000
  DELIMITER = "|"
end
