# frozen_string_literal: true

class GetActiveSessionsTool < ApplicationTool
  description 'Lista quem está assistindo o quê agora no servidor Jellyfin'

  def call
    sessions = jellyfin.active_sessions

    watching = sessions.select { |s| s['NowPlayingItem'] }.map do |session|
      {
        user: session['UserName'],
        device: session['DeviceName'],
        watching: session.dig('NowPlayingItem', 'Name')
      }
    end

    respond_with(active_count: watching.size, sessions: watching)
  end
end
