# frozen_string_literal: true

module Seerr
  # Thin HTTP wrapper around the Seerr API (formerly Jellyseerr/Overseerr —
  # the projects merged into "Seerr" in 2026). Used to search TMDB and submit
  # media requests that the *arr stack picks up and downloads automatically.
  # Docs: https://docs.seerr.dev/
  class Client
    class Error < StandardError; end

    STATUS_AVAILABLE = 5
    STATUS_LABELS = {
      1 => 'unknown',
      2 => 'pending', # requested, waiting on approval/start
      3 => 'processing', # actively downloading
      4 => 'partially_available',
      5 => 'available',
      6 => 'deleted'
    }.freeze

    def self.status_label(status_code)
      STATUS_LABELS.fetch(status_code, 'not_requested')
    end

    module PercentParamsEncoder
      def self.encode(params)
        return nil if params.nil?

        params.map { |k, v| "#{ERB::Util.url_encode(k.to_s)}=#{ERB::Util.url_encode(v.to_s)}" }.join('&')
      end

      def self.decode(query)
        Faraday::Utils.default_params_encoder.decode(query)
      end
    end

    def initialize(base_url: ENV.fetch('SEERR_URL'), api_key: ENV.fetch('SEERR_API_KEY'))
      @connection = Faraday.new(url: "#{base_url}/api/v1") do |f|
        f.headers['X-Api-Key'] = api_key
        f.options.params_encoder = PercentParamsEncoder
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.adapter Faraday.default_adapter
      end
    end

    # media_type filters results to "movie" or "tv"
    def search(query, media_type:)
      results = get('search', query: query).fetch('results', [])
      results.select { |r| r['mediaType'] == media_type }
    end

    def create_request(media_id:, media_type:, seasons: nil)
      body = { mediaType: media_type, mediaId: media_id }
      server_id = best_server_id(media_type)
      body[:serverId] = server_id if server_id
      body[:seasons] = seasons if seasons

      post('request', body)
    end

    private

    def best_server_id(media_type)
      service = media_type == 'tv' ? 'sonarr' : 'radarr'
      servers = get("service/#{service}")
      return nil if servers.empty?

      root_folders = get("service/#{service}/#{servers.first['id']}").fetch('rootFolders', [])
      best_path = root_folders.max_by { |f| f['freeSpace'] }&.fetch('path', nil)
      return nil unless best_path

      matching_server = servers.find { |s| s['activeDirectory'] == best_path }
      (matching_server || servers.first)['id']
    rescue Error
      nil
    end

    def get(path, params = {})
      response = @connection.get(path, params.compact)
      raise Error, "GET #{path} failed: #{response.status}" unless response.success?

      response.body
    end

    def post(path, body)
      response = @connection.post(path, body.compact)
      raise Error, "POST #{path} failed: #{response.status} #{response.body}" unless response.success?

      response.body
    end
  end
end
