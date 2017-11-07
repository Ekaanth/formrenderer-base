before ->
  $('body').html('<div data-formrenderer />')

  @createFormRendererWithFieldDescription = (x) ->
    new FormRenderer
      project_id: 'dummy_val'
      response:
        id: 'xxx'
        responses: {}
      response_fields: [
        field_type: 'text'
        label: 'yooo'
        description: x
      ]

describe 'basic sanitization', ->
  before ->
    @createFormRendererWithFieldDescription "\n\nhihi<a href='http://www.\
google.com'>This is a link</a><script>alert('hi')</script>"

  it 'removes script tags', ->
    expect($('.fr_response_field script').length).to.equal(0)

  it 'preserves anchor tags', ->
    expect($('.fr_response_field a[href*=google]').attr('href'))
      .to
      .equal('http://www.google.com')

  it 'simple formats', ->
    expect($('.fr_response_field br').length).to.equal(2)

  it 'does not mess with existing link targets', ->
    expect($('.fr_response_field a').attr('target')).to.equal(undefined)

describe 'handling of undefiend', ->
  before ->
    new FormRenderer
      project_id: 'dummy_val'
      response:
        id: 'xxx'
        responses: {}
      response_fields: [
        field_type: 'block_of_text'
      ]

  it 'does not render undefined text', ->
    expect($('.fr_response_field:contains("undefined")').length).to.equal(0)

describe 'autolinking', ->
  before ->
    @createFormRendererWithFieldDescription """
      http://www.google.com
    """

  it 'preserves them', ->
    expect($('.fr_response_field a').length).to.equal(1)
    expect($('.fr_response_field a').attr('href')).to.equal('http://www.google.com')
    expect($('.fr_response_field a').attr('target')).to.equal('_blank')

describe 'formatAndSanitizeHTML', ->
  it 'prevents XSS', ->
    expect(FormRenderer.formatAndSanitizeHTML('<script>alert(1)</script>')).to.equal('')
    expect(FormRenderer.formatAndSanitizeHTML('<details open ontoggle=alert(1)>')).to.equal('')
