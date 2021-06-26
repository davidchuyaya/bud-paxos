require 'rubygems'
require 'bud'

class PingPong
    include Bud

    state do
        channel :chan, [:@addr, :sender, :value]
        periodic :timer, 1
    end

    bloom :sender do
        chan <~ timer { |t| ["#{LOCALHOST}:#{RECEIVER_PORT}", ip_port, "ping"] if ip_port == "#{LOCALHOST}:#{SENDER_PORT}" }
    end

    bloom :receiver do
        chan <~ chan { |incoming| [incoming.sender, ip_port, "pong"] if incoming.value == "ping" }
        stdio <~ chan.inspected
    end
end

LOCALHOST = "127.0.0.1"
SENDER_PORT = "10000"
RECEIVER_PORT = "10001"


pong = PingPong.new(:stdin => $stdin, :ip => LOCALHOST, :port => RECEIVER_PORT.to_i)
pong.run_bg
ping = PingPong.new(:stdin => $stdin, :ip => LOCALHOST, :port => SENDER_PORT.to_i)
ping.run_fg