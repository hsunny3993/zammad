# coffeelint: disable=camel_case_classes
class App.UiElement.ticket_perform_action
  @defaults: (attribute) ->
    defaults = ['ticket.state_id']

    groups =
      ticket:
        name: 'Ticket'
        model: 'Ticket'
      article:
        name: 'Article'
        model: 'Article'

    if attribute.notification
      groups.notification =
        name: 'Notification'
        model: 'Notification'

    # merge config
    elements = {}
    for groupKey, groupMeta of groups
      if !groupMeta.model || !App[groupMeta.model]
        if groupKey is 'notification'
          elements["#{groupKey}.email"] = { name: 'email', display: 'Email' }
          elements["#{groupKey}.sms"] = { name: 'sms', display: 'SMS' }
          elements["#{groupKey}.whatsapp"] = { name: 'whatsapp', display: 'WhatsApp' }
          elements["#{groupKey}.webhook"] = { name: 'webhook', display: 'Webhook' }
        else if groupKey is 'article'
          elements["#{groupKey}.note"] = { name: 'note', display: 'Note' }
      else

        for row in App[groupMeta.model].configure_attributes

          # ignore passwords and relations
          if row.type isnt 'password' && row.name.substr(row.name.length-4,4) isnt '_ids'

            # ignore readonly attributes
            if !row.readonly
              config = _.clone(row)

              switch config.tag
                when 'datetime'
                  config.operator = ['static', 'relative']
                when 'tag'
                  config.operator = ['add', 'remove']

              elements["#{groupKey}.#{config.name}"] = config

    # add ticket deletion action
    if attribute.ticket_delete
      elements['ticket.action'] =
        name: 'action'
        display: 'Action'
        tag: 'select'
        null: false
        translate: true
        options:
          delete: 'Delete'

    [defaults, groups, elements]

  @placeholder: (elementFull, attribute, params, groups, elements) ->
    item = $( App.view('generic/ticket_perform_action/row')( attribute: attribute ) )
    selector = @buildAttributeSelector(elementFull, groups, elements)
    item.find('.js-attributeSelector').prepend(selector)
    item

  @render: (attribute, params = {}) ->

    [defaults, groups, elements] = @defaults(attribute)

    # return item
    item = $( App.view('generic/ticket_perform_action/index')( attribute: attribute ) )

    # add filter
    item.on('click', '.js-rowActions .js-add', (e) =>
      element = $(e.target).closest('.js-filterElement')
      placeholder = @placeholder(item, attribute, params, groups, elements)
      if element.get(0)
        element.after(placeholder)
      else
        item.append(placeholder)
      placeholder.find('.js-attributeSelector select').trigger('change')
      @updateAttributeSelectors(item)
    )

    # remove filter
    item.on('click', '.js-rowActions .js-remove', (e) =>
      return if $(e.currentTarget).hasClass('is-disabled')
      $(e.target).closest('.js-filterElement').remove()
      @updateAttributeSelectors(item)
    )

    # change attribute selector
    item.on('change', '.js-attributeSelector select', (e) =>
      elementRow = $(e.target).closest('.js-filterElement')
      groupAndAttribute = elementRow.find('.js-attributeSelector option:selected').attr('value')
      @rebuildAttributeSelectors(item, elementRow, groupAndAttribute, elements, {}, attribute)
      @updateAttributeSelectors(item)
    )

    # change operator selector
    item.on('change', '.js-operator select', (e) =>
      elementRow = $(e.target).closest('.js-filterElement')
      groupAndAttribute = elementRow.find('.js-attributeSelector option:selected').attr('value')
      @buildOperator(item, elementRow, groupAndAttribute, elements, {}, attribute)
    )

    # build initial params
    if _.isEmpty(params[attribute.name])

      for groupAndAttribute in defaults

        # build and append
        element = @placeholder(item, attribute, params, groups, elements)
        item.append(element)
        @rebuildAttributeSelectors(item, element, groupAndAttribute, elements, {}, attribute)

    else

      for groupAndAttribute, meta of params[attribute.name]

        # build and append
        element = @placeholder(item, attribute, params, groups, elements)
        @rebuildAttributeSelectors(item, element, groupAndAttribute, elements, meta, attribute)
        item.append(element)

    @disableRemoveForOneAttribute(item)
    item

  @buildAttributeSelector: (elementFull, groups, elements) ->

    # find first possible attribute
    selectedValue = ''
    elementFull.find('.js-attributeSelector select option').each(->
      if !selectedValue && !$(@).prop('disabled')
        selectedValue = $(@).val()
    )

    selection = $('<select class="form-control"></select>')
    for groupKey, groupMeta of groups
      displayName = App.i18n.translateInline(groupMeta.name)
      selection.closest('select').append("<optgroup label=\"#{displayName}\" class=\"js-#{groupKey}\"></optgroup>")
      optgroup = selection.find("optgroup.js-#{groupKey}")
      for elementKey, elementGroup of elements
        spacer = elementKey.split(/\./)
        if spacer[0] is groupKey
          attributeConfig = elements[elementKey]
          displayName = App.i18n.translateInline(attributeConfig.display)

          selected = ''
          if elementKey is selectedValue
            selected = 'selected="selected"'
          optgroup.append("<option value=\"#{elementKey}\" #{selected}>#{displayName}</option>")
    selection

  # disable - if we only have one attribute
  @disableRemoveForOneAttribute: (elementFull) ->
    if elementFull.find('.js-attributeSelector select').length > 1
      elementFull.find('.js-remove').removeClass('is-disabled')
    else
      elementFull.find('.js-remove').addClass('is-disabled')

  @updateAttributeSelectors: (elementFull) ->

    # enable all
    elementFull.find('.js-attributeSelector select option').removeAttr('disabled')

    # disable all used attributes
    elementFull.find('.js-attributeSelector select').each(->
      keyLocal = $(@).val()
      elementFull.find('.js-attributeSelector select option[value="' + keyLocal + '"]').attr('disabled', true)
    )

    # disable - if we only have one attribute
    @disableRemoveForOneAttribute(elementFull)

  @rebuildAttributeSelectors: (elementFull, elementRow, groupAndAttribute, elements, meta, attribute) ->

    # set attribute
    if groupAndAttribute
      elementRow.find('.js-attributeSelector select').val(groupAndAttribute)

    notificationTypeMatch = groupAndAttribute.match(/^notification.([\w]+)$/)
    articleTypeMatch = groupAndAttribute.match(/^article.([\w]+)$/)

    if _.isArray(notificationTypeMatch) && notificationType = notificationTypeMatch[1]
      elementRow.find('.js-setAttribute').html('').addClass('hide')
      elementRow.find('.js-setArticle').html('').addClass('hide')
      @buildNotificationArea(notificationType, elementFull, elementRow, groupAndAttribute, elements, meta, attribute)
    else if _.isArray(articleTypeMatch) && articleType = articleTypeMatch[1]
      elementRow.find('.js-setAttribute').html('').addClass('hide')
      elementRow.find('.js-setNotification').html('').addClass('hide')
      @buildArticleArea(articleType, elementFull, elementRow, groupAndAttribute, elements, meta, attribute)
    else
      elementRow.find('.js-setNotification').html('').addClass('hide')
      elementRow.find('.js-setArticle').html('').addClass('hide')
      if !elementRow.find('.js-setAttribute div').get(0)
        attributeSelectorElement = $( App.view('generic/ticket_perform_action/attribute_selector')(
          attribute: attribute
          name: name
          meta: meta || {}
        ))
        elementRow.find('.js-setAttribute').html(attributeSelectorElement).removeClass('hide')
      @buildOperator(elementFull, elementRow, groupAndAttribute, elements, meta, attribute)

  @buildOperator: (elementFull, elementRow, groupAndAttribute, elements, meta, attribute) ->
    currentOperator = elementRow.find('.js-operator option:selected').attr('value')

    if !meta.operator
      meta.operator = currentOperator

    name = "#{attribute.name}::#{groupAndAttribute}::operator"

    selection = $("<select class=\"form-control\" name=\"#{name}\"></select>")
    attributeConfig = elements[groupAndAttribute]
    if !attributeConfig || !attributeConfig.operator
      elementRow.find('.js-operator').parent().addClass('hide')
    else
      elementRow.find('.js-operator').parent().removeClass('hide')
    if attributeConfig && attributeConfig.operator
      for operator in attributeConfig.operator
        operatorName = App.i18n.translateInline(operator)
        selected = ''
        if meta.operator is operator
          selected = 'selected="selected"'
        selection.append("<option value=\"#{operator}\" #{selected}>#{operatorName}</option>")
      selection

    elementRow.find('.js-operator select').replaceWith(selection)

    @buildPreCondition(elementFull, elementRow, groupAndAttribute, elements, meta, attribute)

  @buildPreCondition: (elementFull, elementRow, groupAndAttribute, elements, meta, attributeConfig) ->
    currentOperator = elementRow.find('.js-operator option:selected').attr('value')
    currentPreCondition = elementRow.find('.js-preCondition option:selected').attr('value')

    if !meta.pre_condition
      meta.pre_condition = currentPreCondition

    toggleValue = =>
      preCondition = elementRow.find('.js-preCondition option:selected').attr('value')
      if preCondition isnt 'specific'
        elementRow.find('.js-value select').html('')
        elementRow.find('.js-value').addClass('hide')
      else
        elementRow.find('.js-value').removeClass('hide')
        @buildValue(elementFull, elementRow, groupAndAttribute, elements, meta, attribute)

    # force to use auto complition on user lookup
    attribute = _.clone(attributeConfig)

    name = "#{attribute.name}::#{groupAndAttribute}::value"
    attributeSelected = elements[groupAndAttribute]

    preCondition = false
    if attributeSelected.relation is 'User'
      preCondition = 'user'
      attribute.tag = 'user_autocompletion'
    if attributeSelected.relation is 'Organization'
      preCondition = 'org'
      attribute.tag = 'autocompletion_ajax'
    if !preCondition
      elementRow.find('.js-preCondition select').html('')
      elementRow.find('.js-preCondition').closest('.controls').addClass('hide')
      toggleValue()
      @buildValue(elementFull, elementRow, groupAndAttribute, elements, meta, attribute)
      return

    elementRow.find('.js-preCondition').closest('.controls').removeClass('hide')
    name = "#{attribute.name}::#{groupAndAttribute}::pre_condition"

    selection = $("<select class=\"form-control\" name=\"#{name}\" ></select>")
    options = {}
    if preCondition is 'user'
      options =
        'current_user.id': App.i18n.translateInline('current user')
        'specific': App.i18n.translateInline('specific user')

      if attributeSelected.null is true
        options['not_set'] = App.i18n.translateInline('unassign user')

    else if preCondition is 'org'
      options =
        'current_user.organization_id': App.i18n.translateInline('current user organization')
        'specific': App.i18n.translateInline('specific organization')

    for key, value of options
      selected = ''
      if key is meta.pre_condition
        selected = 'selected="selected"'
      selection.append("<option value=\"#{key}\" #{selected}>#{App.i18n.translateInline(value)}</option>")
    elementRow.find('.js-preCondition').closest('.controls').removeClass('hide')
    elementRow.find('.js-preCondition select').replaceWith(selection)

    elementRow.find('.js-preCondition select').bind('change', (e) ->
      toggleValue()
    )

    @buildValue(elementFull, elementRow, groupAndAttribute, elements, meta, attribute)
    toggleValue()

  @buildValue: (elementFull, elementRow, groupAndAttribute, elements, meta, attribute) ->
    name = "#{attribute.name}::#{groupAndAttribute}::value"

    # build new item
    attributeConfig = elements[groupAndAttribute]
    config = _.clone(attributeConfig)

    if config.relation is 'User'
      config.tag = 'user_autocompletion'
    if config.relation is 'Organization'
      config.tag = 'autocompletion_ajax'

    # render ui element
    item = ''
    if config && App.UiElement[config.tag]
      config['name'] = name
      if attribute.value && attribute.value[groupAndAttribute]
        config['value'] = _.clone(attribute.value[groupAndAttribute]['value'])
      config.multiple = false
      config.nulloption = config.null
      if config.tag is 'checkbox'
        config.tag = 'select'
      tagSearch = "#{config.tag}_search"
      if config.tag is 'datetime'
        config.validationContainer = 'self'
      if App.UiElement[tagSearch]
        item = App.UiElement[tagSearch].render(config, {})
      else
        item = App.UiElement[config.tag].render(config, {})

    relative_operators = [
      'before (relative)',
      'within next (relative)',
      'within last (relative)',
      'after (relative)',
      'till (relative)',
      'from (relative)',
      'relative'
    ]

    upcoming_operator = meta.operator

    if !_.include(config.operator, upcoming_operator)
      if Array.isArray(config.operator)
        upcoming_operator = config.operator[0]
      else
        upcoming_operator = null

    if _.include(relative_operators, upcoming_operator)
      config['name'] = "#{attribute.name}::#{groupAndAttribute}"
      if attribute.value && attribute.value[groupAndAttribute]
        config['value'] = _.clone(attribute.value[groupAndAttribute])
      item = App.UiElement['time_range'].render(config, {})

    elementRow.find('.js-setAttribute > .flex > .js-value').removeClass('hide').html(item)

  @buildNotificationArea: (notificationType, elementFull, elementRow, groupAndAttribute, elements, meta, attribute) ->

    return if elementRow.find(".js-setNotification .js-body-#{notificationType}").get(0)

    elementRow.find('.js-setNotification').empty()

    options =
      'article_last_sender': 'Article Last Sender'
      'ticket_owner': 'Owner'
      'ticket_customer': 'Customer'
      'ticket_agents': 'All Agents'

    whatsappOptions =
      'ticket_customer': 'Customer'

    name = "#{attribute.name}::notification.#{notificationType}"

    messageLength = switch notificationType
      when 'sms' then 160
      else 200000

    # meta.recipient was a string in the past (single-select) so we convert it to array if needed
    if !_.isArray(meta.recipient)
      meta.recipient = [meta.recipient]

    columnSelectOptions = []
    for key, value of options
      selected = undefined
      for recipient in meta.recipient
        if key is recipient
          selected = true
      columnSelectOptions.push({ value: key, name: App.i18n.translatePlain(value), selected: selected })

    # In whatsapp case
    columnWhatsappSelectOptions = []
    for key, value of whatsappOptions
      selected = undefined
      for recipient in meta.recipient
        if key is recipient
          selected = true
      columnWhatsappSelectOptions.push({ value: key, name: App.i18n.translatePlain(value), selected: selected })

    columnWhatsappSelectRecipientUserOptions = []
    for user in App.User.all()
      key = "userid_#{user.id}"
      isCustomer = user.permission('ticket.customer')
      selected = undefined
      for recipient in meta.recipient
        if key is recipient
          selected = true
      if isCustomer
        columnWhatsappSelectRecipientUserOptions.push({ value: key, name: "#{user.firstname} #{user.lastname}", selected: selected })

    # In whatsapp trigger case, removes variable section for choosing recipient
    if notificationType is 'whatsapp'
      columnSelectRecipient = new App.ColumnSelect
        attribute:
          name:    "#{name}::recipient"
          options: [
            {
              label: 'Variables',
              group: columnWhatsappSelectOptions
            },
            {
              label: 'User',
              group: columnWhatsappSelectRecipientUserOptions
            },
          ]
    else
      columnSelectRecipient = new App.ColumnSelect
        attribute:
          name:    "#{name}::recipient"
          options: [
            {
              label: 'Variables',
              group: columnSelectOptions
            },
            {
              label: 'User',
              group: columnSelectRecipientUserOptions
            },
          ]

    columnSelectRecipientUserOptions = []
    for user in App.User.all()
      key = "userid_#{user.id}"
      selected = undefined
      for recipient in meta.recipient
        if key is recipient
          selected = true
      columnSelectRecipientUserOptions.push({ value: key, name: "#{user.firstname} #{user.lastname}", selected: selected })

    columnSelectRecipient = new App.ColumnSelect
      attribute:
        name:    "#{name}::recipient"
        options: [
          {
            label: 'Variables',
            group: columnSelectOptions
          },
          {
            label: 'User',
            group: columnSelectRecipientUserOptions
          },
        ]

    selectionRecipient = columnSelectRecipient.element()

    if notificationType is 'webhook'
      notificationElement = $( App.view('generic/ticket_perform_action/webhook')(
        attribute: attribute
        name: name
        notificationType: notificationType
        meta: meta || {}
      ))

      notificationElement.find('.js-recipient select').replaceWith(selectionRecipient)


      if App.Webhook.search(filter: { active: true }).length isnt 0 || !_.isEmpty(meta.webhook_id)
        webhookSelection = App.UiElement.select.render(
          name: "#{name}::webhook_id"
          multiple: false
          null: false
          relation: 'Webhook'
          value: meta.webhook_id
          translate: false
          nulloption: true
        )
      else
        webhookSelection = App.view('generic/ticket_perform_action/webhook_not_available')( attribute: attribute )

      notificationElement.find('.js-webhooks').html(webhookSelection)

    else if notificationType is 'whatsapp'
      notificationElement = $( App.view('generic/ticket_perform_action/notification')(
        attribute: attribute
        name: name
        notificationType: notificationType
        meta: meta || {}
      ))

      notificationElement.find('.js-recipient select').replaceWith(selectionRecipient)

      visibilitySelection = App.UiElement.select.render(
        name: "#{name}::internal"
        multiple: false
        null: false
        options: { true: 'internal', false: 'public' }
        value: meta.internal || 'false'
        translate: true
      )

      notificationElement.find('.js-internal').html(visibilitySelection)

      notificationElement.find('.js-body div[contenteditable="true"]').ce(
        mode: 'richtext'
        placeholder: 'message'
        maxlength: messageLength
      )
      new App.WidgetPlaceholder(
        el: notificationElement.find('.js-body div[contenteditable="true"]').parent()
        objects: [
          {
            prefix: 'ticket'
            object: 'Ticket'
            display: 'Ticket'
          },
          {
            prefix: 'article'
            object: 'TicketArticle'
            display: 'Article'
          },
          {
            prefix: 'user'
            object: 'User'
            display: 'Current User'
          },
        ]
      )
    else
      notificationElement = $( App.view('generic/ticket_perform_action/notification')(
        attribute: attribute
        name: name
        notificationType: notificationType
        meta: meta || {}
      ))

      notificationElement.find('.js-recipient select').replaceWith(selectionRecipient)

      visibilitySelection = App.UiElement.select.render(
        name: "#{name}::internal"
        multiple: false
        null: false
        options: { true: 'internal', false: 'public' }
        value: meta.internal || 'false'
        translate: true
      )

      includeAttachmentsCheckbox = App.UiElement.select.render(
        name: "#{name}::include_attachments"
        multiple: false
        null: false
        options: { true: 'Yes', false: 'No' }
        value: meta.include_attachments || 'false'
        translate: true
      )

      notificationElement.find('.js-internal').html(visibilitySelection)
      notificationElement.find('.js-include_attachments').html(includeAttachmentsCheckbox)

      notificationElement.find('.js-body div[contenteditable="true"]').ce(
        mode: 'richtext'
        placeholder: 'message'
        maxlength: messageLength
      )
      new App.WidgetPlaceholder(
        el: notificationElement.find('.js-body div[contenteditable="true"]').parent()
        objects: [
          {
            prefix: 'ticket'
            object: 'Ticket'
            display: 'Ticket'
          },
          {
            prefix: 'article'
            object: 'TicketArticle'
            display: 'Article'
          },
          {
            prefix: 'user'
            object: 'User'
            display: 'Current User'
          },
        ]
      )

    elementRow.find('.js-setNotification').html(notificationElement).removeClass('hide')

    if App.Config.get('smime_integration') == true
      selection = App.UiElement.select.render(
        name: "#{name}::sign"
        multiple: false
        options: {
          'no': 'Do not sign email'
          'discard': 'Sign email (if not possible, discard notification)'
          'always': 'Sign email (if not possible, send notification anyway)'
        }
        value: meta.sign
        translate: true
      )

      elementRow.find('.js-sign').html(selection)

      selection = App.UiElement.select.render(
        name: "#{name}::encryption"
        multiple: false
        options: {
          'no': 'Do not encrypt email'
          'discard': 'Encrypt email (if not possible, discard notification)'
          'always': 'Encrypt email (if not possible, send notification anyway)'
        }
        value: meta.encryption
        translate: true
      )

      elementRow.find('.js-encryption').html(selection)

  @buildArticleArea: (articleType, elementFull, elementRow, groupAndAttribute, elements, meta, attribute) ->

    return if elementRow.find(".js-setArticle .js-body-#{articleType}").get(0)

    elementRow.find('.js-setArticle').empty()

    name = "#{attribute.name}::article.#{articleType}"
    selection = App.UiElement.select.render(
      name: "#{name}::internal"
      multiple: false
      null: false
      label: 'Visibility'
      options: { true: 'internal', false: 'public' }
      value: meta.internal
      translate: true
    )
    articleElement = $( App.view('generic/ticket_perform_action/article')(
      attribute: attribute
      name: name
      articleType: articleType
      meta: meta || {}
    ))
    articleElement.find('.js-internal').html(selection)
    articleElement.find('.js-body div[contenteditable="true"]').ce(
      mode: 'richtext'
      placeholder: 'message'
      maxlength: 200000
    )
    new App.WidgetPlaceholder(
      el: articleElement.find('.js-body div[contenteditable="true"]').parent()
      objects: [
        {
          prefix: 'ticket'
          object: 'Ticket'
          display: 'Ticket'
        },
        {
          prefix: 'article'
          object: 'TicketArticle'
          display: 'Article'
        },
        {
          prefix: 'user'
          object: 'User'
          display: 'Current User'
        },
      ]
    )

    elementRow.find('.js-setArticle').html(articleElement).removeClass('hide')

  @humanText: (condition) ->
    none = App.i18n.translateContent('No filter.')
    return [none] if _.isEmpty(condition)
    [defaults, groups, operators, elements] = @defaults()
    rules = []
    for attribute, value of condition

      objectAttribute = attribute.split(/\./)

      # get stored params
      if meta && objectAttribute[1]
        model = toCamelCase(objectAttribute[0])
        config = elements[attribute]

        valueHuman = []
        if _.isArray(value)
          for data in value
            r = @humanTextLookup(config, data)
            valueHuman.push r
        else
          valueHuman.push @humanTextLookup(config, value)

        if valueHuman.join
          valueHuman = valueHuman.join(', ')
        rules.push "#{App.i18n.translateContent('Set')} <b>#{App.i18n.translateContent(model)} -> #{App.i18n.translateContent(config.display)}</b> #{App.i18n.translateContent('to')} <b>#{valueHuman}</b>."

    return [none] if _.isEmpty(rules)
    rules

  @humanTextLookup: (config, value) ->
    return value if !App[config.relation]
    return value if !App[config.relation].exists(value)
    data = App[config.relation].fullLocal(value)
    return value if !data
    if data.displayName
      return App.i18n.translateContent( data.displayName() )
    valueHuman.push App.i18n.translateContent( data.name )
