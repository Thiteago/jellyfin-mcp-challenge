# frozen_string_literal: true

class GetMediaDetailsTool < ApplicationTool
  description 'Retorna detalhes completos de um item do Jellyfin: sinopse, elenco, duração e nota'

  arguments do
    required(:item_id).filled(:string).description('ID do item no Jellyfin (retornado por outras tools, ex: random_movie)')
  end

  def call(item_id:)
    item = jellyfin.item_details(item_id)

    respond_with(
      id: item['Id'],
      name: item['Name'],
      year: item['ProductionYear'],
      genres: item['Genres'],
      overview: item['Overview'],
      community_rating: item['CommunityRating'],
      runtime_minutes: item['RunTimeTicks'] ? item['RunTimeTicks'] / 600_000_000 : nil,
      cast: Array(item['People']).select { |p| p['Type'] == 'Actor' }.map { |p| p['Name'] }
    )
  end
end
