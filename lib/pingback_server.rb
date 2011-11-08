require 'rack/rpc'
require 'xmlrpc/parser'

class PingbackServer < Rack::RPC::Server
  def hello_world
    "Hello, world!"
  end
  rpc 'hello_world' => :hello_world

  def pingback_ping(source_uri, target_uri)
    error_code, message = Pingback.receive_ping(source_uri, target_uri)
    raise XMLRPC::FaultException.new(error_code, message) if error_code
    message
  end
  rpc 'pingback.ping' => :pingback_ping
end
