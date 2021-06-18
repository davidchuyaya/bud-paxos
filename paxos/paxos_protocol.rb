module PaxosProtocol
  state do
    channel :connect, [:@addr, :client] => [:id, :type] # type:string = client, acceptor, or proposer

    channel :client_to_proposer, [:@addr] => [:client, :payload]
    channel :proposer_to_client, [:@addr] => [:payload, :slot]
    channel :p1a, [:@addr] => [:proposer_client, :id, :ballot_num]
    channel :p1b, [:@addr] => [:acceptor_client, :id, :ballot_num, :sent_ballot_num, :log] # log = [:slot] => [:id, :ballot_num, :payload]
    channel :p2a, [:@addr] => [:proposer_client, :id, :ballot_num, :payload, :slot]
    channel :p2b, [:@addr] => [:acceptor_client, :id, :ballot_num, :slot]

    # proposer
    table :acceptors, [:addr]
    table :id_table, [:id] # store @id, useful for joining
    table :sent_p1a_for_ballot, [:num] # stores the ballots for all p1as sent
    table :ballot_table, [:id, :num] # stores all ballots seen
    table :p1b_received, [:acceptor, :sent_ballot_num] => [:id, :ballot_num, :log] # stores all p1bs ever received
    table :slot_table, [:num] # stores all slots used in the past
    table :acceptor_logs, [:sent_ballot_num, :acceptor, :slot] => [:id, :ballot_num, :payload]
    table :unslotted_payloads, [:client] => [:payload]
    table :sent_payloads, [:slot] => [:client, :payload]
    table :payload_acks, [:slot, :acceptor]
    table :committed_slots, [:slot]
    scratch :leader_table, [:bool]
    scratch :leader_accept_table, [:acceptor]
    scratch :current_ballot, [:num]
    scratch :num_accept_table, [] => [:num]
    scratch :relevant_acceptor_logs, [:acceptor, :slot] => [:id, :ballot_num, :payload]
    scratch :uncommitted_acceptor_logs, [:slot] => [:data]
    scratch :max_local_slot, [] => [:num]
    scratch :max_acceptor_log_slot, [] => [:num]
    scratch :current_slot, [] => [:num]
    scratch :random_unslotted_payload, [:payload, :client]
    scratch :payloads_to_send_p2a, [:slot] => [:client, :payload]
    scratch :acks_per_slot, [:slot] => [:num_acks]
    scratch :newly_committed_slots, [:slot]

    # acceptor
    table :log, [:slot] => [:id, :ballot_num, :payload]
    table :acceptor_ballot_table, [:id, :num]
    scratch :max_acceptor_ballot, [:id, :num]

    # client
    table :proposers, [:addr]
  end

  NUM_ACCEPTORS = 3
  NUM_PROPOSERS = 1
  LOCALHOST = "127.0.0.1"
  PROPOSER_START_PORT = 15000
  ACCEPTOR_START_PORT = 16000
end
