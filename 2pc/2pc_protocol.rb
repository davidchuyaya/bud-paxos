module TwoPcProtocol
  state do
    channel :connect, [:@addr] => [:client]

    channel :client_to_coordinator, [:@addr, :payload] => [:client]
    channel :coordinator_to_client, [:@addr, :payload] => [:commit_bool]
    channel :vote_request, [:@addr, :payload]
    channel :vote_response, [:@addr, :payload] => [:commit_bool]
    channel :commit, [:@addr, :payload] => [:commit_bool]
    channel :commit_ack, [:@addr, :payload] => [:commit_bool]

    # coordinator
    table :participants, [:client]
    table :payloads, [:payload] => [:client, :num_votes, :num_acks, :commit_bool]
    table :sent_commit, [:payload]
    table :acked_client, [:payload]
  end

  NUM_PARTICIPANTS = 3
  LOCALHOST = "127.0.0.1"
  COORDINATOR_PORT = 10000
  COORDINATOR_ADDR = "#{LOCALHOST}:#{COORDINATOR_PORT}"
end
