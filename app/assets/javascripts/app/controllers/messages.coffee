class App.Messages extends App.Controller
  clueAccess: false

  @tickets = {}
  @users = {}
  @ticketArticleIds = {}
  @ticketIds = []
  @dropzone = undefined
  @channelType = undefined
  @ticketUpdatedAtLastCall = undefined
  @emojioneArea = undefined
  @mediaRecorder = {}
  @buffArray = []
  @pageIndex = 0
  @perPage = 20

  constructor: ->
    super

    # fetch new data if triggered
    @controllerBind('Ticket:update', (data) =>
      console.log(data)
      @fetchMayBe(data)
    )

    # render page
    @render()

    # rerender view, e. g. on language change
    @controllerBind('ui:rerender', =>
      return if !@authenticateCheck()
      @render()
    )

  T: (name) ->
    App.i18n.translateInline(name)

  getShortMsg: (article) ->
    if !article
      return ''

    mimeType = ""
    if typeof article.attachments != "undefined"
      if article.attachments.length > 0
        msgType = article.attachments[0]['preferences']['Mime-Type']
        attachmentId = article.attachments[0]['id']

        if typeof msgType == "undefined"
          msgType = article.attachments[0]['preferences']['Content-Type']

    content = ""
    if msgType && msgType == "application/pdf"
      content = @T("(PDF)")

    if msgType && msgType.startsWith("audio")
      content = @T("(Audio)")

    if msgType && msgType.startsWith("video")
      content = @T("(Video)")

    if article.content_type && article.content_type.startsWith("image")
      content = @T("(Image)")

    if content == ""
      content = article.body

    if content.length > 10
      content = content[0..10] + "..."

    return content

  fetchMayBe: (data) ->
    prevTicketOwner = undefined
    if App.Messages.tickets[data.id]
      ticketUpdatedAtLastCall = App.Messages.tickets[data.id].updated_at
      if ticketUpdatedAtLastCall
        if new Date(data.updated_at).getTime() is new Date(ticketUpdatedAtLastCall).getTime()
          return
        if new Date(data.updated_at).getTime() < new Date(ticketUpdatedAtLastCall).getTime()
          return

      App.Messages.tickets[data.id].updated_at = data.updated_at
      prevTicketOwner = App.Messages.tickets[data.id].owner_id

    ticketIdWithNewArticles = data.id
    me = App.Session.get('id')

    $.ajax(
      type:  'GET'
      url:   "#{App.Config.get('api_path')}/tickets/#{ticketIdWithNewArticles}?all=true"
      processData: true
      success: (data, status, xhr) =>
        ticket = data.assets.Ticket[ticketIdWithNewArticles]

        # if ticket was closed: 4(pending closed), 5(closed)
        if ticket.state_id in [4, 5]
          $("li.nv-item-active[data-ticket-id='#{ticket.id}']").attr("data-ticket-status", "closed")
          $("li.nv-item-active[data-ticket-id='#{ticket.id}']").css("display", "none")
          return

        # if ticket was assgined to me
        if ticket.owner_id == me and prevTicketOwner != ticket.owner_id
          $("li.nv-item-active[data-ticket-id='#{ticket.id}']").attr("data-mine", "mine")
          return

        App.Messages.users = data.assets.User
        ticket.customer = data.assets.User[ticket.customer_id]
        ticket.owner = data.assets.User[ticket.owner_id]
        curActiveTicketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))

        if App.Messages.tickets[ticketIdWithNewArticles] == null || typeof App.Messages.tickets[ticketIdWithNewArticles] == "undefined"
          App.Messages.tickets[ticketIdWithNewArticles] = ticket

        oldNum = parseInt($("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name i").text())
        oldNum = if isNaN(oldNum) then 0 else oldNum

        # Checks if the ticket is currently displayed as active
        if ticketIdWithNewArticles == curActiveTicketId
          newArticleNums = 0
          for articleId in data.ticket_article_ids
            if articleId not in App.Messages.ticketArticleIds[ticketIdWithNewArticles]
              article = data.assets.TicketArticle[articleId]

              @renderArticle(article, true)
              @renderAvatar(".avatar-#{article.created_by_id}", article.created_by_id)
              @renderBadge(".avatar-#{article.created_by_id} > span", ticket)

              if article.created_by_id != me
                newArticleNums++

          if article
            if newArticleNums > 0
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name i").remove()
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name").append("<i class='badge-icon badge-new'>#{newArticleNums + oldNum}</i>")
            content = @getShortMsg(article)
            article.body = content
            App.Messages.tickets[ticketIdWithNewArticles]['last_article'] = article
            App.Messages.ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
            $("li[data-ticket-id=#{ticketIdWithNewArticles}] div.nv-recent-message span.nv-recent-msg").text(content)

        else # If the ticket is currently not displayed as active
          # Checks if the ticket is new
          if ticketIdWithNewArticles not in App.Messages.ticketIds
            App.Messages.ticketIds.push(ticketIdWithNewArticles)
            App.Messages.ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
            App.Messages.tickets[ticketIdWithNewArticles] = ticket

            lastArticle = data.assets.TicketArticle[Object.keys(data.assets.TicketArticle)[Object.keys(data.assets.TicketArticle).length - 1]]
            content = @getShortMsg(lastArticle)
            lastArticle.body = content
            App.Messages.tickets[ticketIdWithNewArticles]['last_article'] = lastArticle

            activeClass = ""
            badgeClass = @getChannelBadge(ticket.create_article_type_id)
            if isNaN(curActiveTicketId)
              activeClass = "nv-item-active"

            is_mine = ""
            if me == ticket.owner_id
              is_mine = 'mine'

            ticket_state_type_id = App.TicketState.findNative(ticket.state_id).state_type_id
            ticket_state_name = App.TicketStateType.findNative(ticket_state_type_id).name
            if ticket_state_name != "closed"
              ticket_state_name = ""

            ticketHTML = """
              <li class="nv-item #{activeClass}" data-ticket-id="#{ticketIdWithNewArticles}" data-customer-id="#{ticket.customer_id}" data-article-type-id="#{ticket.create_article_type_id}" data-ticket-status="#{ticket_state_name}" data-mine="#{is_mine}">
                <a href="#">
                    <span class="nv-item-avatar" id="avatar-#{ticket.id}"></span>
                    <div class="nv-body">
                      <div class="nv-name">
                        <span class="nv-contact-name">
                          #{ticket.customer.firstname} #{ticket.customer.lastname}
                          <i class="badge-icon badge-new">#{Object.keys(data.assets.TicketArticle).length}</i>
                        </span>
                        <span class="nv-item-time">#{@T(@formattedDateTime(lastArticle.updated_at))}</span>
                      </div>
                      <div class="nv-recent-message">
                        <span class="nv-recent-msg">#{content}</span>
                        <span class="nv-options">
                          <i class="badge-icon #{badgeClass}"></i>
                        </span>
                      </div>
                    </div>
                  </a>
              </li>
            """

            $(".contacts ul.nv-items").prepend(ticketHTML)
            @renderAvatar("span#avatar-#{ticket.id}", ticket.customer_id)

            App.Messages.ticketIds.push(ticketIdWithNewArticles)
            App.Messages.ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
            if isNaN(curActiveTicketId)
              @displayHistory(ticketIdWithNewArticles, ticket.create_article_type_id)
          else
            newArticleNums = 0
            for articleId in data.ticket_article_ids
              if articleId not in App.Messages.ticketArticleIds[ticketIdWithNewArticles]
                newArticleNums++
                article = data.assets.TicketArticle[articleId]

            if article
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name i").remove()
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name").append("<i class='badge-icon badge-new'>#{newArticleNums + oldNum}</i>")
              content = @getShortMsg(article)
              article.body = content
              App.Messages.tickets[ticketIdWithNewArticles]['last_article'] = article
              App.Messages.ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] div.nv-recent-message span.nv-recent-msg").text(content)

        @moveTicketToTop(ticketIdWithNewArticles)
        @ticketClickHandler()
        @historyClickHandler()
      error: (xhr) =>
        statusText = xhr.statusText
        status     = xhr.status
        detail     = xhr.responseText

        # ignore if request is aborted
        return if statusText is 'abort'

        @renderDone = false

        # if ticket is already loaded, ignore status "0" - network issues e. g. temp. not connection
        if App.Messages.ticketUpdatedAtLastCall && status is 0
          console.log('network issues e. g. temp. no connection', status, statusText, detail)
          return

        # show error message
        if status is 403 || statusText is 'Not authorized'
          @taskHead      = '» ' + App.i18n.translateInline('Not authorized') + ' «'
          @taskIconClass = 'diagonal-cross'
          @renderScreenUnauthorized(objectName: 'Ticket')
        else if status is 404 || statusText is 'Not Found'
          @taskHead      = '» ' + App.i18n.translateInline('Not Found') + ' «'
          @taskIconClass = 'diagonal-cross'
          @renderScreenNotFound(objectName: 'Ticket')
        else
          @taskHead      = '» ' + App.i18n.translateInline('Error') + ' «'
          @taskIconClass = 'diagonal-cross'

          if !detail
            detail = 'General communication error, maybe internet is not available!'
          @renderScreenError(
            status:     status
            detail:     detail
            objectName: 'Ticket'
          )
    )

  moveTicketToTop: (ticketIdWithNewArticles) ->
    $(".contacts .jspContainer ul.nv-items").prepend($("li[data-ticket-id=#{ticketIdWithNewArticles}]"))

  renderView: (ticketData) ->
    localEl = $( App.view('messages')(
      head:    'Messages'
      isAdmin: @permissionCheck('admin')
      tickets: ticketData
      me:      App.Session.get('id')
    ) )

  renderAvatar: (element, objectId, size=40) ->
    new App.WidgetAvatar(
      el:        @$(element)
      object_id: objectId
      size:      size
    )

  getChannelBadge: (channelId) ->
    style = ""
    if channelId == 1     # email
      style = "fas fa-envelope"
    if channelId == 2     # sms
      style = "fas fa-sms"
    if channelId == 3     # chat
      style = "fas fa-comment-dots"
    if channelId == 4     # fax
      style = "fas fa-fax"
    if channelId == 5     # phone
      style = "fas fa-phone"
    if channelId == 6     # twitter status
      style = "fab fa-twitter"
    if channelId == 7     # twitter direct-message
      style = "fab fa-twitter-square"
    if channelId == 8     # facebook feed post
      style = "fab fa-facebook"
    if channelId == 9     # facebook feed comment
      style = "fab fa-facebook-f"
    if channelId == 10    # note
      style = "fas fa-sticky-note"
    if channelId == 11    # web
      style = "fas fa-pen"
    if channelId == 12    # telegram personal-message
      style = "fab fa-telegram-plane"
    if channelId == 13    # whatsapp personal-message
      style = "fab fa-whatsapp"

    return style

  getChannelBadgeTitle: (channelId) ->
    title = ""
    if channelId == 1     # email
      title = "Email"
    if channelId == 2     # sms
      title = "SMS"
    if channelId == 3     # chat
      title = "Chat"
    if channelId == 4     # fax
      title = "Fax"
    if channelId == 5     # phone
      title = "Phone"
    if channelId == 6     # twitter status
      title = "Twitter Status"
    if channelId == 7     # twitter direct-message
      title = "Twitter Direct Mesage"
    if channelId == 8     # facebook feed post
      title = "Facebook Feed Post"
    if channelId == 9     # facebook feed comment
      title = "Facebook Feed Comment"
    if channelId == 10    # note
      title = "Note"
    if channelId == 11    # web
      title = "Web"
    if channelId == 12    # telegram personal-message
      title = "Telegram"
    if channelId == 13    # whatsapp personal-message
      title = "WhatsApp"

    return title

  renderBadge: (element, ticket) ->
    style = @getChannelBadge(ticket.create_article_type_id)

    $(element).children().remove()
    $(element).append(
      """
        <i class="badge-icon #{style}"></i>
      """
    )

  renderArticle: (article, isNewMsg=false) ->
    inboundClass = if article.sender_id == 2 then "inbound" else "outbound"

    mimeType = ""
    if article.attachments? and article.attachments.length > 0
      msgType = article.attachments[0]['preferences']['Mime-Type']
      attachmentId = article.attachments[0]['id']

      if typeof msgType == "undefined"
        msgType = article.attachments[0]['preferences']['Content-Type']

    mimeHTML = ""
    if msgType? and msgType == "application/pdf"
      mimeHTML = """
        <a href="#{App.Config.get('api_path')}/ticket_attachment/#{article.ticket_id}/#{article.id}/#{attachmentId}?view=preview" target="_blank"><i class="fas fa-file-pdf" style='color: #d61313;'></i></a>
      """

    if msgType? and msgType.startsWith("audio")
      mimeHTML = """
        <audio src="#{App.Config.get('api_path')}/ticket_attachment/#{article.ticket_id}/#{article.id}/#{attachmentId}?view=preview" controls style="width: 250px;"></audio>
      """

    if msgType? and msgType.startsWith("video")
      mimeHTML = """
        <video src="#{App.Config.get('api_path')}/ticket_attachment/#{article.ticket_id}/#{article.id}/#{attachmentId}?view=preview" controls style="width: 250px;"></video>
      """

    if msgType? and msgType.startsWith("image")
      mimeHTML = """
        <div><img src="#{App.Config.get('api_path')}/ticket_attachment/#{article.ticket_id}/#{article.id}/#{attachmentId}?view=preview" style="width: 250px;"></img></div>
      """

    subject_html = ""
    if article.type_id == 1       # email article
      subject_html = """
        <div class="email-subject">
          #{article.subject}
        </div>
      """

    history = """
      <li class="nv-history nv-#{inboundClass}"  id="#{article.id}">
        <span class="nv-avatar avatar-#{article.created_by_id}"></span>
        <div class="nv-history-body">
          <div class="nv-message">
            <div style="display: block; margin-top: 5px; margin-left: 10px; margin-right: 10px;">
              <div>
                #{subject_html}
                #{article.body}
              </div>
              #{mimeHTML}
            </div>
          </div>
        </div>
      </li>
    """

    if isNewMsg
      $('.nv-histories').append(history)
      @moveToBottom()
    else
      $('.nv-histories').prepend(history)

  renderHistory: (ticket) ->
    currentTicketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
    boldStyle = ""

    if currentTicketId == ticket.id
      boldStyle = "font-weight: 600;"

    history = """
      <li class="nv-history"  id="#{ticket.id}">
        <div class="nv-history-body">
          <div class="nv-message" style='width: 100%'>
            <div style="display: block; width: 100%;">
              <span style="display: block; float: left; width: 100%; #{boldStyle}">
                <a href="/#ticket/zoom/#{ticket.id}" target="_blank" style='width: 100%;'>
                  <span class="history-badge" id="history-badge-#{ticket.id}"></span>
                  #{'[' + ticket.number + ']&nbsp;&nbsp;&nbsp;' + ticket.title}
                  <span style="font-size: 10px; color: grey; float: right; padding-top: 4px;">
                    #{@formattedDateTime(ticket.created_at)}
                  </span>
                </a>
              </span>
            </div>
          </div>
        </div>
      </li>
    """

    $('.nv-all-histories ul').append(history)

  ticketClickHandler: ->
    @$('.nv-items li').unbind('click')
    @$('.nv-items li').bind(
      'click'
      (e) =>
        $(".nv-histories").unbind("scroll")

        @$('.contacts').removeClass('active-window')
        @$('.contacts').addClass('deactive-window')

        @$('.message_board').removeClass('deactive-window')
        @$('.message_board').addClass('active-window')

        @$('.customer_detail').removeClass('active-window')
        @$('.customer_detail').addClass('deactive-window')

        @$('.nv-items li').removeClass('nv-item-active')
        @$(e.currentTarget).addClass('nv-item-active')

        try
          App.Messages.emojioneArea.setText("")
        catch e
          console.log(e)

        ticketId = parseInt($(e.currentTarget).attr('data-ticket-id'))
        articleTypeId = parseInt($(e.currentTarget).attr('data-article-type-id'))

        App.Messages.pageIndex = 0
        @displayHistory(ticketId, articleTypeId)
    )

  historyClickHandler: ->
    @$('div.message_board').unbind('click')
    @$('div.message_board').bind(
      'click'
      (e) =>
        @$("li.nv-item-active span.nv-contact-name i").remove()
    )

  customerDetailTabHandler: ->
    $(".nv-tab-detail").unbind("click")
    $(".nv-tab-detail").bind(
      "click",
      (e) =>
        $(".nv-tab-detail").addClass("nv-tab-active")
        $(".nv-tab-channel").removeClass("nv-tab-active")
        $(".nv-tab-history").removeClass("nv-tab-active")
        $(".nv-customer-info").css("display", "block")
        $(".nv-customer-channel-info").css("display", "none")
        $(".nv-all-histories").css("display", "none")
    )

    $(".nv-tab-channel").unbind("click")
    $(".nv-tab-channel").bind(
      "click",
      (e) =>
        $(".nv-tab-channel").addClass("nv-tab-active")
        $(".nv-tab-detail").removeClass("nv-tab-active")
        $(".nv-tab-history").removeClass("nv-tab-active")
        $(".nv-customer-channel-info").css("display", "block")
        $(".nv-customer-info").css("display", "none")
        $(".nv-all-histories").css("display", "none")
    )

    $(".nv-tab-history").unbind("click")
    $(".nv-tab-history").bind(
      "click",
      (e) =>
        $(".nv-tab-history").addClass("nv-tab-active")
        $(".nv-tab-detail").removeClass("nv-tab-active")
        $(".nv-tab-channel").removeClass("nv-tab-active")
        $(".nv-customer-channel-info").css("display", "none")
        $(".nv-customer-info").css("display", "none")
        $(".nv-all-histories").css("display", "block")
    )

  renderCustomerDetail: (ticket) ->
    App.Messages.channelType = ticket.create_article_type_id
    customer = App.Messages.users[ticket.customer_id]
    if customer == null || typeof customer == "undefined"
      customer = App.User.find(ticket.customer_id)

    ticket_number = ticket.number
    firstname = customer.firstname
    lastname = customer.lastname
    email = customer.email
    phone = customer.mobile
    wa_phone = customer.whatsapp_mobile
    street = customer.street
    city = customer.city
    country = customer.country

    $("#ticket_number").val(ticket_number)
    $("#phone").val(phone)
    $("#wa_phone").val(wa_phone)
    $("#email").val(email)
    $("#street").val(street)
    $("#city").val(city)
    $("#country").val(country)
    $(".nv-customer-name").text("#{firstname} #{lastname}")

    channelName = @getChannelBadgeTitle(App.Messages.channelType)

    $(".nv-customer-channel-info").text(channelName)
    $(".customer_detail").css("display", "block")

    $.ajax(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets_by_customer/#{ticket.customer_id}"
      processData: true,
      success: (data) =>
        for ticket in data.histories
          @renderHistory(ticket)
          @renderBadge("#history-badge-#{ticket.id}", ticket)
      error: =>
        console.log("Failed to initialize")
    )

    @renderAvatar('.nv-customer-avatar', ticket.customer_id)
    @renderBadge(".nv-customer-channel", ticket)
    @customerDetailTabHandler()

  render: ->
    $.ajax(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/users?expand=true"
      processData: true,
      success: (users) =>
        for user in users
          App.Messages.users[user.id] = user

        $.ajax(
          type: 'GET'
          url:  "#{App.Config.get('api_path')}/tickets?expand=true"
          processData: true,
          success: (data) =>
            App.Messages.tickets = {}
            tickets = []
            firstTicket = undefined
            id = 1

            for ticket in data
              customer = App.Messages.users[ticket.customer_id]
              ticket_state_type_id = App.TicketState.findNative(ticket.state_id).state_type_id
              ticket_state_name = App.TicketStateType.findNative(ticket_state_type_id).name

              if customer
                if id == 1 && ticket_state_name != "closed"
                  firstTicket = ticket
                  id++

                ticket.customer = customer
                ticket.badge = @getChannelBadge(ticket.create_article_type_id)
                if ticket.last_article
                  ticket.last_article.body = @getShortMsg(ticket.last_article)
                  ticket.last_article.formattedTime = @formattedDateTime(ticket.last_article.updated_at)
                App.Messages.tickets[ticket.id] = ticket
                tickets.push(ticket)

                App.Messages.ticketIds.push(ticket.id)
                App.Messages.ticketArticleIds[ticket.id] = ticket.article_ids

            localEl = @renderView(tickets)
            @html localEl

            for ticket in data
              @renderAvatar("span#avatar-#{ticket.id}", ticket.customer_id)

            if firstTicket
              @displayHistory(firstTicket.id, firstTicket.create_article_type_id)

            @ticketClickHandler()
            @historyClickHandler()
            @responsiveHandler()
            @audioRecordHandler()

            if @permissionCheck('admin') || @permissionCheck('agent')
              @tabClickHandler()
              @renderAgentSelectionView()
              @closeConvHandler()

            @$('.contacts').removeClass('deactive-window')
            @$('.contacts').addClass('active-window')

            @$('.message_board').removeClass('active-window')
            @$('.message_board').addClass('deactive-window')

            @$('.customer_detail').removeClass('active-window')
            @$('.customer_detail').addClass('deactive-window')

            setTimeout(
              () =>
                if typeof App.Messages.emojioneArea == "undefined"
                  App.Messages.emojioneArea = $("#emoji-area").emojioneArea({
                    pickerPosition: "top",
                    filtersPosition: "top",
                    tones: false,
                    autocomplete: false,
                    inline: true,
                    hidePickerOnBlur: false,
                    recentEmojis: false,
                    events: {
                      keyup: (editor, event) =>
#                        App.Messages.sendMsgByKey(editor, event)
                    }
                  })[0].emojioneArea
              , 1500
            )
          error: =>
            console.log("Failed to initialize")
        )
      error: =>
        console.log("Failed to fetch users")
    )

  responsiveHandler: ->
    $('.nv-back-contacts').on(
      'click'
      (e) =>
        $('.message_board').removeClass('active-window')
        $('.message_board').addClass('deactive-window')
        $('.contacts').removeClass('deactive-window')
        $('.contacts').addClass('active-window')
        $('.customer_detail').removeClass('active-window')
        $('.customer_detail').addClass('deactive-window')
    )

    $('.nv-back-messages').on(
      'click'
      (e) =>
        $('.customer_detail').removeClass('active-window')
        $('.customer_detail').addClass('deactive-window')
        $('.contacts').removeClass('active-window')
        $('.contacts').addClass('deactive-window')
        $('.message_board').removeClass('deactive-window')
        $('.message_board').addClass('active-window')
    )

    $('.nv-go-detail').on(
      'click'
      (e) =>
        $('.contacts').removeClass('active-window')
        $('.contacts').addClass('deactive-window')
        $('.message_board').removeClass('active-window')
        $('.message_board').addClass('deactive-window')
        $('.customer_detail').removeClass('deactive-window')
        $('.customer_detail').addClass('active-window')
    )

  tabClickHandler: ->
    $('div.contacts div.nv-tab, div.contacts div.nv-tab span').on(
      'click'
      (e) =>
        e.stopPropagation()

        if e.target.localName != "div"
          return

        tabType = e.target.dataset.tabType
        $('div.contacts div.nv-tab').removeClass("nv-tab-active")
        $(e.target).addClass("nv-tab-active")

        if tabType == "closed"
          $('div.contacts li.nv-item').map( (idx, ele) =>
            if $(ele).attr('data-ticket-status') == 'closed'
              $(ele).css('display', 'block')
            else
              $(ele).css('display', 'none')
          )
        else if tabType == "open"
          $('div.contacts li.nv-item').map( (idx, ele) =>
            if $(ele).attr('data-ticket-status') == 'closed'
              $(ele).css('display', 'none')
            else
              $(ele).css('display', 'block')
          )
        else if tabType == "mine"
          $('div.contacts li.nv-item').map( (idx, ele) =>
            if $(ele).attr('data-mine') == 'mine'
              $(ele).css('display', 'block')
            else
              $(ele).css('display', 'none')
          )
    )

  closeConvHandler: ->
    @$('.btn-close-conv').on(
      'click'
      (e) =>
        if @$('.btn-close-conv').hasClass('disabled')
          return

        ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
        ticket = App.Messages.tickets[ticketId]

        reqBody = {
          'customer_id': ticket.customer_id,
          'group_id': ticket.group_id,
          'id': ticketId,
          'number': ticket.number,
          'owner_id': ticket.owner_id,
          'pending_time': null,
          'preferences': {
            'channel_id': if ticket.preferences then ticket.preferences.channel_id else '',
            'customer_phone_number': if ticket.preferences then ticket.preferences.customer_phone_number else ''
          },
          'priority_id': ticket.priority_id,
          'state_id': "4",              # closed
          'title': ticket.title,
          'updated_at': Date.now()
        }

        $.ajax(
          type: 'PUT'
          url:  "#{App.Config.get('api_path')}/tickets/#{ticketId}?all=true"
          processData: true,
          headers: {'X-CSRF-Token': App.Ajax.token()},
          data: reqBody,
          success: (users) =>
            ticket.state_id = 4       # update a set of ticket with closed ticket
            App.Messages.tickets[ticketId] = ticket
            @$('.btn-close-conv').addClass('disabled')

            alert('Closed')
          error: =>
            alert('Failed')
        )
    )

  renderAgentSelectionView: ->
    $.ajax(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/users?expand=true"
      processData: true,
      success: (users) =>
        ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
        if isNaN(ticketId)
          return

        customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
        ticket = App.Messages.tickets[ticketId]
        html = ""

        for user in users
          if user.id == ticket.owner_id
            currentAgent = user

          if user.roles && (user.roles.includes('Agent') || user.roles.includes('Admin'))
            html += """
              <label for="agent-#{user.id}">#{user.firstname} #{user.lastname}
                <input type="radio" id="agent-#{user.id}" name="agent" value="#{user.id}"/>
              </label>
            """

        $(".dropp-body").append(html)

        if currentAgent
          $('.js-value').attr("data-agent-id", ticket.owner_id)
          if ticket.owner_id == 1
            $('.js-value').text(@T("Choose an agent"))
          else
            $('.js-value').text("#{currentAgent.firstname} #{currentAgent.lastname}")

        # Default dropdown action to show/hide dropdown content
        $('.js-dropp-action').click( (e, ele) =>
          e.preventDefault()
          $('.js-dropp-action').toggleClass('js-open')
          $('.js-dropp-action').parent().next('.dropp-body').toggleClass('js-open')
        )

        # Using as fake input select dropdown
        $('.dropp-body label').click( () =>
          $(this).addClass('js-open').siblings().removeClass('js-open')
          $('.dropp-body,.js-dropp-action').removeClass('js-open')
        )

        # get the value of checked input radio and display as dropp title
        $('input[name="agent"]').change( () =>
          if $('.dropp').hasClass('disabled')
            alert(@T('This ticket was closed.'))
            return

          ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
          customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
          ticket = App.Messages.tickets[ticketId]

          agent_name = $("input[name='agent']:checked").parent().text()
          agent_id = $("input[name='agent']:checked").val()
          $('.js-value').attr("data-agent-id", agent_id)
          $('.js-value').text(agent_name)

          reqBody = {
            'customer_id': customerId,
            'group_id': ticket.group_id,
            'id': ticketId,
            'number': ticket.number,
            'owner_id': agent_id,
            'pending_time': null,
            'preferences': {
              'channel_id': if ticket.preferences then ticket.preferences.channel_id else '',
              'customer_phone_number': if ticket.preferences then ticket.preferences.customer_phone_number else ''
            },
            'priority_id': ticket.priority_id,
            'state_id': ticket.state_id,
            'title': ticket.title,
            'updated_at': Date.now()
          }

          $.ajax(
            type: 'PUT'
            url:  "#{App.Config.get('api_path')}/tickets/#{ticketId}?all=true"
            processData: true,
            headers: {'X-CSRF-Token': App.Ajax.token()},
            data: reqBody,
            success: (users) =>
              ticket.owner_id = agent_id
              App.Messages.tickets[ticketId] = ticket
              currentUserId = App.Session.get('id')

              if parseInt(agent_id) == currentUserId
                $("li.nv-item-active[data-ticket-id='#{ticketId}']").attr("data-mine", "mine")
              else
                $("li.nv-item-active[data-ticket-id='#{ticketId}']").attr("data-mine", "")
                currentTab = $("div.contacts div.nv-tab-active span").text()
                if currentTab = 'Mine'
                  $("li.nv-item-active[data-ticket-id='#{ticketId}']").css('display', 'none')

              alert('Changed')
            error: =>
              alert('Failed')
          )
        )
      error: =>
        console.log("Failed to render agent selection view")
    )

  @convertTextToHtml: (msg) ->
    exp = /(\b(https?|ftp|file):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig
    msg = msg.replace(/\n/g, "<br>")
    msg = msg.replace(exp, "<a href='$1' target='_blank'>$1</a>")

    return msg

  @sendMsgByKey: (editor, event) ->
    if event.keyCode == 13
      ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
      customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
      articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))

      msg = ""
      if articleTypeId == 1
        msg = $("#email-body").val()
        msg = App.Messages.convertTextToHtml(msg)
      else
        try
          msg = App.Messages.emojioneArea.getText()
        catch e
          console.log(e)

        if msg == ''
          msg = $("#emoji-area").val()

      files = []
      if articleTypeId == 13
        files = App.Messages.dropzone.getQueuedFiles()

      for file in files
        App.Messages.dropzone.processFile(file)

      if files.length == 0 and msg != ""
        form_id = App.ControllerForm.formId()
        App.Messages.createArticle(msg, form_id)

  sendMsg: () ->
    @$('.send-msg').unbind('click')
    @$('.send-msg').bind(
      'click'
      (e) =>
        ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
        customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
        articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))

        msg = ''
        if articleTypeId == 1
          msg = $("#email-body").val()
          msg = App.Messages.convertTextToHtml(msg)
        else
          try
            msg = App.Messages.emojioneArea.getText()
          catch e
            console.log(e)

          if msg == ''
            msg = $("#emoji-area").val()

        alert(msg)
        files = []
        if articleTypeId == 13
          files = App.Messages.dropzone.getQueuedFiles()

        for file in files
          App.Messages.dropzone.processFile(file)

        if files.length == 0 and msg != ""
          form_id = App.ControllerForm.formId()
          App.Messages.createArticle(msg, form_id)
    )

  sendEmailMsg: () ->
    @$('.send-email').on(
      'click'
      (e) =>
        ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
        customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
        articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))

        msg = ''
        if articleTypeId == 1
          msg = $("#email-body").val()
          msg = App.Messages.convertTextToHtml(msg)
        else
          try
            msg = App.Messages.emojioneArea.getText()
          catch e
            console.log(e)

          if msg == ''
            msg = $("#emoji-area").val()

        files = []
        if articleTypeId == 13
          files = App.Messages.dropzone.getQueuedFiles()

        for file in files
          App.Messages.dropzone.processFile(file)

        if files.length == 0 and msg != ""
          form_id = App.ControllerForm.formId()
          App.Messages.createArticle(msg, form_id)
    )

  initFileTransfer: ->
    Dropzone.autoDiscover = false
    if typeof App.Messages.dropzone == "undefined"
      App.Messages.dropzone = new Dropzone(
        ".dropzone",
        {
          url: "#{App.Config.get('api_path')}/upload_caches/#{App.ControllerForm.formId()}",
          thumbnailMethod: 'crop',
          maxFilesize: 16,
          parallelUploads: 2,
          clickable: false,
          addRemoveLinks: true,
          autoProcessQueue: false,
          paramName: "File",
          headers: {'X-CSRF-Token': App.Ajax.token()}
          success: (file, response) ->
            if response.success
              this.removeFile(file)

              msg = ""
              articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))
              if articleTypeId == 1
                msg = $("#email-body").val()
                msg = App.Messages.convertTextToHtml(msg)
              else
                try
                  msg = App.Messages.emojioneArea.getText()
                catch e
                  console.log(e)

                if msg == ''
                  msg = $("#emoji-area").val()

              App.Messages.createArticle(msg, response.data.form_id)
            else
              console.log("Failed to send image")
          accept: (file, done) ->
            if file.type in ['audio/aac', 'audio/mp4', 'audio/amr', 'audio/mpeg', 'audio/ogg', 'image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/3gpp', 'application/pdf']
              done()
            else
              done("Error! Files of this type are not accepted");
        }
      );

  audioRecordHandler: ->
    audioIN = {
      audio: true,
      video: false
    }
    start = document.getElementById('start_record')
    stop = document.getElementById('stop_record')

    navigator.mediaDevices.getUserMedia(audioIN)
    .then( (mediaStreamObj) =>
      dataArray = []
      mediaRecorder = new MediaRecorder(mediaStreamObj)

      start.addEventListener('click', (ev) =>
        mediaRecorder.start()
        $('#start_record').css("display", "none")
        $('#stop_record').css("display", "block")
      )

      stop.addEventListener('click', (ev) =>
        mediaRecorder.stop()
        $('#start_record').css("display", "block")
        $('#stop_record').css("display", "none")
      )

      mediaRecorder.ondataavailable = (ev) =>
        dataArray.push(ev.data)

      mediaRecorder.onstop = (ev) =>
        audioData = new Blob(
          dataArray,
          { 'type': 'audio/mpeg' }
        )
        dataArray = []
        formData = new window.FormData()
        formData.append('File', audioData, "record_file.mp3")

        $.ajax(
          url: "#{App.Config.get('api_path')}/upload_caches/#{App.ControllerForm.formId()}",
          type: 'POST',
          data: formData,
          processData: false,
          contentType: false,
#              maxFilesize: 16,
          headers: {'X-CSRF-Token': App.Ajax.token()}
          success: (response) ->
            if response.success
              msg = ""
              articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))
              if articleTypeId == 1
                msg = $("#email-body").val()
                msg = App.Messages.convertTextToHtml(msg)
              else
                try
                  msg = App.Messages.emojioneArea.getText()
                catch e
                  console.log(e)

                if msg == ''
                  msg = $("#emoji-area").val()

              App.Messages.createArticle(msg, response.data.form_id)
            else
              alert("Failed to send record file")
        )
    )
    .catch( (err) =>
      console.log(err.name, err.message)
    )

  @createArticle: (msg, form_id) ->
    ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
    customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
    articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))

    ticket = App.Messages.tickets[ticketId]
    owner = App.Messages.users[ticket.owner_id]
    if owner == null || typeof owner == "undefined"
      owner = App.User.find(ticket.owner_id)
    customer = App.Messages.users[ticket.customer_id]
    if customer == null || typeof customer == "undefined"
      customer = App.User.find(ticket.customer_id)
    currentUser = App.Session.get();

    if articleTypeId == 1
      article = {
        'body': msg,
        'cc': '',
        'content_type': 'text/plain',
        'form_id': form_id,
        'from': "#{currentUser.firstname} #{currentUser.lastname}",
        'in_reply_to': '',
        'internal': false,
        'sender_id': 1,
        'subject': '',
        'subtype': '',
        'ticket_id': ticketId,
        'to': customer.email,
        'type_id': App.Messages.channelType,
      }
    else if articleTypeId == 2
      article = {
        'body': msg,
        'cc': '',
        'content_type': 'text/plain',
        'form_id': form_id,
        'from': "#{currentUser.firstname} #{currentUser.lastname}",
        'in_reply_to': '',
        'internal': false,
        'sender_id': 1,
        'subject': '',
        'subtype': '',
        'ticket_id': ticketId,
        'to': customer.mobile,
        'type_id': App.Messages.channelType,
      }
    else
      article = {
        'body': msg,
        'cc': '',
        'content_type': 'text/plain',
        'form_id': form_id,
        'from': "#{currentUser.firstname} #{currentUser.lastname}",
        'in_reply_to': '',
        'internal': false,
        'sender_id': 1,
        'subject': '',
        'subtype': '',
        'ticket_id': ticketId,
        'to': '',
        'type_id': App.Messages.channelType,
      }

    reqBody = {
      'article': article,
      'customer_id': customerId,
      'group_id': ticket.group_id,
      'id': ticketId,
      'number': ticket.number,
      'owner_id': ticket.owner_id,
      'pending_time': null,
      'preferences': {
        'channel_id': if ticket.preferences then ticket.preferences.channel_id else '',
        'customer_phone_number': if ticket.preferences then ticket.preferences.customer_phone_number else ''
      },
      'priority_id': ticket.priority_id,
      'state_id': ticket.state_id,
      'title': ticket.title,
      'updated_at': Date.now()
    }

    $.ajax(
      type: 'PUT'
      url:  "#{App.Config.get('api_path')}/tickets/#{ticketId}?all=true"
      processData: true,
      headers: {'X-CSRF-Token': App.Ajax.token()},
      data: reqBody,
      before: =>
        $("li[data-ticket-id=#{ticketId}] span.nv-contact-name i").remove()
      success: (data) =>
        new_state_id = data['assets']['Ticket'][data.ticket_id]['state_id']
        App.Messages.tickets[ticketId].state_id = new_state_id

        try
          App.Messages.emojioneArea.setText("")
        catch e
          console.log(e)

        $("#email-body").val("")
        $("#emoji-area").val("")
      error: =>
        console.log("error")
    )

  displayHistory: (ticketId, articleTypeId, pageIndex=App.Messages.pageIndex, perPage=App.Messages.perPage, moveToBottom=true) ->
    ticket = App.Messages.tickets[ticketId]
    currentAgent = App.Messages.users[ticket.owner_id]
    if currentAgent == null || typeof currentAgent == "undefined"
      currentAgent = App.User.find(ticket.owner_id)

    # assign bar
    $('.js-value').attr("data-agent-id", ticket.owner_id)
    if ticket.owner_id == 1
      $('.js-value').text(@T("Choose an agent"))
    else
      $('.js-value').text("#{currentAgent.firstname} #{currentAgent.lastname}")

    # close conversation
    ticket_state_type_id = App.TicketState.findNative(ticket.state_id).state_type_id
    ticket_state_name = App.TicketStateType.findNative(ticket_state_type_id).name
    if ticket_state_name == "closed"
      @$('.btn-close-conv').addClass('disabled')
      @$('.dropp').addClass('disabled')
      @$('.btn-close-conv').text(@T('Closed'))
    else
      @$('.btn-close-conv').removeClass('disabled')
      @$('.dropp').removeClass('disabled')
      @$('.btn-close-conv').text(@T('Close'))

    # Remove new flag from ticket bar
    $("li[data-ticket-id=#{ticketId}] span.nv-contact-name i").remove()

    if pageIndex == 0
      $('.nv-histories').children().remove()
      $('.nv-all-histories ul').children().remove()

    if articleTypeId == 1
      $("#nv-chat").css("display", "none")
      $("#nv-chat-email").css("display", "flex")
      $('.dropzone').css('height', 'calc(100% - 64px - 134px)')
      @sendEmailMsg()
    else
      $("#nv-chat").css("display", "flex")
      $("#nv-chat-email").css("display", "none")
      $('.dropzone').css('height', 'calc(100% - 64px - 66px)')
      @sendMsg()

    $(".message_board").css("display", "block")

    $.ajax(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets_articles/#{ticketId}?page=#{pageIndex}&per_page=#{perPage}"
      processData: true,
      beforeSend: () =>
        $("#ajax_loader").removeClass("hide")
      ,
      success: (data) =>
        if typeof data.assets.Ticket == "undefined"
          $("#ajax_loader").addClass("hide")
          return

        ticket = data.assets.Ticket[ticketId]

        articleIds = data.ticket_article_ids
        for articleId in articleIds
          article = data.assets.TicketArticle[articleId]

          @renderArticle(article)
          @renderAvatar(".avatar-#{article.created_by_id}", article.created_by_id)
          @renderBadge(".avatar-#{article.created_by_id} > span", ticket)

        $(".nv-message-board-footer").css("display", "block")

        @renderCustomerDetail(ticket)
        if @getChannelBadgeTitle(ticket.create_article_type_id) == "WhatsApp"
          @initFileTransfer()
          @showAudioRecord()
        else
          if typeof App.Messages.dropzone != "undefined"
            App.Messages.dropzone.destroy()
            App.Messages.dropzone = undefined
          @hideAudioRecord()

        if moveToBottom
          @moveToBottom()
        @displayMoreHistories(ticketId, articleTypeId)

        $("#ajax_loader").addClass("hide")
      error: =>
        console.log("error")
    )

  moveToBottom: () ->
    history_view = $(".nv-histories");
    last_history = $(".nv-histories li:last");

    # 40 is padding top & bottom of history_view
    if (history_view[0].scrollHeight - 40) > history_view.height()
      last_history[0].scrollIntoView()

  displayMoreHistories: (ticketId, articleTypeId) ->
    thisObj = this
    $(".nv-histories").unbind("scroll")
    $(".nv-histories").bind(
      "scroll",
      () ->
        if $(this).scrollTop() == 0
          App.Messages.pageIndex += 1
          thisObj.displayHistory(ticketId, articleTypeId, App.Messages.pageIndex, App.Messages.perPage, false)
    )

  showAudioRecord: =>
    $("#start_record").css("display", "block")
    $("#stop_record").css("display", "none")

  hideAudioRecord: =>
    $("#start_record").css("display", "none")
    $("#stop_record").css("display", "none")

  url: ->
    '#messages'

  show: (params) =>
    # incase of being only admin, redirect to admin interface (show no empty white content page)
    if !@permissionCheck('ticket.customer') && !@permissionCheck('ticket.agent') && @permissionCheck('admin')
      @navigate '#manage', { hideCurrentLocationFromHistory: true }
      return

    # set title
    @title 'Messages'

    # highlight navbar
    @navupdate '#messages'

  formattedDateTime: (datetime) =>
    old_time = new Date(datetime)
    now = new Date()

    difference = Math.abs(now - old_time)
    diffDays = Math.floor(difference / (24 * 60 * 60 * 1000))
    diffHours = Math.floor(difference / (60 * 60 * 1000))

    if diffDays != 0
      month = '' + (old_time.getMonth() + 1)
      day = '' + (old_time.getDate())
      year = old_time.getFullYear()

      if (month.length < 2)
        month = '0' + month;
      if (day.length < 2)
        day = '0' + day;

      return [year, month, day].join('.')
    if diffHours != 0
      diffMinutes = Math.floor((difference - diffHours * 60 * 60 * 1000) / (60 * 1000))
      return diffHours + "h " + diffMinutes + "m"
    if diffMinutes != 0
      diffMinutes = Math.floor(difference / (60 * 1000))
      return diffMinutes + "m"

    return "1m"

class MessagesRouter extends App.ControllerPermanent
  requiredPermission: ['*']

  constructor: (params) ->
    super

    # check authentication
    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key:        'Messages'
      controller: 'Messages'
      params:     {}
      show:       true
      persistent: true
    )

App.Config.set('messages', MessagesRouter, 'Routes')
App.Config.set('Messages', { controller: 'Messages', permission: ['*'] }, 'permanentTask')
App.Config.set('Messages', { prio: 99, parent: '', name: 'Messages', target: '#messages', key: 'Messages', permission: ['ticket.agent', 'ticket.customer'], class: 'chat', icon: 'comment-alt' }, 'NavBar')
