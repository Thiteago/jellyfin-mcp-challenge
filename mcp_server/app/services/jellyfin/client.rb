# frozen_string_literal: true

module Jellyfin
  # Thin HTTP wrapper around the Jellyfin REST API.
  # Docs: https://api.jellyfin.org
  class Client
    class Error < StandardError; end

    def initialize(base_url: ENV.fetch('JELLYFIN_URL'),
                    api_key: ENV.fetch('JELLYFIN_API_KEY'),
                    user_id: ENV.fetch('JELLYFIN_USER_ID'))
      @user_id = user_id
      @connection = Faraday.new(url: base_url) do |f|
        f.headers['Authorization'] = "MediaBrowser Token=\"#{api_key}\""
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.adapter Faraday.default_adapter
      end
    end

    # Generic search/browse over the library. Used by both random_movie and search_media.
    def items(include_item_types: 'Movie', search_term: nil, genres: nil, years: nil,
               unwatched_only: false, sort_by: 'SortName', sort_order: 'Ascending', limit: 20)
      params = {
        IncludeItemTypes: include_item_types,
        Recursive: true,
        SortBy: sort_by,
        SortOrder: sort_order,
        Limit: limit,
        Fields: 'Genres,Overview,CommunityRating,ProductionYear'
      }
      params[:SearchTerm] = search_term if search_term.present?
      params[:Genres] = genres if genres.present?
      params[:Years] = years if years.present?
      params[:Filters] = 'IsUnplayed' if unwatched_only

      get("/Users/#{@user_id}/Items", params).fetch('Items', [])
    end

    def item_details(item_id)
      get("/Users/#{@user_id}/Items/#{item_id}")
    end

    def mark_as_favorite(item_id)
      post("/Users/#{@user_id}/FavoriteItems/#{item_id}")
    end

    def active_sessions
      get('/Sessions')
    end

    private

    def get(path, params = {})
      response = @connection.get(path, params.compact)
      raise Error, "GET #{path} failed: #{response.status}" unless response.success?

      response.body
    end

    def post(path, params = {})
      response = @connection.post(path, params.compact)
      raise Error, "POST #{path} failed: #{response.status}" unless response.success?

      response.body
    end
  end
end
