window.FormRenderer = FormRenderer = Backbone.View.extend
  defaults:
    enablePages: true
    screendoorBase: 'https://screendoor.dobt.co'
    target: '[data-formrenderer]'
    validateImmediately: false
    response: {}
    responderLanguage: undefined
    preview: false
    skipValidation: undefined
    saveParams: {}
    showLabels: false
    scrollToPadding: 0
    plugins: [
      'Autosave'
      'WarnBeforeUnload'
      'BottomBar'
      'ErrorBar'
      'SavedSession'
    ]

  ## Initialization logic

  constructor: (options) ->
    @fr = @
    @options = $.extend {}, @defaults, options
    @requests = 0
    @state = new Backbone.Model
      hasChanges: false
    @setElement $(@options.target)
    @$el.addClass 'fr_form'
    @$el.data 'formrenderer-instance', @
    @subviews = { pages: {} }

    @serverHeaders =
      'X-FR-Version': FormRenderer.VERSION
      'X-FR-URL': document.URL

    @plugins = _.map @options.plugins, (pluginName) =>
      new FormRenderer.Plugins[pluginName](@)

    p.beforeFormLoad?() for p in @plugins

    # Loading state
    @$el.html JST['main'](@)
    @trigger 'viewRendered', @

    @loadFromServer =>
      @$el.find('.fr_loading').remove()
      @initFormComponents(@options.response_fields, @options.response.responses)
      @initPages()
      if @options.enablePages then @initPagination() else @initNoPagination()
      p.afterFormLoad?() for p in @plugins
      @validate() if @options.validateImmediately
      @trigger 'ready'
      @options.onReady?()

    # If @$el is a <form>, make extra-sure that it can't be submitted natively
    @$el.on 'submit', (e) ->
      e.preventDefault()

    @ # explicitly return self

  corsSupported: ->
    'withCredentials' of new XMLHttpRequest()

  projectUrl: ->
    "#{@options.screendoorBase}/projects/#{@options.project_id}"

  # Fetch the details of this form from the Screendoor API
  loadFromServer: (cb) ->
    return cb() if @options.response_fields? && @options.response.responses?

    $.ajax
      url: "#{@options.screendoorBase}/api/form_renderer/load"
      type: 'get'
      dataType: 'json'
      data: @loadParams()
      headers: @serverHeaders
      success: (data) =>
        @options.response_fields ||= data.project.response_fields
        @options.response.responses ||= (data.response?.responses || {})

        if !@options.afterSubmit?
          @options.afterSubmit =
            method: 'page'
            html: data.project.after_response_page_html || "<p>#{FormRenderer.t.thanks}</p>"

        cb()
      error: (xhr) =>
        if !@corsSupported()
          @$el.
            find('.fr_loading').
            html(FormRenderer.t.not_supported.replace(/\:url/g, @projectUrl()))
        else
          @$el.find('.fr_loading').text(
            "#{FormRenderer.t.error_loading}: \"#{xhr.responseJSON?.error || 'Unknown'}\""
          )
          @trigger 'errorSaving', xhr

  # Build pages, which contain the response fields views.
  initPages: ->
    addPage = =>
      @subviews.pages[currentPageInLoop] = new FormRenderer.Views.Page(form_renderer: @)

    @numPages = @formComponents.where(field_type: 'page_break').length + 1
    @state.set 'activePage', 1
    currentPageInLoop = 1
    addPage()

    @formComponents.each (rf) =>
      if rf.get('field_type') == 'page_break'
        currentPageInLoop++
        addPage()
      else
        @subviews.pages[currentPageInLoop].models.push rf

    for pageNumber, page of @subviews.pages
      @$el.append page.render().el

  initPagination: ->
    @subviews.pagination = new FormRenderer.Views.Pagination(form_renderer: @)
    @$el.prepend @subviews.pagination.render().el
    @subviews.pages[@state.get('activePage')].show()

  initNoPagination: ->
    for pageNumber, page of @subviews.pages
      page.show()

  ## Pages / Validation

  activatePage: (newPageNumber) ->
    @subviews.pages[@state.get('activePage')].hide()
    @subviews.pages[newPageNumber].show()
    window.scrollTo(0, @options.scrollToPadding)
    @state.set 'activePage', newPageNumber

  validate: ->
    page.validate() for _, page of @subviews.pages
    @trigger 'afterValidate afterValidate:all'
    return @areAllPagesValid()

  isPageVisible: (pageNumber) ->
    @subviews.pages[pageNumber]?.isVisible()

  isPageValid: (pageNumber) ->
    @subviews.pages[pageNumber]?.isValid()

  focusFirstError: ->
    page = @invalidPages()[0]
    @activatePage page
    view = @subviews.pages[page].firstViewWithError()
    window.scrollTo(0, view.$el.offset().top - @options.scrollToPadding)
    view.focus()

  invalidPages: ->
    _.filter [1..@numPages], (x) =>
      @isPageValid(x) == false

  areAllPagesValid: ->
    @invalidPages().length == 0

  visiblePages: ->
    _.tap [], (a) =>
      for num, _ of @subviews.pages
        a.push(parseInt(num, 10)) if @isPageVisible(num)

  isFirstPage: ->
    first = @visiblePages()[0]
    !first || (@state.get('activePage') == first)

  isLastPage: ->
    last = _.last(@visiblePages())
    !last || (@state.get('activePage') == last)

  previousPage: ->
    @visiblePages()[_.indexOf(@visiblePages(), @state.get('activePage')) - 1]

  nextPage: ->
    @visiblePages()[_.indexOf(@visiblePages(), @state.get('activePage')) + 1]

  handlePreviousPage: ->
    @activatePage @previousPage()

  handleNextPage: ->
    if @isLastPage() || !@options.enablePages
      @submit()
    else
      @activatePage(@nextPage())

  ## Saving

  loadParams: ->
    {
      v: 0
      response_id: @options.response.id
      project_id: @options.project_id
      responder_language: @options.responderLanguage
    }

  saveParams: ->
    _.extend(
      @loadParams(),
      {
        skip_validation: @options.skipValidation
      },
      @options.saveParams,
      @followUpFormParams()
    )

  followUpFormParams: ->
    if @options.follow_up_form_id? && @options.initial_response_id?
      {
        follow_up_form_id: @options.follow_up_form_id,
        initial_response_id: @options.initial_response_id
      }
    else
      {}

  responsesChanged: ->
    @state.set('hasChanges', true)

    # Handle the edge case when the form is saved while there's an AJAX
    # request pending.
    if @isSaving
      @changedWhileSaving = true

  # Options:
  #   submit (boolean) if true, tell the server to submit the response
  #   cb (function) a callback that will be called on success
  save: (options = {}) ->
    return if @isSaving
    @requests += 1
    @isSaving = true
    @changedWhileSaving = false

    $.ajax
      url: "#{@options.screendoorBase}/api/form_renderer/save"
      type: 'post'
      contentType: 'application/json'
      dataType: 'json'
      data: JSON.stringify(
        _.extend @saveParams(), {
          raw_responses: @getValue(),
          submit: if options.submit then true else undefined
        }
      )
      headers: @serverHeaders
      complete: =>
        @requests -= 1
        @isSaving = false
        @trigger 'afterSave'
      success: (data) =>
        @state.set
          hasChanges: @changedWhileSaving
          hasServerErrors: false
        @options.response.id = data.response_id
        options.cb?.apply(@, arguments)
      error: (xhr) =>
        @state.set
          hasServerErrors: true
          serverErrorText: xhr.responseJSON?.error
          serverErrorKey: xhr.responseJSON?.error_key
          submitting: false

  waitForRequests: (cb) ->
    if @requests > 0
      setTimeout ( => @waitForRequests(cb) ), 100
    else
      cb()

  submit: (opts = {}) ->
    return unless opts.skipValidation || @options.skipValidation || @validate()
    @state.set('submitting', true)

    @waitForRequests =>
      if @options.preview
        @_preview()
      else
        @save submit: true, cb: =>
          @trigger 'afterSubmit'
          @_afterSubmit()

  _afterSubmit: ->
    as = @options.afterSubmit

    if typeof as == 'function'
      as.call @
    else if typeof as == 'string'
      window.location = as.replace(':id', @options.response.id.split(',')[0])
    else if typeof as == 'object' && as.method == 'page'
      $page = $("<div class='fr_after_submit_page'>#{as.html}</div>")
      @$el.replaceWith($page)
    else
      console.log '[FormRenderer] Not sure what to do...'

  _preview: ->
    cb = =>
      window.location = @options.preview.replace(':id', @options.response.id.split(',')[0])

    # If we know the response ID and there are no changes, we can bypass
    # the call to @save() entirely
    if !@state.get('hasChanges') && @options.response.id
      cb()
    else
      @save cb: cb

  reflectConditions: ->
    page.reflectConditions() for _, page of @subviews.pages
    @subviews.pagination?.render()

## Class-level configs

FormRenderer.BUTTON_CLASS = 'fr_button'
FormRenderer.DEFAULT_LAT_LNG = [40.7700118, -73.9800453]
FormRenderer.MAPBOX_URL = 'https://api.tiles.mapbox.com/mapbox.js/v2.1.4/mapbox.js'

# Keep in-sync with Screendoor
FormRenderer.EMAIL_REGEX = /^\s*([^@\s]{1,64})@((?:[-a-z0-9]+\.)+[a-z]{2,})\s*$/i

FormRenderer.ADD_ROW_ICON = '+'
FormRenderer.REMOVE_ROW_ICON = '-'
FormRenderer.REMOVE_ENTRY_LINK_CLASS = 'fr_group_entry_remove'
FormRenderer.REMOVE_ENTRY_LINK_HTML = 'Remove'

## Settin' these up for later

FormRenderer.Views = {}
FormRenderer.Models = {}
FormRenderer.Plugins = {}

## Validators have been deprecated, but are kept here for backwards-compatibility.
FormRenderer.Validators = {
  EmailValidator: {
    VALID_REGEX: FormRenderer.EMAIL_REGEX
  }
};

## Plugin utilities

FormRenderer.addPlugin = (x) ->
  @::defaults.plugins.push(x)

FormRenderer.removePlugin = (x) ->
  @::defaults.plugins = _.without(@::defaults.plugins, x)
