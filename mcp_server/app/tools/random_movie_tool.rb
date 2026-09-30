# frozen_string_literal: true

class RandomMovieTool < ApplicationTool
  description 'Sorteia um filme aleatório da biblioteca do Jellyfin, com filtros opcionais de gênero e de não-assistidos'

  arguments do
    optional(:genre).filled(:string).description('Filtra por gênero, ex: "Comedy", "Horror"')
    optional(:unwatched_only).filled(:bool).description('Se true, sorteia apenas entre filmes ainda não assistidos')
  end

  def call(genre: nil, unwatched_only: false)
    movies = jellyfin.items(
      genres: genre,
      unwatched_only: unwatched_only,
      sort_by: 'Random',
      limit: 1
    )

    return respond_with(error: 'Nenhum filme encontrado com esses filtros') if movies.empty?

    respond_with(summarize_item(movies.first))
  end
end
