require 'rack/rpc'
require 'xmlrpc/parser'

class PingbackServer < Rack::RPC::Server
  def hello_world
    "Hello, world!"
  end
  rpc 'hello_world' => :hello_world

  def pingback_ping(source_uri, target_uri)
    Rails.logger.info "Received pingback for #{target_uri} from #{source_uri}"
    error_code, message = Pingback.receive_ping(source_uri, target_uri)
    Rails.logger.info message
    raise XMLRPC::FaultException.new(error_code, message) if error_code
    message
  end
  rpc 'pingback.ping' => :pingback_ping
end
