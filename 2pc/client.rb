require 'rubygems'
require 'bud'
require_relative '2pc_protocol'

class Client
  include Bud
  include TwoPcProtocol

  def initialize(opts={})
    super
  end

  bootstrap do
  end

  bloom do
    client_to_coordinator <~ stdio { |io| [COORDINATOR_ADDR, io.line, ip_port] }
    stdio <~ coordinator_to_client { |incoming| ["Committed = #{incoming.commit_bool.to_s}: #{incoming.payload}"] }
  end
end

program = Client.new(:stdin => $stdin)
program.run_fg

