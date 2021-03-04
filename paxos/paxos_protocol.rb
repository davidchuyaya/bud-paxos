module PaxosProtocol
  state do
    channel :connect, [:@addr, :client] => [:id, :type] # type:string = client, acceptor, or proposer

    channel :client_to_proposer, [:@addr] => [:client, :payload]
    channel :proposer_to_client, [:@addr] => [:payload, :slot]
    channel :p1a, [:@addr] => [:proposer_client, :id, :ballot_num]
    channel :p1b, [:@addr] => [:acceptor_client, :id, :ballot_num, :log] # log = [:slot] => [:id, :ballot_num, :payload]
    channel :p2a, [:@addr] => [:proposer_client, :id, :ballot_num, :payload, :slot]
    channel :p2b, [:@addr] => [:acceptor_client, :id, :ballot_num, :slot]
  end

  LOCALHOST = "127.0.0.1"
  PROPOSER_START_PORT = 15000
  ACCEPTOR_START_PORT = 16000
end
