# frozen_string_literal: true

# FastMcp - Model Context Protocol for Rails
# This initializer sets up the MCP middleware in your Rails application.
#
# In Rails applications, you can use:
# - ActionTool::Base as an alias for FastMcp::Tool
# - ActionResource::Base as an alias for FastMcp::Resource
#
# All your tools should inherit from ApplicationTool which already uses ActionTool::Base,
# and all your resources should inherit from ApplicationResource which uses ActionResource::Base.

# Mount the MCP middleware in your Rails application
# You can customize the options below to fit your needs.
require 'fast_mcp'

FastMcp.mount_in_rails(
  Rails.application,
  name: 'jellyfin-mcp-server',
  version: '1.0.0',
  path_prefix: '/mcp', # This is the default path prefix
  messages_route: 'messages', # This is the default route for the messages endpoint
  sse_route: 'sse', # This is the default route for the SSE endpoint
  localhost_only: false, # allow the agent_api service (a different process/host) to connect
  authenticate: true,
  auth_token: ENV.fetch('MCP_AUTH_TOKEN', 'dev-secret-token')
) do |server|
  Rails.application.config.after_initialize do
    # FastMcp will automatically discover and register all classes
    # that inherit from ApplicationTool (which uses ActionTool::Base)
    server.register_tools(*ApplicationTool.descendants)
  end
end
