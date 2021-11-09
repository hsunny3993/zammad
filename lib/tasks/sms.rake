# Copyright (C) 2021 TopDev

require 'rubygems'

namespace :sms do
  desc "Fetch incoming sms messages from Voipe Playsms"
  task fetch_incoming_messages: :environment do
    conn = Faraday.new(
      request: {params_encoder: Faraday::FlatParamsEncoder}
    )

    channel = Channel.where('active = ? AND area LIKE ?', true, 'Sms::Account').first
    last_sms_article = Ticket::Article.where('preferences LIKE ?', "%channel_id: #{channel.id}%").order(updated_at: :asc).first

    if channel
      if last_sms_article.nil?
        response = conn.get("http://sms.voipe.co.il/playsms/index.php", {
          app: 'ws',
          u: channel.options[:account_id],
          h: channel.options[:token],
          op: 'ix'
        })
      else
        response = conn.get("http://sms.voipe.co.il/playsms/index.php", {
          app: 'ws',
          u: channel.options[:account_id],
          h: channel.options[:token],
          last: last_sms_article.message_id,
          op: 'ix'
        })
      end

      json_response = JSON.parse(response.body)
      status = json_response['status']
      error_code = json_response['error']

      if status == "ERR" && error_code != "501"
        puts 'Unable to fetch incoming SMS message.'
        puts json_response
      end

      if status != "ERR"
        data = json_response['data']
        data.each { |sms|
          sms['account_sid'] = channel.options[:account_id]
          adapter = channel.options[:adapter]
          driver_class = "::Channel::Driver::#{adapter.to_classname}".constantize
          driver_instance = driver_class.new
          driver_instance.process(sms)
        }
      end
    end
  end
end
