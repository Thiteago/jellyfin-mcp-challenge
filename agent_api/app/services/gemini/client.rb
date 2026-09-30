# frozen_string_literal: true

module Gemini
  class Client
    class Error < StandardError; end

    BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'

    def initialize(api_key: ENV.fetch('GEMINI_API_KEY'), model: ENV.fetch('GEMINI_MODEL', 'gemini-3.8-flash'))
      @api_key = api_key
      @model = model
      @connection = Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.adapter Faraday.default_adapter
      end
    end

    def generate_content(contents:, function_declarations: [])
      body = { contents: contents }
      body[:tools] = [{ functionDeclarations: function_declarations }] if function_declarations.present?

      response = @connection.post("models/#{@model}:generateContent") do |req|
        req.headers['x-goog-api-key'] = @api_key
        req.body = body
      end

      raise Error, "Gemini API error #{response.status}: #{response.body}" unless response.success?

      response.body
    end
  end
end
