require 'rubygems'
require 'bud'

class Kvs
    include Bud

    state do
        channel :get, [:@addr, :sender, :key] # GET requests only work once... hm.
        channel :put, [:@addr, :key, :value]
        channel :get_res, [:@addr, :key, :value]

        # server-only
        table :db, [:key] => [:value]
    end

    bloom :client do
        get <~ stdio do |io| 
            ["#{LOCALHOST}:#{SERVER_PORT}", ip_port, key_of_get(io.line)] if is_get(io.line)
        end
        put <~ stdio do |io|
            ["#{LOCALHOST}:#{SERVER_PORT}", key_of_put(io.line), value_of_put(io.line)] if is_put(io.line)
        end
        stdio <~ get_res { |res| ["#{res.key}: #{res.value}"] }
    end

    bloom :server do
        get_res <~ (get * db).pairs(:key => :key) { |req, row| [req.sender, req.key, row.value] }
        # Implicit ordering done by server
        db <+- put { |req| [req.key, req.value] }
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
SERVER_PORT = "10001"


server = Kvs.new(:stdin => $stdin, :ip => LOCALHOST, :port => SERVER_PORT.to_i)
server.run_bg
client = Kvs.new(:stdin => $stdin, :ip => LOCALHOST, :port => CLIENT_PORT.to_i)
client.run_fg