# frozen_string_literal: true

require 'net/http'
require 'json'
require 'securerandom'

module Mcp
  class Client
    class Error < StandardError; end

    DEFAULT_TIMEOUT = 15

    def self.shared
      @shared ||= new
    end

    def initialize(base_url: ENV.fetch('MCP_SERVER_URL'), auth_token: ENV.fetch('MCP_AUTH_TOKEN'))
      @uri = URI.parse(base_url)
      @auth_token = auth_token
      @pending = {}
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @messages_path = nil
      connect_sse!
    end

    def list_tools
      send_request('tools/list', {}).fetch('tools')
    end

    def call_tool(name, arguments = {})
      send_request('tools/call', { name: name, arguments: arguments })
    end

    private

    def connect_sse!
      ready = Queue.new

      @sse_thread = Thread.new do
        http = Net::HTTP.new(@uri.host, @uri.port)
        http.read_timeout = nil

        request = Net::HTTP::Get.new('/mcp/sse')
        request['Authorization'] = "Bearer #{@auth_token}"
        request['Accept'] = 'text/event-stream'

        buffer = +''
        http.request(request) do |response|
          response.read_body do |chunk|
            buffer << chunk
            while (boundary = buffer.index("\n\n"))
              raw_event = buffer.slice!(0..boundary + 1)
              handle_sse_event(raw_event, ready)
            end
          end
        end
      rescue StandardError => e
        ready << e
      end

      result = ready.pop
      raise Error, "Failed to connect to MCP server SSE stream: #{result.message}" if result.is_a?(Exception)

      @messages_path = result
    end

    def handle_sse_event(raw_event, ready)
      event_type = 'message'
      data_lines = []

      raw_event.each_line do |line|
        line = line.strip
        next if line.empty?

        if line.start_with?('event:')
          event_type = line.delete_prefix('event:').strip
        elsif line.start_with?('data:')
          data_lines << line.delete_prefix('data:').strip
        end
      end

      data = data_lines.join("\n")
      return if data.empty?

      case event_type
      when 'endpoint'
        ready << data
      when 'message'
        deliver_response(JSON.parse(data))
      end
    end

    def deliver_response(json)
      id = json['id']
      return unless id

      @mutex.synchronize do
        @pending[id] = json
        @cond.broadcast
      end
    end

    def send_request(method, params, retrying: false)
      id = SecureRandom.uuid
      post_message(id, method, params)
      response = wait_for_response(id)

      raise Error, response.dig('error', 'message') || 'MCP server returned an error' if response['error']

      response['result']
    rescue Error => e
      raise if retrying || !e.message.start_with?('Timeout')

      reconnect!
      send_request(method, params, retrying: true)
    end

    def reconnect!
      @sse_thread&.kill
      @mutex.synchronize { @pending.clear }
      connect_sse!
    end

    def post_message(id, method, params)
      post_uri = URI.join("#{@uri.scheme}://#{@uri.host}:#{@uri.port}", @messages_path)

      http = Net::HTTP.new(post_uri.host, post_uri.port)
      request = Net::HTTP::Post.new(post_uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{@auth_token}"
      request.body = { jsonrpc: '2.0', id: id, method: method, params: params }.to_json

      http.request(request)
    end

    def wait_for_response(id)
      deadline = Time.now + DEFAULT_TIMEOUT

      @mutex.synchronize do
        until @pending.key?(id)
          remaining = deadline - Time.now
          raise Error, "Timeout waiting for MCP server response (method id=#{id})" if remaining <= 0

          @cond.wait(@mutex, remaining)
        end

        @pending.delete(id)
      end
    end
  end
end
