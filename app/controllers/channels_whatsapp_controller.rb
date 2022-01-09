# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class ChannelsWhatsappController < ApplicationController
  prepend_before_action -> { authentication_check && authorize! }, except: [:webhook]
  skip_before_action :verify_csrf_token, only: [:webhook]

  def index
    assets = {}
    channel_ids = []
    Channel.where(area: 'WhatsApp::Bot').order(:id).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push channel.id
    end

    render json: {
      assets:      assets,
      channel_ids: channel_ids
    }
  end

  def add
    begin
      channel = Whatsapp.create_or_update_channel(params[:api_token], params)
    rescue => e
      raise Exceptions::UnprocessableEntity, e.message
    end
    render json: channel
  end

  def update
    channel = Channel.find_by(id: params[:id], area: 'WhatsApp::Bot')
    begin
      channel = Whatsapp.create_or_update_channel(params[:api_token], params, channel)
    rescue => e
      raise Exceptions::UnprocessableEntity, e.message
    end
    render json: channel
  end

  def enable
    channel = Channel.find_by(id: params[:id], area: 'WhatsApp::Bot')
    channel.active = true
    channel.save!
    render json: {}
  end

  def disable
    channel = Channel.find_by(id: params[:id], area: 'WhatsApp::Bot')
    channel.active = false
    channel.save!
    render json: {}
  end

  def destroy
    channel = Channel.find_by(id: params[:id], area: 'WhatsApp::Bot')
    channel.destroy
    render json: {}
  end

  def webhook
    Rails.logger.info { "############### NEW MESSAGE FROM WA ################" }
    Rails.logger.debug { params['callback_token'] }
    raise Exceptions::UnprocessableEntity, 'callback_token is missing' if params['callback_token'].blank?

    channel = Whatsapp.bot_by_callback_token(params['callback_token'])
    raise Exceptions::UnprocessableEntity, 'bot not found' if !channel

    whatsapp = Whatsapp.new(channel.options[:api_token])
    begin
      whatsapp.to_group(params, channel.group_id, channel)
    rescue Exceptions::UnprocessableEntity => e
      Rails.logger.error e.message
    end

    render json: {}, status: :ok
  end

end
