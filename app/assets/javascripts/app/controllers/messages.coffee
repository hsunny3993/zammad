class App.Messages extends App.Controller
  clueAccess: false

  constructor: ->
    super
    @tickets = {}
    @users = {}
    @ticketArticleIds = {}
    @ticketIds = []
    @dropzone = undefined
    @channelType = undefined
    @ticketUpdatedAtLastCall = undefined

    # fetch new data if triggered
    @controllerBind('Ticket:update', (data) =>
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
    if @tickets[data.id]
      ticketUpdatedAtLastCall = @tickets[data.id].updated_at
      if ticketUpdatedAtLastCall
        if new Date(data.updated_at).getTime() is new Date(ticketUpdatedAtLastCall).getTime()
          return
        if new Date(data.updated_at).getTime() < new Date(ticketUpdatedAtLastCall).getTime()
          return

      @tickets[data.id].updated_at = data.updated_at

    ticketIdWithNewArticles = data.id
    me = App.Session.get('id')

    $.ajax(
      type:  'GET'
      url:   "#{App.Config.get('api_path')}/tickets/#{ticketIdWithNewArticles}?all=true"
      processData: true
      success: (data, status, xhr) =>
        ticket = data.assets.Ticket[ticketIdWithNewArticles]
        @users = data.assets.User
        ticket.customer = data.assets.User[ticket.customer_id]
        ticket.owner = data.assets.User[ticket.owner_id]
        curActiveTicketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))

        if @tickets[ticketIdWithNewArticles] == null || typeof @tickets[ticketIdWithNewArticles] == "undefined"
          @tickets[ticketIdWithNewArticles] = ticket

        oldNum = parseInt($("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name i").text())
        oldNum = if isNaN(oldNum) then 0 else oldNum

        # Checks if the ticket is currently displayed as active
        if ticketIdWithNewArticles == curActiveTicketId
          newArticleNums = 0
          for articleId in data.ticket_article_ids
            if articleId not in @ticketArticleIds[ticketIdWithNewArticles]
              article = data.assets.TicketArticle[articleId]

              @renderArticle(article)
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
            @tickets[ticketIdWithNewArticles]['last_article'] = article
            @ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
            $("li[data-ticket-id=#{ticketIdWithNewArticles}] div.nv-recent-message span.nv-recent-msg").text(content)

        else # If the ticket is currently not displayed as active
          # Checks if the ticket is new
          if ticketIdWithNewArticles not in @ticketIds
            @ticketIds.push(ticketIdWithNewArticles)
            @ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
            @tickets[ticketIdWithNewArticles] = ticket

            lastArticle = data.assets.TicketArticle[Object.keys(data.assets.TicketArticle)[Object.keys(data.assets.TicketArticle).length - 1]]
            content = @getShortMsg(lastArticle)
            lastArticle.body = content
            @tickets[ticketIdWithNewArticles]['last_article'] = lastArticle

            activeClass = ""
            badgeClass = @getChannelBadge(ticket.create_article_type_id)
            if isNaN(curActiveTicketId)
              activeClass = "nv-item-active"

            is_mine = ""
            if me == ticket.owner_id
              is_mine = 'mine'

            ticketHTML = """
              <li class="nv-item #{activeClass}" data-ticket-id="#{ticketIdWithNewArticles}" data-customer-id="#{ticket.customer_id}" data-article-type-id="#{ticket.create_article_type_id}" data-mine="#{is_mine}">
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

            @ticketIds.push(ticketIdWithNewArticles)
            @ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
            if isNaN(curActiveTicketId)
              @displayHistory(ticketIdWithNewArticles, ticket.create_article_type_id)
          else
            newArticleNums = 0
            for articleId in data.ticket_article_ids
              if articleId not in @ticketArticleIds[ticketIdWithNewArticles]
                newArticleNums++
                article = data.assets.TicketArticle[articleId]

            if article
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name i").remove()
              $("li[data-ticket-id=#{ticketIdWithNewArticles}] span.nv-contact-name").append("<i class='badge-icon badge-new'>#{newArticleNums + oldNum}</i>")
              content = @getShortMsg(article)
              article.body = content
              @tickets[ticketIdWithNewArticles]['last_article'] = article
              @ticketArticleIds[ticketIdWithNewArticles] = data.ticket_article_ids
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
        if @ticketUpdatedAtLastCall && status is 0
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

  renderAvatar: (element, objectId) ->
    new App.WidgetAvatar(
      el:        @$(element)
      object_id: objectId
      size:      40
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

  renderArticle: (article) ->
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
        <i class="fas fa-file-pdf" style='color: #d61313;'></i>
      """

    if msgType? and msgType.startsWith("audio")
      mimeHTML = """
        <audio src="#{App.Config.get('api_path')}/ticket_attachment/#{article.ticket_id}/#{article.id}/#{attachmentId}?view=preview" controls></audio>
      """

    if msgType? and msgType.startsWith("video")
      mimeHTML = """
        <video src="#{App.Config.get('api_path')}/ticket_attachment/#{article.ticket_id}/#{article.id}/#{attachmentId}?view=preview" controls></video>
      """

    history = """
      <li class="nv-history nv-#{inboundClass}"  id="#{article.id}">
        <span class="nv-avatar avatar-#{article.created_by_id}"></span>
        <div class="nv-history-body">
          <div class="nv-message">
            <div style="display: block;">
              #{article.body}
              #{mimeHTML}
            </div>
          </div>
        </div>
      </li>
    """

    $('.nv-histories').append(history)

  ticketClickHandler: ->
    @$('.nv-items li').unbind('click')
    @$('.nv-items li').bind(
      'click'
      (e) =>
        @$('.contacts').removeClass('active-window')
        @$('.contacts').addClass('deactive-window')

        @$('.message_board').removeClass('deactive-window')
        @$('.message_board').addClass('active-window')

        @$('.customer_detail').removeClass('active-window')
        @$('.customer_detail').addClass('deactive-window')

        @$('.nv-items li').removeClass('nv-item-active')
        @$(e.currentTarget).addClass('nv-item-active')
        $(".emojionearea-editor").text("")

        ticketId = parseInt($(e.currentTarget).attr('data-ticket-id'))
        articleTypeId = parseInt($(e.currentTarget).attr('data-article-type-id'))

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
        $(".nv-customer-info").css("display", "block")
        $(".nv-customer-channel-info").css("display", "none")
    )

    $(".nv-tab-channel").unbind("click")
    $(".nv-tab-channel").bind(
      "click",
      (e) =>
        $(".nv-tab-detail").removeClass("nv-tab-active")
        $(".nv-tab-channel").addClass("nv-tab-active")
        $(".nv-customer-info").css("display", "none")
        $(".nv-customer-channel-info").css("display", "block")
    )

  renderCustomerDetail: (ticket) ->
    @channelType = ticket.create_article_type_id
    customer = @users[ticket.customer_id]
    if customer == null || typeof customer == "undefined"
      customer = App.User.find(ticket.customer_id)

    firstname = customer.firstname
    lastname = customer.lastname
    email = customer.email
    phone = customer.mobile
    street = customer.street
    city = customer.city
    country = customer.country

    $("#phone").val(phone)
    $("#email").val(email)
    $("#street").val(street)
    $("#city").val(city)
    $("#country").val(country)
    $(".nv-customer-name").text("#{firstname} #{lastname}")

    channelName = @getChannelBadgeTitle(@channelType)

    $(".nv-customer-channel-info").text(channelName)
    $(".customer_detail").css("display", "block")

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
          @users[user.id] = user

        $.ajax(
          type: 'GET'
          url:  "#{App.Config.get('api_path')}/tickets?expand=true"
          processData: true,
          success: (data) =>
            @tickets = {}
            tickets = []
            firstTicket = undefined
            id = 1

            for ticket in data
              customer = @users[ticket.customer_id]

              if customer
                if id == 1
                  firstTicket = ticket

                ticket.customer = customer
                ticket.badge = @getChannelBadge(ticket.create_article_type_id)
                if ticket.last_article
                  ticket.last_article.body = @getShortMsg(ticket.last_article)
                  ticket.last_article.formattedTime = @formattedDateTime(ticket.last_article.updated_at)
                @tickets[ticket.id] = ticket
                tickets.push(ticket)

                @ticketIds.push(ticket.id)
                @ticketArticleIds[ticket.id] = ticket.article_ids
                id++

            localEl = @renderView(tickets)
            @html localEl

            for ticket in data
              @renderAvatar("span#avatar-#{ticket.id}", ticket.customer_id)

            if firstTicket
              @displayHistory(firstTicket.id, firstTicket.create_article_type_id)

            @ticketClickHandler()
            @historyClickHandler()
            @sendMsgHandler()
            @responsiveHandler()

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

        if tabType == "mine"
          $('div.contacts li.nv-item').map( (idx, ele) =>
            if $(ele).attr('data-mine') == 'mine'
              $(ele).css('display', 'block')
            else
              $(ele).css('display', 'none')
          )
        else if tabType == "all"
          $('div.contacts li.nv-item').map( (idx, ele) =>
            $(ele).css('display', 'block')
          )
    )

  closeConvHandler: ->
    @$('.btn-close-conv').on(
      'click'
      (e) =>
        if @$('.btn-close-conv').hasClass('disabled')
          return

        ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
        ticket = @tickets[ticketId]

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
            @tickets[ticketId] = ticket
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
        customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
        ticket = @tickets[ticketId]
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
          ticket = @tickets[ticketId]

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
              @tickets[ticketId] = ticket

              alert('Changed')
            error: =>
              alert('Failed')
          )
        )
      error: =>
        console.log("Failed to render agent selection view")
    )

  convertTextToHtml: (msg) ->
    exp = /(\b(https?|ftp|file):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig
    msg = msg.replace(/\n/g, "<br>")
    msg = msg.replace(exp, "<a href='$1' target='_blank'>$1</a>")

    return msg

  sendMsgHandler: ->
    @$('.send-msg').on(
      'click'
      (e) =>
        ticketId = parseInt($('li.nv-item-active').attr('data-ticket-id'))
        customerId = parseInt($('li.nv-item-active').attr('data-customer-id'))
        articleTypeId = parseInt($('li.nv-item-active').attr('data-article-type-id'))

        if articleTypeId == 1
          msg = $("#email-body").val()
          msg = @convertTextToHtml(msg)
        else
          msg = $(".emojionearea-editor").text()

        files = []
        if articleTypeId == 13
          files = @dropzone.getQueuedFiles()

        for file in files
          result = @dropzone.processFile(file)

        if msg != ""
          ticket = @tickets[ticketId]

          owner = @users[ticket.owner_id]
          if owner == null || typeof owner == "undefined"
            owner = App.User.find(ticket.owner_id)

          customer = @users[ticket.customer_id]
          if customer == null || typeof customer == "undefined"
            customer = App.User.find(ticket.customer_id)

          currentUser = App.Session.get();

          if articleTypeId == 1
            article = {
              'body': msg,
              'cc': '',
              'content_type': 'text/plain',
              'form_id': '',
              'from': "#{currentUser.firstname} #{currentUser.lastname}",
              'in_reply_to': '',
              'internal': false,
              'sender_id': 1,
              'subject': '',
              'subtype': '',
              'ticket_id': ticketId,
              'to': customer.email,
              'type_id': @channelType,
            }
          else if articleTypeId == 2
            article = {
              'body': msg,
              'cc': '',
              'content_type': 'text/plain',
              'form_id': '',
              'from': "#{currentUser.firstname} #{currentUser.lastname}",
              'in_reply_to': '',
              'internal': false,
              'sender_id': 1,
              'subject': '',
              'subtype': '',
              'ticket_id': ticketId,
              'to': customer.mobile,
              'type_id': @channelType,
            }
          else
            article = {
              'body': msg,
              'cc': '',
              'content_type': 'text/plain',
              'form_id': '',
              'from': "#{currentUser.firstname} #{currentUser.lastname}",
              'in_reply_to': '',
              'internal': false,
              'sender_id': 1,
              'subject': '',
              'subtype': '',
              'ticket_id': ticketId,
              'to': '',
              'type_id': @channelType,
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
              @tickets[ticketId].state_id = new_state_id

              $(".emojionearea-editor").text("")
              $("#email-body").val("")
            error: =>
              console.log("error")
          )
    )

  initFileTransfer: ->
    Dropzone.autoDiscover = false
    if typeof @dropzone == "undefined"
      @dropzone = new Dropzone(
        ".dropzone",
        {
          url: "#{App.Config.get('api_path')}/upload_caches/1",
          thumbnailMethod: 'crop',
          maxFilesize: 5,
          parallelUploads: 2,
          clickable: false,
          addRemoveLinks: true,
          autoProcessQueue: false,
          paramName: "File",
          headers: {'X-CSRF-Token': App.Ajax.token()}
          success: (file, response) ->
            response = JSON.parse(response)
            if (response.status == "success")
              dropzone.removeFile(file)
            else
              console.log("Failed to send image")
        }
      );

  displayHistory: (ticketId, articleTypeId) ->
    ticket = @tickets[ticketId]
    currentAgent = @users[ticket.owner_id]
    if currentAgent == null || typeof currentAgent == "undefined"
      currentAgent = App.User.find(ticket.owner_id)

    # assign bar
    $('.js-value').attr("data-agent-id", ticket.owner_id)
    if ticket.owner_id == 1
      $('.js-value').text(@T("Choose an agent"))
    else
      $('.js-value').text("#{currentAgent.firstname} #{currentAgent.lastname}")

    # close conversation
    if ticket.state_id == 4
      @$('.btn-close-conv').addClass('disabled')
      @$('.dropp').addClass('disabled')
      @$('.btn-close-conv').text(@T('Closed'))
    else
      @$('.btn-close-conv').removeClass('disabled')
      @$('.dropp').removeClass('disabled')
      @$('.btn-close-conv').text(@T('Close'))

    # Remove new flag from ticket bar
    $("li[data-ticket-id=#{ticketId}] span.nv-contact-name i").remove()

    $('.nv-histories').children().remove()
    if articleTypeId == 1
      $("#nv-chat").css("display", "none")
      $("#nv-chat-email").css("display", "block")
      $('.dropzone').css('height', 'calc(100% - 64px - 134px)')
    else
      $("#nv-chat").css("display", "block")
      $("#nv-chat-email").css("display", "none")
      $('.dropzone').css('height', 'calc(100% - 64px - 66px)')

    $(".message_board").css("display", "block")

    $.ajax(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets/#{ticketId}?all=true"
      processData: true,
      success: (data) =>
        @ticketArticleIds[ticketId] = data.ticket_article_ids
        ticket = data.assets.Ticket[ticketId]

        articleIds = data.ticket_article_ids
        for articleId in articleIds
          article = data.assets.TicketArticle[articleId]

          @renderArticle(article)
          @renderAvatar(".avatar-#{article.created_by_id}", article.created_by_id)
          @renderBadge(".avatar-#{article.created_by_id} > span", ticket)

        $("#emoji-area").emojioneArea({
          pickerPosition: "top",
          filtersPosition: "bottom",
          tones: false,
          autocomplete: false,
          inline: true,
          hidePickerOnBlur: false
        });

        $(".nv-message-board-footer").css("display", "block")

        @renderCustomerDetail(ticket)
        @initFileTransfer()
      error: =>
        console.log("error")
    )

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
    diffMinutes = Math.floor(difference / (60 * 1000))

    if diffDays != 0
      return diffDays + "d"
    if diffHours != 0
      return diffHours + "h"
    if diffMinutes != 0
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
App.Config.set('Messages', { prio: 99, parent: '', name: 'Messages', target: '#messages', key: 'Messages', permission: ['ticket.agent', 'ticket.customer'], class: 'messages', iconStyle: 'comment-alt' }, 'NavBarRight')
