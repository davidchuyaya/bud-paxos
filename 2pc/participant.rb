require 'rubygems'
require 'bud'
require_relative '2pc_protocol'
require_relative 'participant_module'

class Participant
  include Bud
  include TwoPcProtocol
  include ParticipantModule

  def initialize(opts={})
    super
  end
end

program = Participant.new(:stdin => $stdin)
program.run_fg