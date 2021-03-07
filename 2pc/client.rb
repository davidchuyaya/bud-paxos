require 'rubygems'
require 'bud'
require_relative '2pc_protocol'
require_relative 'client_module'

class Client
  include Bud
  include TwoPcProtocol
  include ClientModule

  def initialize(opts={})
    super
  end
end

program = Client.new(:stdin => $stdin)
program.run_fg

