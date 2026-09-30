# frozen_string_literal: true

module Api
  class QuestionsController < ApplicationController
    def create
      question = params.require(:question)

      result = Agent::QuestionAnswerer.new.call(question)

      render json: { answer: result[:answer], tool_calls: result[:tool_calls] }
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue Mcp::Client::Error => e
      render json: { error: "MCP server unavailable: #{e.message}" }, status: :bad_gateway
    rescue Gemini::Client::Error, Agent::QuestionAnswerer::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end
  end
end
