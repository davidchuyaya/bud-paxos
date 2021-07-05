require 'rubygems'
require 'bud'

class Kvs
    include Bud

    state do
        channel :get, [:@addr, :sender, :key]
        channel :put, [:@addr, :key, :value]
        channel :get_res, [:@addr, :key, :value]
        table :servers, [:part, :addr]

        # server-only
        table :db, [:key] => [:value]
    end

    bootstrap do
        servers <= (0...SERVER_PORTS.length).map { |i| [i, "#{LOCALHOST}:#{SERVER_PORTS[i]}"] }
    end

    bloom :client do # "client" is aware of partitioning in this model.
        get <~ (stdio * servers).pairs do |io, server| 
            [server.addr, ip_port, key_of_get(io.line)] if is_get(io.line) && server.part == partition_of_key(key_of_get(io.line))
        end
        put <~ (stdio * servers).pairs do |io, server|
            [server.addr, key_of_put(io.line), value_of_put(io.line)] if is_put(io.line) && server.part == partition_of_key(key_of_put(io.line))
        end
        stdio <~ get_res { |res| ["#{res.key}: #{res.value}"] }
    end

    bloom :server do
        get_res <~ (get * db).pairs(:key => :key) { |req, row| [req.sender, req.key, row.value] }
        # Implicit ordering done by server
        db <+- put { |req| [req.key, req.value] }
    end

    def partition_of_key(key)
        key.hash % SERVER_PORTS.length
    end

    # GET expected input format: "GET key"
    def is_get(input)
        input.start_with?("GET ")
    end
    def key_of_get(input)
        input["GET ".length, input.length]
    end
    # PUT expected input format: "PUT key:value"
    def is_put(input)
        input.start_with?("PUT ")
    end
    def key_of_put(input)
        remainder = input["PUT ".length, input.length]
        remainder.split(":")[0]
    end
    def value_of_put(input)
        remainder = input["PUT ".length, input.length]
        remainder.split(":")[1]
    end
end

LOCALHOST = "127.0.0.1"
CLIENT_PORT = "10000"
SERVER_PORTS = ["10001", "10002", "10003"]


SERVER_PORTS.each do |port|
    server = Kvs.new(:stdin => $stdin, :ip => LOCALHOST, :port => port.to_i)
    server.run_bg
end
client = Kvs.new(:stdin => $stdin, :ip => LOCALHOST, :port => CLIENT_PORT.to_i)
client.run_fg