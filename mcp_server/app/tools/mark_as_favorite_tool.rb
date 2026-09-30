# frozen_string_literal: true

class MarkAsFavoriteTool < ApplicationTool
  description 'Marca um item do Jellyfin como favorito para o usuário configurado'

  arguments do
    required(:item_id).filled(:string).description('ID do item no Jellyfin a ser marcado como favorito')
  end

  def call(item_id:)
    result = jellyfin.mark_as_favorite(item_id)

    respond_with(success: true, is_favorite: result['IsFavorite'])
  end
end
