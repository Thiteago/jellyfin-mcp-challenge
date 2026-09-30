# frozen_string_literal: true

class CheckMediaStatusTool < ApplicationTool
  description(
    'Verifica o status de um filme/série no Seerr antes de decidir se vale a pena pedir: ' \
    'se nunca foi pedido, se já está pendente/baixando, ou se já está disponível. ' \
    'Chame isso ANTES de request_media pra não duplicar um pedido que já está em andamento.'
  )

  arguments do
    required(:title).filled(:string).description('Título do filme ou série a verificar')
    required(:media_type).filled(:string).description('Tipo de mídia: "movie" para filme, "tv" para série')
  end

  def call(title:, media_type:)
    return respond_with(error: 'media_type precisa ser "movie" ou "tv"') unless %w[movie tv].include?(media_type)

    found = seerr_lookup(title, media_type)
    return respond_with(status: 'not_found', title: title) unless found

    respond_with(status: found[:status], title: found[:name], year: found[:year], tmdb_id: found[:id])
  rescue Seerr::Client::Error => e
    respond_with(error: e.message)
  end
end
