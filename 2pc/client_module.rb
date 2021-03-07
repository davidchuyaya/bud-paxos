module ClientModule
  bloom do
    client_to_coordinator <~ stdio { |io| [TwoPcProtocol::COORDINATOR_ADDR, io.line, ip_port] }
    stdio <~ coordinator_to_client { |incoming| ["Committed = #{incoming.commit_bool.to_s}: #{incoming.payload}"] }
  end
end

