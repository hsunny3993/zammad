class ChannelWhatsapp extends App.ControllerSubContent
  requiredPermission: 'admin.channel_whatsapp'
  events:
    'click .js-new':     'new'
    'click .js-edit':    'edit'
    'click .js-delete':  'delete'
    'click .js-disable': 'disable'
    'click .js-enable':  'enable'

  constructor: ->
    super

    #@interval(@load, 60000)
    @load()

  load: =>
    @startLoading()
    @ajax(
      id:   'whatsapp_index'
      type: 'GET'
      url:  "#{@apiPath}/channels_whatsapp"
      processData: true
      success: (data) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        @render(data)
    )

  render: (data) =>

    channels = []
    for channel_id in data.channel_ids
      channel = App.Channel.find(channel_id)
      if channel && channel.options
        displayName = '-'
        if channel.group_id
          group = App.Group.find(channel.group_id)
          displayName = group.displayName()
        channel.options.groupName = displayName
      channels.push channel
    @html App.view('whatsapp/index')(
      channels: channels
    )

  new: (e) =>
    e.preventDefault()
    new BotAdd(
      container: @el.parents('.content')
      load: @load
    )

  edit: (e) =>
    e.preventDefault()
    id = $(e.target).closest('.action').data('id')
    channel = App.Channel.find(id)
    new BotEdit(
      channel: channel
      container: @el.parents('.content')
      load: @load
    )

  delete: (e) =>
    e.preventDefault()
    id   = $(e.target).closest('.action').data('id')
    new App.ControllerConfirm(
      message: 'Sure?'
      callback: =>
        @ajax(
          id:   'whatsapp_delete'
          type: 'DELETE'
          url:  "#{@apiPath}/channels_whatsapp"
          data: JSON.stringify(id: id)
          processData: true
          success: =>
            @load()
        )
      container: @el.closest('.content')
    )

  disable: (e) =>
    e.preventDefault()
    id   = $(e.target).closest('.action').data('id')
    @ajax(
      id:   'whatsapp_disable'
      type: 'POST'
      url:  "#{@apiPath}/channels_whatsapp_disable"
      data: JSON.stringify(id: id)
      processData: true
      success: =>
        @load()
    )

  enable: (e) =>
    e.preventDefault()
    id   = $(e.target).closest('.action').data('id')
    @ajax(
      id:   'whatsapp_enable'
      type: 'POST'
      url:  "#{@apiPath}/channels_whatsapp_enable"
      data: JSON.stringify(id: id)
      processData: true
      success: =>
        @load()
    )

class BotAdd extends App.ControllerModal
  head: 'Add Whatsapp Bot'
  shown: true
  button: 'Add'
  buttonCancel: true
  small: true

  content: ->
    content = $(App.view('whatsapp/bot_add')())
    createGroupSelection = (selected_id) ->
      return App.UiElement.select.render(
        name:       'group_id'
        multiple:   false
        limit:      100
        null:       false
        relation:   'Group'
        nulloption: true
        value:      selected_id
        class:      'form-control--small'
      )

    content.find('.js-select').on('click', (e) =>
      @selectAll(e)
    )
    content.find('.js-messagesGroup').replaceWith createGroupSelection(1)
    content

  onClosed: =>
    return if !@isChanged
    @isChanged = false
    @load()

  onSubmit: (e) =>
    @formDisable(e)
    @ajax(
      id:   'whatsapp_app_verify'
      type: 'POST'
      url:  "#{@apiPath}/channels_whatsapp"
      data: JSON.stringify(@formParams())
      processData: true
      success: =>
        @isChanged = true
        @close()
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @formEnable(e)
        error_message = App.i18n.translateContent(data.error || 'Unable to save Bot.')
        @el.find('.alert').removeClass('hidden').text(error_message)
    )

class BotEdit extends App.ControllerModal
  head: 'WhatsApp Account'
  shown: true
  buttonCancel: true

  content: ->
    content = $(App.view('whatsapp/bot_edit')(channel: @channel))

    createGroupSelection = (selected_id) ->
      return App.UiElement.select.render(
        name:       'group_id'
        multiple:   false
        limit:      100
        null:       false
        relation:   'Group'
        nulloption: true
        value:      selected_id
        class:      'form-control--small'
      )

    content.find('.js-messagesGroup').replaceWith createGroupSelection(@channel.group_id)
    content

  onClosed: =>
    return if !@isChanged
    @isChanged = false
    @load()

  onSubmit: (e) =>
    @formDisable(e)
    params = @formParams()
    @channel.options = params
    @ajax(
      id:   'channel_whatsapp_update'
      type: 'PUT'
      url:  "#{@apiPath}/channels_whatsapp/#{@channel.id}"
      data: JSON.stringify(@formParams())
      processData: true
      success: =>
        @isChanged = true
        @close()
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @formEnable(e)
        error_message = App.i18n.translateContent(data.error || 'Unable to save changes.')
        @el.find('.alert').removeClass('hidden').text(error_message)
    )

#App.Config.set('Telegram', { prio: 5100, name: 'Telegram', parent: '#channels', target: '#channels/whatsapp', controller: ChannelWhatsapp, permission: ['admin.channel_whatsapp'] }, 'NavBarAdmin')

App.Config.set('Whatsapp', { prio: 5100, name: 'Whatsapp', parent: '#channels', target: '#channels/whatsapp', controller: ChannelWhatsapp, permission: ['admin.channel_whatsapp'] }, 'NavBarAdmin')
