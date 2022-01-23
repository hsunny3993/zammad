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
    callback_url = "https://zmd5.voipe.cc/api/v1/channels_whatsapp_webhook/#{callback_token}"
    # callback_url = "https://1c21-82-103-129-80.ngrok.io/api/v1/channels_whatsapp_webhook/#{callback_token}"
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
    Rails.logger.info { params.inspect }

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
      Rails.logger.info { 'Update user from message...' }
      user = User.find(auth.user_id)
      user.update!(user_data)
    else
      user = User.where(mobile: login).first
      user_data[:active] = true
      user_data[:role_ids] = Role.signup_role_ids

      if user
        Rails.logger.info { 'Update user from message...' }
        user.update(user_data)
      else
        Rails.logger.info { 'Create user from message...' }
        user = User.create(user_data)
      end
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

    Rails.logger.info { params.inspect }
    Rails.logger.info { user.inspect }

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
      Rails.logger.info { 'Update ticket from message...' }
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

    Rails.logger.info { 'Create ticket from message...' }
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
      photo = params[:messages][0][:image]

      # download photo
      photo_result = get_file(params, photo, api_token)

      # body = "<img src=\"data:image/png;base64,#{Base64.strict_encode64(photo_result.body)}\" style=\"width: 100%;\">"
      # if photo[:caption]
      #   body += "<br>#{photo[:caption].text2html}"
      # end

      body = '&nbsp;'
      begin
        if photo[:caption]
          body += "<br>#{photo[:caption].text2html}"
        end
      rescue
        body = "&nbsp;"
      end

      article.content_type = photo[:mime_type]
      article.body         = body
      article.save!

      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
        )

      type = photo[:mime_type].gsub(%r{(.+/)}, '')
      if type == 'jpeg'
        type = 'jpg'
      end

      Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        photo_result.body,
        filename:    "image-#{photo[:id]}.#{type}",
        preferences: {
          'Mime-Type' => photo[:mime_type],
        },
        )

      return article
    end

    # add document
    if params[:messages][0][:type] == 'document'
      document = params[:messages][0][:document]
      document_result = get_file(params, document, api_token)

      body = '&nbsp;'
      begin
        if document[:caption]
          body += "#{document[:caption].text2html}"
        end
      rescue
        body = '&nbsp;'
      end

      article.content_type = document[:mime_type]
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

      body  = '&nbsp;'
      begin
        body += if video[:caption]
                  "#{video[:caption].text2html}"
                end
      rescue
        body = '&nbsp;'
      end
      video_result         = get_file(params, video, api_token)
      article.content_type = video[:mime_type]
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

      begin
        body = '&nbsp;'
        if params[:messages][0][:caption]
          body = "<br>#{voice[:caption].text2html}"
        end
      rescue
        body = '&nbsp;'
      end

      document_result      = get_file(params, voice, api_token)
      article.content_type = voice[:mime_type]
      article.body         = body
      article.save!

      type = 'mp3'
      mime_type = voice[:mime_type]
      if voice[:mime_type] == 'audio/mpeg'
        type = 'mp3'
      end
      if voice[:mime_type] == 'audio/ogg; codecs=opus'
        type = 'mp3' # opus codec is converted to mp3
        voice[:mime_type] = 'audio/mpeg'
      end
      if voice[:mime_type] == 'audio/vnd.wav'
        type = 'wav'
      end
      if voice[:mime_type] == 'audio/aac'
        type = 'aac'
      end
      if voice[:mime_type] == 'audio/amr'
        type = 'amr'
      end
      if voice[:mime_type] == 'audio/mp4'
        type = 'mp4'
      end

      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
      )
      store = Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        document_result.body,
        filename:    voice[:file_path] || "audio-#{voice[:id]}.#{type}",
        preferences: {
          'Mime-Type' => voice[:mime_type],
        },
      )

      # converting opus codec audio into mp3(mpeg codec)
      if mime_type == 'audio/ogg; codecs=opus'
        store_file = Store::File.find(store[:store_file_id])
        sha = store_file[:sha]
        file_path = "#{Store::Provider::File.get_location(sha)}"
        system("ffmpeg -i #{file_path} -vn -ar 44100 -ac 2 -f mp3 #{file_path}.mp3")
        system("mv #{file_path}.mp3 #{file_path}")
        store.update!(size: File.stat(file_path).size)
      end

      return article
    end

    # add sticker
    if params[:messages][0][:sticker]
      sticker = params[:messages][0][:sticker]

      body = '&nbsp;'
      sticker_result = get_file(params, sticker, api_token)

      article.content_type = sticker[:mime_type]
      article.body = body
      article.save!

      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
      )

      type = sticker[:mime_type].gsub(%r{(.+/)}, '')

      Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        sticker_result.body,
        filename:    "#{sticker[:metadata]["sticker-pack-id"]}.#{type}",
        preferences: {
          'Mime-Type' => sticker[:mime_type],
        },
      )
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
      Rails.logger.info { "New message arrived from WA" }
      Transaction.execute(reset_user_id: true) do
        user   = to_user(params)
        ticket = to_ticket(params, user, group_id, channel)
        to_article(params, user, ticket, channel)
      end
    rescue Exception => e
      Rails.logger.debug {"Error message &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&#{e}"}
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
