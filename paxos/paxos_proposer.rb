require 'rubygems'
require 'bud'
require_relative 'paxos_protocol'

class PaxosProposer
  include Bud
  include PaxosProtocol

  def initialize(id, num_acceptors, opts={})
    @id = id
    @num_acceptors = num_acceptors
    super opts
  end

  state do
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
    # TODO heartbeats?
  end

  bootstrap do
    # connect to acceptors
    for i in 1..@num_acceptors
      acceptor_addr = "#{PaxosProtocol::LOCALHOST}:#{(PaxosProtocol::ACCEPTOR_START_PORT + i).to_s}"
      acceptors <= [[acceptor_addr, false]]
      connect <~ [[acceptor_addr, ip_port, @id, "proposer"]]
    end
    ballot_table <= [[0]]
    leader_accept_table <= [[0]] # tables need a dummy value for "count" to execute without waiting an extra timestep
    leader_reject_table <= [[0]] # ^ same
    leader_table <= [[false]]
    slot_table <= [[0]]
  end

  bloom do
    # buffer payloads
    unslotted_payloads <= client_to_proposer { |incoming| [incoming.client, incoming.payload] }
    stdio <~ client_to_proposer { |incoming| ["client sent: #{incoming.payload}"] }

    # send p1a TODO wait on heartbeats
    p1a <~ (acceptors * ballot_table * leader_table).combos do |acceptor, ballot, is_leader|
      if !is_leader.bool && !acceptor.sent_p1a
        acceptors <+- [[acceptor.addr, true]] # update sent_p1a = true
        [acceptor.addr, ip_port, @id, ballot.num] #if pending_payloads.exists?
      end
    end

    leader_accept_table <= (p1b * ballot_table).pairs do |incoming, ballot|
      [[incoming.acceptor_client, incoming.id, incoming.ballot_num, incoming.log]] if incoming.ballot_num == ballot.num && incoming.id == @id
    end
    leader_reject_table <= (p1b * ballot_table).pairs do |incoming, ballot|
      [[incoming.acceptor_client, incoming.id, incoming.ballot_num, incoming.log]] if incoming.ballot_num != ballot.num || incoming.id != @id
    end

    # process p1b
    leader_table <+ (leader_accept_table.group(nil, count) * leader_reject_table.group(nil, count))
                      .pairs do |num_accept, num_reject|
      # note that we subtract one. Num_accept & num_reject both need at least 1 element to trigger this code
      puts "Num accept: #{num_accept[0]-1}, num reject: #{num_reject[0]-1}"
      if num_accept[0]-1 >= majority_acceptors
        leader_table <- [[false]]
        [true]
      elsif num_accept[0]-1 + num_reject[0]-1 >= majority_acceptors
        # TODO wait a bit
        no_longer_leader
        nil
      end
    end
    # Note: this print has the side effect of populating acceptor logs
    stdio <~ p1b { |incoming| ["accepted id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, log: #{uninspected_log(incoming.log)}"] }
    stdio <~ leader_table { |is_leader| ["Is leader: #{is_leader.bool.to_s}"] }
    stdio <~ acceptor_logs.inspected

    # uncommitted log, enqueue
    payloads_to_send_p2a <= (leader_table * acceptor_logs).combos do |is_leader, log|
      if is_leader.bool && log.num <= majority_acceptors && !slot_table.include?([log.slot])
        puts "repairing"
        payloads <+ [[log.slot, "", log.payload, 0]]
        slot_table <+ [[log.slot]]
        [log.slot, log.payload]
      end
    end

    # set slots
    payloads_to_send_p2a <= (unslotted_payloads.group([:client, :payload], choose_rand(:client)) * leader_table * slot_table.group(nil, max(:num)))
                              .combos do |p, is_leader, max_slot|
      if is_leader.bool
        puts "Setting slot, max: #{max_slot}"
        $slot = max_slot.num + 1
        unslotted_payloads <- [[p.client, p.payload]]
        payloads <+ [[$slot, p.client, p.payload, 0]]
        slot_table <+ [[$slot]] # TODO potential clash with repaired slots
        [$slot, p.payload]
      end
    end

    # send p2a
    p2a <~ (acceptors * payloads_to_send_p2a * ballot_table).combos { |acceptor, p, ballot|
      [acceptor.addr, ip_port, @id, ballot.num, p.payload, p.slot] }

    # process p2b
    stdio <~ p2b { |incoming| ["p2b id: #{incoming.id.to_s}, ballot num: #{incoming.ballot_num.to_s}, slot: #{incoming.slot.to_s}"] }
    newly_committed_slots <= (p2b * payloads * ballot_table).combos(p2b.slot => payloads.slot) do |incoming, p, ballot|
      if incoming.ballot_num == ballot.num && incoming.id == @id
        puts "Accepted, num_accept: #{p.num_accept.to_s}, client: #{p.client}"
        if p.num_accept + 1 >= majority_acceptors
          [p.slot]
        else
          payloads <+- [[p.slot, p.client, p.payload, p.num_accept + 1]]
          nil # prevent payloads from being returned
        end
      else
        no_longer_leader
      end
    end

    # send to client
    proposer_to_client <~ (payloads * newly_committed_slots).pairs(:slot => :slot) do |p, new_slot|
      [p.client, p.payload, p.slot] unless (committed_slots.include?([p.slot]) || p.client == "") # only send once. Empty client for repaired slots
    end
    committed_slots <+ newly_committed_slots { |new_slot| [new_slot.slot] }
  end

  def majority_acceptors
    @num_acceptors / 2 + 1
  end

  def no_longer_leader
    # Note: leave at least 1 element in the tables for the rules to trigger correctly
    leader_accept_table <- leader_accept_table { |l1| [l1.acceptor] unless l1.acceptor == 0 }
    leader_reject_table <- leader_reject_table { |l2| [l2.acceptor] unless l2.acceptor == 0 }
    acceptors <+- p1b {|incoming| [incoming.acceptor_client, false]}
    ballot_table <- ballot_table {|b1| [b1.num]}
    ballot_table <+ ballot_table {|b2| [b2.num + 1]}
    acceptor_logs <- acceptor_logs {|a| [a.acceptor, a.slot]}
    slot_table <- slot_table {|s| [s.num] unless s.num == 0}
    leader_table <- [[true]]
    leader_table <+ [[false]]
    # unslot all pending payloads
    unslotted_payloads <= payloads {|p| [p.client, p.payload]}
  end

  # sample log: [["[1000, 0, 0, \"Test\"]"], ["[2000, 0, 0, \"test 2\"]"]]
  def uninspected_log(log)
    # strip string of unwanted characters: [ , " ] \
    # Note: will delete these from input if it was a part of the input. Assumes input is clean
    stripped = log.to_s.gsub(/[\["\]\\]/, '')
    splitted = stripped.split(', ')
    # Put into :acceptor_logs, [:slot] => [:id, :ballot_num, :payload, :num]
    for i in 0...(splitted.length/4)
      $offset = 4*i
      $slot = splitted[$offset].to_i
      $id = splitted[$offset+1].to_i
      $ballot_num = splitted[$offset+2].to_i
      $payload = splitted[$offset+3]
      puts "Inserting slot:#{$slot.to_s}, ballot: [#{$id.to_s},#{$ballot_num.to_s}], payload: #{$payload}"
      if acceptor_logs.exists?{|prev_log| prev_log.slot == $slot} # not sure why, but "include" doesn't work here
        acceptor_logs <+- acceptor_logs do |existing_log|
          if existing_log.slot == $slot
            if existing_log.ballot_num == $ballot_num && existing_log.id == $id
              [$slot, $id, $ballot_num, $payload, existing_log.num + 1] # same ballot
            elsif existing_log.ballot_num < $ballot_num || (existing_log.ballot_num == $ballot_num && existing_log.id < $id)
              [$slot, $id, $ballot_num, $payload, 1] # overwrite
            end
          end
        end
      else
        acceptor_logs <= [[$slot, $id, $ballot_num, $payload, 1]]
      end
    end
    acceptor_logs.inspected.to_s
  end
end

# Arguments: proposer ID (starting from 1), num acceptors
id = ARGV[0].to_i
num_acceptors = ARGV[1].to_i
program = PaxosProposer.new(id, num_acceptors, :stdin => $stdin, :ip => PaxosProtocol::LOCALHOST,
                            :port => PaxosProtocol::PROPOSER_START_PORT + id)
program.run_fg