class CommunicateWhatsappJob < ApplicationJob

  retry_on StandardError, attempts: 4, wait: lambda { |executions|
    executions * 120.seconds
  }

  def perform(article_id)
    article = Ticket::Article.find(article_id)

    # set retry count
    article.preferences['delivery_retry'] ||= 0
    article.preferences['delivery_retry'] += 1

    ticket = Ticket.lookup(id: article.ticket_id)
    log_error(article, "Can't find ticket.preferences for Ticket.find(#{article.ticket_id})") if !ticket.preferences
    log_error(article, "Can't find ticket.preferences['customer_phone_number'] for Ticket.find(#{article.ticket_id})") if !ticket.preferences['customer_phone_number']

    channel = Channel.lookup(id: ticket.preferences['channel_id'])
    log_error(article, "No such channel for channel id #{ticket.preferences['channel_id']}") if !channel
    log_error(article, "Channel.find(#{channel.id}) has not whatsapp api token!") if channel.options[:api_token].blank?

    begin
      conn = Faraday.new(
        request: {params_encoder: Faraday::FlatParamsEncoder}
      )

      conn.headers = {
        'D360-Api-Key'=> channel.options[:api_token],
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }

      data = {
        recipient_type: "individual",
        to: ticket.preferences["customer_phone_number"],
        type: "text",
        text: {
          body: article.body
        }
      }

      response = conn.post("https://waba.360dialog.io/v1/messages", data.to_json)
      if response.status != 201
        raise Exceptions::UnprocessableEntity, 'Unable to send reply message.'
      end

      article.attachments.each do |file|
        parts = file.filename.split(%r{^(.*)(\..+?)$})
        t = Tempfile.new([parts[1], parts[2]])
        t.binmode
        t.write(file.content)
        t.rewind

        # UPLOAD A MEDIA TO FACEBOOK WHATSAPP SERVER
        content_type = file.preferences["Content-Type"]
        conn = Faraday.new(
          url: 'https://waba.360dialog.io',
          headers: {
            'D360-Api-Key' => channel.options[:api_token],
            'Content-Type' => content_type
          }
        )

        # payload = { :file => Faraday::UploadIO.new(t.path.to_s, content_type) }
        # payload = { :file => File.new(t.path.to_s) }
        payload = File.binread(t.path.to_s)
        # payload = URI.encode_www_form(payload)
        media_response = conn.post('/v1/media', payload)
        if media_response.status != 201
          raise Exceptions::UnprocessableEntity, 'Unable to send reply message.'
        end

        media_id = JSON.parse(media_response.body)["media"].first["id"]

        # Send Media whatsapp message
        conn = Faraday.new(
          request: {params_encoder: Faraday::FlatParamsEncoder}
        )

        conn.headers = {
          'D360-Api-Key'=> channel.options[:api_token],
          "Content-Type" => "application/json",
        }

        data = {
          recipient_type: "individual",
          to: ticket.preferences["customer_phone_number"],
        }

        if ['audio/aac', 'audio/mp4', 'audio/amr', 'audio/mpeg', 'audio/ogg'].include? content_type
          data['type'] = "audio"
          data['audio'] = { id: media_id }
        end

        if ['image/jpeg', 'image/png'].include? content_type
          data['type'] = "image"
          data['image'] = { id: media_id }
        end

        if content_type == 'image/webp'
          data['type'] = "sticker"
          data['sticker'] = { id: media_id }
        end

        if ['video/mp4', 'video/3gpp'].include? content_type
          data['type'] = "video"
          data['video'] = { id: media_id }
        end

        if content_type == 'application/pdf'
          data['type'] = "document"
          data['document'] = {
            id: media_id,
            filename: file.filename
          }
        end

        response = conn.post("https://waba.360dialog.io/v1/messages", data.to_json)
        if response.status != 201
          raise Exceptions::UnprocessableEntity, 'Unable to send reply message.'
        end
      end
    rescue Exception => e
      log_error(article, e.message)
      return
    end

    message_id = JSON.parse(response.body)["messages"].first["id"]
    article.from = channel.options[:phone_number]
    article.to = ticket.preferences["customer_phone_number"]
    article.preferences['whatsapp'] = {
      message_id: message_id
    }

    # set delivery status
    article.preferences['delivery_status_message'] = nil
    article.preferences['delivery_status'] = 'success'
    article.preferences['delivery_status_date'] = Time.zone.now

    article.message_id = "#{message_id}"

    article.save!

    Rails.logger.info "Send whatsapp message to: '#{article.to}' (from #{article.from})"

    article
  end

  def log_error(local_record, message)
    local_record.preferences['delivery_status'] = 'fail'
    local_record.preferences['delivery_status_message'] = message.encode!('UTF-8', 'UTF-8', invalid: :replace, replace: '?')
    local_record.preferences['delivery_status_date'] = Time.zone.now
    local_record.save
    Rails.logger.error message

    if local_record.preferences['delivery_retry'] > 3
      Ticket::Article.create(
        ticket_id:     local_record.ticket_id,
        content_type:  'text/plain',
        body:          "Unable to send whatsapp message: #{message}",
        internal:      true,
        sender:        Ticket::Article::Sender.find_by(name: 'System'),
        type:          Ticket::Article::Type.find_by(name: 'note'),
        preferences:   {
          delivery_article_id_related: local_record.id,
          delivery_message:            true,
        },
        updated_by_id: 1,
        created_by_id: 1,
        )
    end

    raise message
  end
end
