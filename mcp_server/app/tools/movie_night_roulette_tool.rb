# frozen_string_literal: true

class MovieNightRouletteTool < ApplicationTool
  description 'Sorteia um filme para a noite e sugere uma combinação de pipoca/bebida de acordo com o gênero'

  PAIRINGS = {
    'Horror' => 'pipoca salgada + luzes apagadas',
    'Comedy' => 'pipoca doce + refrigerante',
    'Romance' => 'vinho + chocolate',
    'Action' => 'energético + salgadinho',
    'Drama' => 'chá quente + biscoito',
    'Animation' => 'pipoca colorida + suco'
  }.freeze
  DEFAULT_PAIRING = 'pipoca + o que tiver na geladeira'

  arguments do
    optional(:genre).filled(:string).description('Gênero desejado para a noite, ex: "Horror". Se omitido, sorteia qualquer gênero')
  end

  def call(genre: nil)
    movies = jellyfin.items(genres: genre, sort_by: 'Random', limit: 1)
    return respond_with(error: 'Nenhum filme encontrado com esse gênero') if movies.empty?

    movie = summarize_item(movies.first)
    pairing_genre = movie[:genres]&.find { |g| PAIRINGS.key?(g) }

    respond_with(movie.merge(suggested_pairing: PAIRINGS.fetch(pairing_genre, DEFAULT_PAIRING)))
  end
end
