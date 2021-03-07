require 'rubygems'
require 'bud'
require_relative '2pc_protocol'

class Coordinator
  include Bud
  include TwoPcProtocol

  def initialize(opts={})
    super
  end

  bootstrap do
  end

  bloom do
    participants <= connect { |c| [c.client] }
    payloads <= client_to_coordinator { |incoming| [incoming.payload, incoming.client, 1, 1, true] }

    # phase 1
    vote_request <~ (client_to_coordinator * participants).pairs { |incoming, participant| [participant.client, incoming.payload] }
    payloads <+- (vote_response * payloads).pairs(:payload => :payload) do |incoming, p|
      [p.payload, p.client, p.num_votes + 1, p.num_acks, p.commit_bool && incoming.commit_bool]
    end

    # phase 2
    commit <~ (payloads * participants).pairs do |p, participant|
      [participant.client, p.payload, p.commit_bool] if p.num_votes == NUM_PARTICIPANT && !sent_commit.include?([p.payload])
    end
    sent_commit <+ payloads { |p| [p.payload] if p.num_votes == NUM_PARTICIPANTS }
    payloads <+- (commit_ack * payloads).pairs(:payload => :payload) do |incoming, p|
      puts "Acked #{p.payload}, num votes: #{p.num_votes}, num acks: #{p.num_acks}"
      [p.payload, p.client, p.num_votes, p.num_acks + 1, p.commit_bool && incoming.commit_bool]
    end

    coordinator_to_client <~ payloads do |p|
      [p.client, p.payload, p.commit_bool] if p.num_acks == NUM_PARTICIPANTS && !acked_client.include?([p.payload])
    end
    acked_client <+ payloads { |p| [p.payload] if p.num_acks == NUM_PARTICIPANTS }
  end
end

program = Coordinator.new(:stdin => $stdin, :ip => TwoPcProtocol::LOCALHOST,
                            :port => TwoPcProtocol::COORDINATOR_PORT)
program.run_fg
