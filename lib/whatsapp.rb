# Copyright (C) 2012-2015 Zammad Foundation, http://zammad-foundation.org/

class Whatsapp

  attr_accessor :client

=begin
check token and return bot attributes of token
  bot = Whatsapp.check_token('token')
=end

  def self.check_token(token)
    api = Whats::Api.new(token)
    begin
      bot = api.getMe()
    rescue
      raise Exceptions::UnprocessableEntity, 'invalid api token'
    end
    bot
  end

=begin
set webhook for bot
  success = Whatsapp.set_webhook('token', callback_url)
returns
  true|false
=end

  def self.set_webhook(token, callback_url)
    Rails.logger.debug { callback_url }

    if callback_url.match?(%r{^http://}i)
      raise Exceptions::UnprocessableEntity, 'webhook url need to start with https://, you use http://'
    end

    conn = Faraday.new(
      request: {params_encoder: Faraday::FlatParamsEncoder}
    )

    conn.headers = {
      'D360-Api-Key': token,
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    data = {
      url: callback_url
    }

    response = conn.post("https://waba.360dialog.io/v1/configs/webhook", data.to_json)
    if response.status != 200
      raise Exceptions::UnprocessableEntity, 'Unable to set webhook at Whatsapp, seems to be a invalid url.'
    end

    true
  end

=begin
create or update channel, store bot attributes and verify token
  channel = Whatsapp.create_or_update_channel('token', params)
returns
  channel # instance of Channel
=end

  def self.create_or_update_channel(api_token, params, channel = nil)
    if !channel && Whatsapp.bot_duplicate?(api_token, params[:phone_number], params[:bot_name])
      raise Exceptions::UnprocessableEntity, 'Bot already exists!'
    end

    # generate random callback token
    callback_token = if Rails.env.test?
                       'callback_token'
                     else
                       SecureRandom.urlsafe_base64(10)
                     end

    # set webhook / callback url for this bot @ whatsapp
    # callback_url = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/api/v1/channels_whatsapp_webhook/#{callback_token}"
    # callback_url = "https://zmd5.voipe.cc/api/v1/channels_whatsapp_webhook/#{callback_token}"
    callback_url = "https://ee04-82-103-129-80.ngrok.io/api/v1/channels_whatsapp_webhook/#{callback_token}"
    if Whatsapp.set_webhook(api_token, callback_url)
      if !channel
        channel = Channel.new
      end

      channel.area = 'WhatsApp::Bot'
      channel.options = {
        callback_token: callback_token,
        callback_url:   callback_url,
        api_token:      api_token,
        phone_number:   params[:phone_number],
        bot_name:       params[:bot_name],
      }
      channel.active = true
      channel.save!
      channel
    end
  end

=begin
check if bot already exists as channel
  success = Whatsapp.bot_duplicate?(bot_id)
returns
  channel # instance of Channel
=end

  def self.bot_duplicate?(api_token, phone_number=nil, bot_name=nil)
    Channel.where(area: 'WhatsApp::Bot').each do |channel|
      next if !channel.options[:api_token]
      next if !channel.options[:phone_number]
      next if !channel.options[:callback_token]
      next if channel.options[:api_token] != api_token and channel.options[:phone_number] != phone_number and channel.options[:bot_name] != bot_name

      return true
    end
    false
  end

=begin
get channel by bot_by_callback_token
  channel = Whatsapp.bot_by_callback_token(bot_id)
returns
  true|false
=end

  def self.bot_by_callback_token(callback_token)
    Channel.where(area: 'WhatsApp::Bot').each do |channel|
      next if !channel.options
      next if !channel.options[:callback_token]
      return channel if channel.options[:callback_token].to_s == callback_token.to_s
    end
    nil
  end

=begin
get media_id from message
  media_id = Whatsapp.media_id(message)
returns
  media_id # 776ce1c5-24e4-40f7-a25c-13981565036e
=end

  def self.media_id(params)
    media_id = 'text'

    case params[:messages][0][:type]
    when 'video'
      media_id = params[:messages][0][:video][:id]
    when 'voice'
      media_id = params[:messages][0][:voice][:id]
    when 'image'
      media_id = params[:messages][0][:image][:id]
    when 'document'
      media_id = params[:messages][0][:document][:id]
    end

    media_id
  end

=begin
  client = Whatsapp.new('token')
=end

  def initialize(token)
    @token = token
    # @api = Whats::Api.new(token)
  end

=begin
  client.message(chat_id, 'some message', language_code)
=end

  def message(chat_id, message, language_code = 'en')
    return if Rails.env.test?

    locale = Locale.find_by(alias: language_code)
    if !locale
      locale = Locale.where('locale LIKE :prefix', prefix: "#{language_code}%").first
    end

    if locale
      message = Translation.translate(locale[:locale], message)
    end

    @api.sendMessage(chat_id, message)
  end

  def user(params)
    {
      id:         params[:contacts][0][:wa_id],
      wa_name:    params[:contacts][0][:profile][:name],
      username:   params[:messages][0][:from]
    }
  end

  def to_user(params)
    Rails.logger.debug { 'Create user from message...' }
    Rails.logger.debug { params.inspect }

    # do message_user lookup
    begin
      message_user = user(params)
    rescue
      Rails.logger.debug  {
        "#{params[:statuses][0][:title]}"
      }
    end

    auth = Authorization.find_by(uid: message_user[:id], provider: 'whatsapp')

    # create or update user
    login = message_user[:id]
    user_data = {
      login:              login,
      mobile:             login,
      whatsapp_mobile:    login,
      firstname:          message_user[:wa_name],
    }
    if auth
      user = User.find(auth.user_id)
      user.update!(user_data)
    else
      user_data[:active]   = true
      user_data[:role_ids] = Role.signup_role_ids
      user                 = User.create(user_data)
    end

    # create or update authorization
    auth_data = {
      uid:      message_user[:id],
      username: login,
      user_id:  user.id,
      provider: 'whatsapp'
    }
    if auth
      auth.update!(auth_data)
    else
      Authorization.create(auth_data)
    end

    user
  end

  def to_ticket(params, user, group_id, channel)
    UserInfo.current_user_id = user.id

    Rails.logger.debug { 'Create ticket from message...' }
    Rails.logger.debug { params.inspect }
    Rails.logger.debug { user.inspect }

    # prepare title
    title = '-'
    %i[text].each do |area|
      next if !params[:messages]
      next if !params[:messages][0][area]
      next if !params[:messages][0][area][:body]

      title = params[:messages][0][area][:body]
      break
    end

    if title == '-'
      %i[video voice image contacts document].each do |area|

        next if !params[:messages]
        next if !params[:messages][0][area]

        title = params[:messages][0][area]
        break
      rescue
        # just go ahead
        title
      end
    end

    # find ticket or create one
    state_ids        = Ticket::State.where(name: %w[closed merged removed]).pluck(:id)
    possible_tickets = Ticket.where(customer_id: user.id).where.not(state_id: state_ids).order(:updated_at)
    ticket           = possible_tickets.find_each.find { |possible_ticket| possible_ticket.preferences[:channel_id].to_i == channel.id }

    if ticket
      # check if title need to be updated
      if ticket.title == '-'
        ticket.title = title
      end
      new_state = Ticket::State.find_by(default_create: true)
      if ticket.state_id != new_state.id
        ticket.state = Ticket::State.find_by(default_follow_up: true)
      end
      ticket.save!
      return ticket
    end

    ticket = Ticket.new(
      group_id:    1,
      title:       title,
      state_id:    Ticket::State.find_by(default_create: true).id,
      priority_id: Ticket::Priority.find_by(default_create: true).id,
      customer_id: user.id,
      preferences: {
        channel_id: channel.id,
        customer_phone_number: params[:contacts][0][:wa_id]
      },
      created_by_id: 1,
      updated_by_id: 1
      )
    ticket.save!
    ticket
  end

  def to_article(params, user, ticket, channel, article = nil)

    if article
      Rails.logger.debug { 'Update article from message...' }
    else
      Rails.logger.debug { 'Create article from message...' }
    end
    Rails.logger.debug { params.inspect }
    Rails.logger.debug { user.inspect }
    Rails.logger.debug { ticket.inspect }

    UserInfo.current_user_id = user.id
    media_id = Whatsapp.media_id(params)
    api_token = channel[:options][:api_token]

    if article
      article.preferences[:edited_message] = {
        message:   {
          created_at: params[:messages][0][:timestamp],
          message_id: params[:messages][0][:id],
          from:       params[:messages][0][:from],
        }
      }
    else
      article = Ticket::Article.new(
        ticket_id:   ticket.id,
        type_id:     Ticket::Article::Type.find_by(name: 'whatsapp personal-message').id,
        sender_id:   Ticket::Article::Sender.find_by(name: 'Customer').id,
        whatsapp_inbound: true,
        from:        params[:messages][0][:from],
        to:          "#{channel[:options][:phone_number]}",
        message_id:  params[:messages][0][:id],
        internal:    false,
        preferences: {
          message:   {
            from:       params[:messages][0][:from],
            type:       params[:messages][0][:type],
            media_id:   media_id,
            created_at: params[:messages][0][:timestamp],
          }
        }
      )
    end

    # add image
    if params[:messages][0][:type] == 'image'
      # find photo with best resolution for us
      photo = params[:messages][0][:image]

      # download photo
      photo_result = get_file(params, photo, api_token)
      body = "<img src=\"data:image/png;base64,#{Base64.strict_encode64(photo_result.body)}\">"

      if photo[:caption]
        body += "<br>#{photo[:caption].text2html}"
      end
      article.content_type = 'image/*'
      article.body         = body
      article.save!
      return article
    end

    # add document
    if params[:messages][0][:type] == 'document'

      document = params[:messages][0][:document]
      body     = '&nbsp;'

      document_result = get_file(params, document, api_token)
      if document[:caption]
        body += "#{document[:caption].text2html}"
      else
        body += "#{document[:id].text2html}"
      end
      article.content_type = 'text/html'
      article.body         = body
      article.save!

      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
        )
      Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        document_result.body,
        filename:    document[:filename],
        preferences: {
          'Mime-Type' => document[:mime_type],
        },
        )
      return article
    end

    # add video
    if params[:messages][0][:type] == 'video'
      video = params[:messages][0][:video]
      body = '&nbsp;'

      if video[:caption]
        body += "#{video[:caption].text2html}"
      else
        body += "#{video[:id].text2html}"
      end
      video_result         = get_file(params, video, api_token)
      article.content_type = 'text/html'
      article.body         = body
      article.save!

      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
        )

      # get video type
      type = video[:mime_type].gsub(%r{(.+/)}, '')
      Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        video_result.body,
        filename:    "video-#{video[:id]}.#{type}",
        preferences: {
          'Mime-Type' => video[:mime_type],
        },
        )
      return article
    end

    # add voice
    if params[:messages][0][:type] == 'voice'

      voice = params[:messages][0][:voice]
      body  = '&nbsp;'

      if params[:messages][0][:caption]
        body = "<br>#{params[:messages][0][:caption].text2html}"
      else
        body += "#{voice[:id].text2html}"
      end

      document_result      = get_file(params, voice, api_token)
      article.content_type = 'text/html'
      article.body         = body
      article.save!

      type = 'mp3'
      if voice[:mime_type] == 'audio/mpeg'
        type = 'mp3'
      end
      if voice[:mime_type] == 'audio/ogg'
        type = 'ogg'
      end
      if voice[:mime_type] == 'audio/vnd.wav'
        type = 'wav'
      end

      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
        )
      Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        document_result.body,
        filename:    voice[:file_path] || "audio-#{voice[:id]}.#{type}",
        preferences: {
          'Mime-Type' => voice[:mime_type],
        },
        )
      return article
    end

    # add sticker
    if params[:messages][0][:sticker]

      sticker = params[:messages][0][:sticker]
      emoji   = sticker[:emoji]
      thumb   = sticker[:thumb]
      body    = '&nbsp;'

      if thumb
        width  = thumb[:width]
        height = thumb[:height]
        thumb_result = get_file(params, thumb, api_token)
        body = "<img style=\"width:#{width}px;height:#{height}px;\" src=\"data:image/webp;base64,#{Base64.strict_encode64(thumb_result.body)}\">"
        article.content_type = 'text/html'
      elsif emoji
        article.content_type = 'text/plain'
        body = emoji
      end

      article.body = body
      article.save!

      if sticker[:file_id]

        document_result = get_file(params, sticker, api_token)
        Store.remove(
          object: 'Ticket::Article',
          o_id:   article.id,
          )
        Store.add(
          object:      'Ticket::Article',
          o_id:        article.id,
          data:        document_result.body,
          filename:    sticker[:file_name] || "#{sticker[:set_name]}.webp",
          preferences: {
            'Mime-Type' => 'image/webp', # mime type is not given from Whatsapp API but this is actually WebP
          },
          )
      end
      return article
    end

    # add text
    if params[:messages][0][:text]
      article.content_type = 'text/plain'
      article.body = params[:messages][0][:text][:body]
      article.save!
      return article
    end
    raise Exceptions::UnprocessableEntity, 'invalid whatsapp message'
  end

  def to_group(params, group_id, channel)
    # begin import
    Rails.logger.debug { 'import message' }

    ticket = nil

    # use transaction
    begin
      Transaction.execute(reset_user_id: true) do
        user   = to_user(params)
        ticket = to_ticket(params, user, group_id, channel)
        to_article(params, user, ticket, channel)
      end
    rescue
      Rails.logger.debug {"Error message &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&"}
    end

    ticket
  end

  def from_article(article)

    message = nil
    Rails.logger.debug { "Create whatsapp personal message from article to '#{article[:to]}'..." }

    message = {}
    # TODO: create whatsapp message here

    Rails.logger.debug { message.inspect }
    message
  end

  def get_file(params, file, api_token)
    result = download_file(file[:id], api_token)

    if !validate_download(result)
      message_text = 'Unable to get you file from bot.'
      message(params[:messages][:chat][:id], "Sorry, we could not handle your message. #{message_text}", params[:messages][:from][:language_code])
      raise Exceptions::UnprocessableEntity, message_text
    end

    result
  end

  def download_file(file_id, api_token)
    conn = Faraday.new(
      request: {params_encoder: Faraday::FlatParamsEncoder}
    )

    conn.headers = {
      'D360-Api-Key': api_token,
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    response = conn.get("https://waba.360dialog.io/v1/media/%s" % [file_id])

    response
  end

  def validate_file_size(file)
    Rails.logger.error 'validate_file_size'
    Rails.logger.error file[:file_size]
    return false if file[:file_size] >= 20.megabytes

    true
  end

  def validate_download(result)
    return false if result.status != 200

    true
  end

end
