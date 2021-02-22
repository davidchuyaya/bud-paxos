require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'

class PaxosAcceptor
  include Bud
  include PaxosProtocol
  $ballot_num = 0
  $ballot_id = 0

  def initialize(opts={})
    super opts
  end

  state do
    table :log, [:slot] => [:id, :ballot_num, :payload]
  end

  bootstrap do
  end

  bloom do
    stdio <~ p1a { |incoming| ["p1a id: " + incoming.id.to_s + ", ballot num: " + incoming.ballot_num.to_s] }
    stdio <~ p2a { |incoming| ["p2a id: " + incoming.id.to_s + ", ballot num: " + incoming.ballot_num.to_s +
                                 ", payload: " + incoming.payload + ", slot: " + incoming.slot.to_s] }

    # process p1a
    p1b <~ p1a do |incoming|
      if incoming.ballot_num >= $ballot_num && incoming.id >= $ballot_id
        $ballot_id = incoming.id
        $ballot_num = incoming.ballot_num
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num] #TODO figure out how to send log
      else
        [incoming.proposer_client, ip_port, $ballot_id, $ballot_num]
      end
    end

    # process p2a
    p2b <~ p2a do |incoming|
      if incoming.ballot_num >= $ballot_num && incoming.id >= $ballot_id
        log <= [[incoming.slot, incoming.id, incoming.ballot_num, incoming.payload]]
        [incoming.proposer_client, ip_port, incoming.id, incoming.ballot_num, incoming.slot]
      else
        [incoming.proposer_client, ip_port, $ballot_id, $ballot_num, incoming.slot]
      end
    end
  end
end

# Arguments: acceptor ID (starting from 1)
id = ARGV[0].to_i
program = PaxosAcceptor.new(:stdin => $stdin, :ip => PaxosProtocol::LOCALHOST,
                            :port => PaxosProtocol::ACCEPTOR_START_PORT + id.to_i)
program.run_fg
