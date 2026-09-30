# frozen_string_literal: true

class SearchMediaTool < ApplicationTool
  description(
    'Busca filmes na biblioteca LOCAL do Jellyfin (o que já está disponível pra assistir) por título, ' \
    'gênero e/ou ano. Se não encontrar nada, isso NÃO significa que o título nunca foi pedido — use ' \
    'check_media_status pra ver se já está pendente/baixando via Seerr antes de sugerir um novo pedido.'
  )

  arguments do
    optional(:query).filled(:string).description('Termo de busca no título do filme')
    optional(:genre).filled(:string).description('Filtra por gênero, ex: "Action", "Drama"')
    optional(:year).filled(:integer).description('Filtra por ano de lançamento')
    optional(:limit).filled(:integer).description('Número máximo de resultados (padrão 10)')
  end

  def call(query: nil, genre: nil, year: nil, limit: 10)
    movies = jellyfin.items(
      search_term: query,
      genres: genre,
      years: year,
      limit: limit
    )

    respond_with(results: movies.map { |item| summarize_item(item) })
  end
end
