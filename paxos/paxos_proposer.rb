require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'

class PaxosProposer
  include Bud
  include PaxosProtocol

  $ballot_num = 0
  $is_leader = false
  $sent_p1a = false
  $num_accept_leader = 0
  $num_reject_leader = 0
  $slot = 0

  def initialize(id, num_acceptors, opts={})
    @id = id
    @num_acceptors = num_acceptors
    super opts
  end

  state do
    table :clients, [:id] => [:client]
    table :acceptors, [:addr] => [:sent_p1a]
    table :payloads, [:client, :payload] => [:slot, :num_accept]
    # TODO heartbeats?
  end

  bootstrap do
    # connect to acceptors
    for i in 1..@num_acceptors
      acceptor_addr = PaxosProtocol::LOCALHOST + ":" + (PaxosProtocol::ACCEPTOR_START_PORT + i).to_s
      acceptors <= [[acceptor_addr, false]]
      connect <~ [[acceptor_addr, ip_port, @id, "proposer"]]
    end
  end

  bloom do
    # connect to clients
    clients <= connect { |incoming| [incoming.id, incoming.client] if incoming.type == "client" }

    # buffer payloads
    payloads <= client_to_proposer { |incoming| [incoming.client, incoming.payload, -1, 0] }
    stdio <~ client_to_proposer { |incoming| ["client sent: " + incoming.payload] }

    # send p1a TODO wait on heartbeats
    p1a <~ acceptors do |acceptor|
      if !$is_leader && !acceptor.sent_p1a
        acceptors <+- [[acceptor.addr, true]] # update sent_p1a = true
        [acceptor.addr, ip_port, @id, $ballot_num] #if pending_payloads.exists?
      end
    end

    # process p1b TODO merge logs, repair
    acceptors <+- (p1b * acceptors).pairs(:acceptor_client => :addr) do |incoming, acceptor|
      if incoming.ballot_num == $ballot_num && incoming.id == @id
        $num_accept_leader += 1
      else
        $num_reject_leader += 1
      end

      if $num_accept_leader >= majority_acceptors
        $is_leader = true
        [acceptor.addr, false] # update sent_p1a = false, will resend once $is_leader = false in the future
      elsif $num_accept_leader + $num_reject_leader >= majority_acceptors
        # TODO wait a bit
        $ballot_num += 1
        [acceptor.addr, false]
      end
    end
    stdio <~ p1b { |incoming| ["accepted id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}"] }

    # send p2a
    p2a <~ (acceptors * payloads).pairs do |acceptor, p|
      if $is_leader && p.slot == -1
        $this_slot = $slot
        $slot += 1
        payloads <+- [[p.client, p.payload, $this_slot, 0]] # TODO bad logic, fix
        [acceptor.addr, ip_port, @id, $ballot_num, p.payload, $this_slot]
      end
    end

    # process p2b
    stdio <~ p2b { |incoming| ["p2b id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, slot: #{incoming.slot.to_s}"] }
    proposer_to_client <~ (p2b * payloads).pairs(:slot => :slot) do |incoming, p|
      if incoming.ballot_num == $ballot_num && incoming.id == @id
        puts "Accepted, num_accept: #{p.num_accept.to_s}"
        if p.num_accept + 1 >= majority_acceptors
          [p.client, p.payload, p.slot]
        else
          payloads <+- [[p.client, p.payload, p.slot, p.num_accept + 1]]
        end
      else
        # TODO no longer leader
      end
    end
  end

  def majority_acceptors
    return @num_acceptors / 2 + 1
  end
end

# Arguments: proposer ID (starting from 1), num acceptors
id = ARGV[0].to_i
num_acceptors = ARGV[1].to_i
program = PaxosProposer.new(id, num_acceptors, :stdin => $stdin, :ip => PaxosProtocol::LOCALHOST,
                            :port => PaxosProtocol::PROPOSER_START_PORT + id)
program.run_fg