# frozen_string_literal: true

class ApplicationTool < ActionTool::Base
  def jellyfin
    @jellyfin ||= Jellyfin::Client.new
  end

  def seerr
    @seerr ||= Seerr::Client.new
  end

  # Shared by request_media and check_media_status: finds the best Seerr
  # search match for a title and normalizes the fields both tools need,
  # including the human-readable Seerr status (not_found/pending/processing/
  # partially_available/available/unknown).
  def seerr_lookup(title, media_type)
    match = seerr.search(title, media_type: media_type).first
    return nil unless match

    {
      id: match['id'],
      name: match['title'] || match['name'],
      year: (match['releaseDate'] || match['firstAirDate']).to_s[0, 4],
      status: Seerr::Client.status_label(match.dig('mediaInfo', 'status'))
    }
  end

  # Trims down a Jellyfin item to the fields the model actually needs,
  # keeping tool responses small and easy for the LLM to reason about.
  def summarize_item(item)
    {
      id: item['Id'],
      name: item['Name'],
      year: item['ProductionYear'],
      genres: item['Genres'],
      overview: item['Overview'],
      community_rating: item['CommunityRating']
    }
  end

  # fast-mcp only serializes a tool's return value as real JSON when it is a
  # Hash with a :content key; otherwise it falls back to Ruby's Hash#to_s.
  # Every tool should route its result through this before returning.
  def respond_with(data)
    { content: [{ type: 'text', text: data.to_json }], isError: false }
  end
end
