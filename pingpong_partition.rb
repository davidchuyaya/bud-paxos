require 'rubygems'
require 'bud'

class PingPong
    include Bud

    state do
        channel :chan, [:@addr, :sender, :value]
        periodic :timer, 1
    end

    bootstrap do
        pongers <= (0...RECEIVER_PORTS.length).map { |i| [i, RECEIVER_PORTS[i]] }
    end

    bloom :sender do
        # sender does not contain partitioned key
        chan <~ (timer * pongers).pairs do |t, ponger|
            partition = partitioning_func(t.key.to_i)
            ["#{LOCALHOST}:#{ponger.port}", ip_port, "ping"] if ip_port == "#{LOCALHOST}:#{SENDER_PORT}" && partition == ponger.part
        end
    end
    bloom :receiver do
        chan <~ chan { |incoming| [incoming.sender, ip_port, "pong"] if incoming.value == "ping" }
        stdio <~ chan.inspected
    end
    def partitioning_func(i)
        i % RECEIVER_PORTS.length
    end
end

LOCALHOST = "127.0.0.1"
SENDER_PORT = "10000"
RECEIVER_PORTS = ["10001", "10002", "10003"]

RECEIVER_PORTS.each do |port|
    pong = PingPong.new(:stdin => $stdin, :ip => LOCALHOST, :port => port.to_i)
    pong.run_bg
end
ping = PingPong.new(:stdin => $stdin, :ip => LOCALHOST, :port => SENDER_PORT.to_i)
ping.run_fg