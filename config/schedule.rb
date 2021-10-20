# Copyright (C) 2021 TopDev

set :output, "log/cron.log"

every 1.minute do
  rake "sms:fetch_incoming_messages"
end
