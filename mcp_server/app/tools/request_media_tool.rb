# frozen_string_literal: true

class RequestMediaTool < ApplicationTool
  description(
    'Pede pra baixar um filme ou série que ainda não está no Jellyfin, via Seerr (dispara o download ' \
    'automaticamente no *arr stack). Segura pra chamar direto: sempre confere o status antes e nunca ' \
    'duplica um pedido que já está pendente/baixando/disponível — nesse caso só informa o status atual.'
  )

  # Anything already past "never requested" means a request already exists —
  # calling create_request again would just duplicate it in the *arr stack.
  ALREADY_HANDLED_STATUSES = %w[pending processing partially_available available].freeze

  arguments do
    required(:title).filled(:string).description('Título do filme ou série a pedir')
    required(:media_type).filled(:string).description('Tipo de mídia: "movie" para filme, "tv" para série')
    optional(:seasons).array(:integer).description(
      'Números das temporadas a pedir (só pra séries). Se omitido, pede todas as temporadas.'
    )
  end

  def call(title:, media_type:, seasons: nil)
    return respond_with(error: 'media_type precisa ser "movie" ou "tv"') unless %w[movie tv].include?(media_type)

    found = seerr_lookup(title, media_type)
    return respond_with(error: "Nenhum(a) #{media_type == 'movie' ? 'filme' : 'série'} encontrado(a) com esse título") unless found

    if ALREADY_HANDLED_STATUSES.include?(found[:status])
      return respond_with(already_requested: true, status: found[:status], title: found[:name], year: found[:year])
    end

    seerr.create_request(media_id: found[:id], media_type: media_type, seasons: media_type == 'tv' ? seasons : nil)

    respond_with(requested: true, title: found[:name], year: found[:year], media_type: media_type)
  rescue Seerr::Client::Error => e
    respond_with(error: e.message)
  end
end
