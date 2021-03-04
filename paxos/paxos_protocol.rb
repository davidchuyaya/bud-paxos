module PaxosProtocol
  state do
    channel :connect, [:@addr, :client] => [:id, :type] # type:string = client, acceptor, or proposer

    channel :client_to_proposer, [:@addr] => [:client, :payload]
    channel :proposer_to_client, [:@addr] => [:payload, :slot]
    channel :p1a, [:@addr] => [:proposer_client, :id, :ballot_num]
    channel :p1b, [:@addr] => [:acceptor_client, :id, :ballot_num, :log] # log = [:slot] => [:id, :ballot_num, :payload]
    channel :p2a, [:@addr] => [:proposer_client, :id, :ballot_num, :payload, :slot]
    channel :p2b, [:@addr] => [:acceptor_client, :id, :ballot_num, :slot]

    # proposer
    table :acceptors, [:addr] => [:sent_p1a]
    table :ballot_table, [:num]
    table :leader_accept_table, [:acceptor] => [:id, :ballot_num, :log]
    table :leader_reject_table, [:acceptor] => [:id, :ballot_num, :log]
    table :leader_table, [:bool]
    table :slot_table, [:num] # stores all slots used in the past
    table :acceptor_logs, [:slot] => [:id, :ballot_num, :payload, :num] # num = number of identical ballots for this slot
    table :unslotted_payloads, [:client] => [:payload]
    table :payloads, [:slot] => [:client, :payload, :num_accept]
    table :committed_slots, [:slot]
    scratch :payloads_to_send_p2a, [:slot] => [:payload]
    scratch :newly_committed_slots, [:slot]
    # TODO heartbeats? leader failure & re-election?

    # acceptor
    table :log, [:slot] => [:id, :ballot_num, :payload]
    table :acceptor_ballot_table, [:id, :num]

    # client
    table :proposers, [:addr]
  end

  LOCALHOST = "127.0.0.1"
  PROPOSER_START_PORT = 15000
  ACCEPTOR_START_PORT = 16000
end
