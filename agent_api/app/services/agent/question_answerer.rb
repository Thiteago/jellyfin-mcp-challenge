# frozen_string_literal: true

module Agent
  class QuestionAnswerer
    class Error < StandardError; end

    MAX_TURNS = 5
    ALLOWED_SCHEMA_KEYS = %w[type description properties items required enum format].freeze

    def initialize(mcp_client: Mcp::Client.shared, gemini_client: Gemini::Client.new)
      @mcp_client = mcp_client
      @gemini_client = gemini_client
    end

    def call(question)
      function_declarations = tool_declarations
      contents = [{ role: 'user', parts: [{ text: question }] }]
      tool_calls = []

      MAX_TURNS.times do
        response = @gemini_client.generate_content(contents: contents, function_declarations: function_declarations)
        parts = response.dig('candidates', 0, 'content', 'parts') || []
        function_calls = parts.select { |part| part['functionCall'] }

        return { answer: extract_text(parts), tool_calls: tool_calls } if function_calls.empty?

        contents << { role: 'model', parts: parts }
        contents << {
          role: 'user',
          parts: function_calls.map { |fc| run_tool_call(fc['functionCall'], tool_calls) }
        }
      end

      raise Error, "Gemini kept calling tools past #{MAX_TURNS} turns without a final answer"
    end

    private

    def tool_declarations
      @mcp_client.list_tools.map do |tool|
        {
          name: tool['name'],
          description: tool['description'],
          parameters: sanitize_schema(tool['inputSchema'])
        }
      end
    end

    def sanitize_schema(schema)
      return schema unless schema.is_a?(Hash)

      schema.each_with_object({}) do |(key, value), result|
        next unless ALLOWED_SCHEMA_KEYS.include?(key)

        result[key] = case key
                      when 'properties' then value.transform_values { |v| sanitize_schema(v) }
                      when 'items' then sanitize_schema(value)
                      else value
                      end
      end
    end

    def run_tool_call(function_call, tool_calls)
      name = function_call['name']
      arguments = function_call['args'] || {}
      mcp_result = @mcp_client.call_tool(name, arguments)
      result_text = Array(mcp_result['content']).find { |b| b['type'] == 'text' }&.fetch('text', nil) || '{}'
      parsed_result = begin
        JSON.parse(result_text)
      rescue JSON::ParserError
        result_text
      end

      tool_calls << { name: name, arguments: arguments, result: parsed_result, error: mcp_result['isError'] == true }

      {
        functionResponse: {
          name: name,
          response: parsed_result.is_a?(Hash) ? parsed_result : { result: parsed_result }
        }
      }
    end

    def extract_text(parts)
      parts.filter_map { |part| part['text'] }.join("\n")
    end
  end
end
