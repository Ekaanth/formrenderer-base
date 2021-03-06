FormRenderer.Models.ResponseFieldEmail = FormRenderer.Models.ResponseField.extend
  valueType: 'string'
  field_type: 'email'
  validateType: ->
    unless @get('value').match(FormRenderer.EMAIL_REGEX)
      'email'

FormRenderer.Views.ResponseFieldEmail = FormRenderer.Views.ResponseField.extend
  field_type: 'email'
