module PaxosProtocol
  state do
    channel :connect, [:@addr, :client] => [:id, :type] # type:string = client, acceptor, or proposer

    channel :client_to_proposer, [:@addr, :client, :payload]
    channel :proposer_to_client, [:@addr, :payload, :slot]
    channel :p1a, [:@addr, :proposer_client, :partition, :id, :ballot_num]
    channel :p1b, [:@addr, :acceptor_client, :partition, :id, :ballot_num, :sent_ballot_num, :log] # log = [:slot] => [:id, :ballot_num, :payload]
    channel :p2a, [:@addr, :proposer_client, :partition, :id, :ballot_num, :payload, :slot]
    channel :p2b, [:@addr, :acceptor_client, :partition, :id, :ballot_num, :slot]

    # proposer that knows about partitions
    # Invariant: each partition has a FIXED group of acceptors
    # that satisfies 2f+1 availability and quorum (e.g odd number of members)
    table :acceptors, [:partition, :addr]
    table :id_table, [:id] # store @id, useful for joining
    table :ballot_table, [:partition, :id, :num] # stores all ballots seen
    table :p1a_buffer, p1a.schema
    table :p1a_sent, p1a.schema
    table :p1b_received, p1b.schema
    table :slot_table, [:num] # stores all slots used in the past
    table :acceptor_logs, [:sent_ballot_num, :acceptor, :slot] => [:id, :ballot_num, :payload] # NOTE: don't need to store partition, since slot already maps
    table :unslotted_payloads, [:client] => [:payload]
    table :sent_payloads, [:slot] => [:client, :payload]
    table :payload_acks, [:slot, :acceptor]
    table :committed_slots_buffer, [:slot]
    table :committed_slots_sent, [:slot]
    scratch :leader_table, [:partition, :bool] # TODO how to figure out?
    scratch :leader_accept_table, [:partition, :acceptor]
    scratch :current_ballot, [:partition, :num]
    scratch :num_accept_table, [:partition] => [:num]
    scratch :relevant_acceptor_logs, [:acceptor, :slot, :id, :ballot_num] => [:payload]
    scratch :max_ballot_acceptor_log, relevant_acceptor_logs.schema
    scratch :counts_acceptor_log, [:slot, :id, :ballot_num] => [:payload, :num_distinct]
    scratch :max_local_slot, [] => [:num]
    scratch :max_acceptor_log_slot, [] => [:num]
    scratch :current_slot, [] => [:num]
    scratch :random_unslotted_payload, [:payload, :client]
    scratch :payloads_to_send_p2a, [:slot] => [:client, :payload]
    scratch :acks_per_slot, [:slot] => [:num_acks]
    scratch :newly_committed_slots, [:slot]

    # acceptor
    table :log, [:slot, :id, :ballot_num] => [:payload]
    table :acceptor_ballot_table, [:id, :num]
    scratch :max_acceptor_ballot, acceptor_ballot_table.schema
    scratch :maximal_ballots, acceptor_ballot_table.schema
    scratch :max_log, log.schema

    # client
    table :proposers, [:addr]
  end

  NUM_ACCEPTORS = 3
  NUM_ACCEPTOR_GROUPS = 2
  NUM_PROPOSERS = 1
  LOCALHOST = "127.0.0.1"
  PROPOSER_START_PORT = 15000
  ACCEPTOR_START_PORT = 16000
end
