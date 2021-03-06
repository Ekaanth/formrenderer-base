FormRenderer.Models.BaseFormComponent = Backbone.DeepModel.extend
  # @param @fr the fr instance
  # @param @parent either the fr instance, or the RepeatingGroupEntry
  # that this field belongs to.
  initialize: (_, @fr, @parent) ->
    @calculateVisibility()

  sync: ->

  # Not named `validate` beacuse that conflicts with Backbone
  validateComponent: ->

  setExistingValue: ->

  shouldPersistValue: ->
    @isVisible &&
    (@group || @input_field)

  getConditions: ->
    @get('conditions') || []

  isRequired: ->
    @get('required')

  isConditional: ->
    @getConditions().length > 0

  parentGroupIsHidden: ->
    @parent.repeatingGroup? && !@parent.repeatingGroup.isVisible

  # @return [Boolean] true if the new value is different than the old value
  calculateVisibilityIsChanged: ->
    prevValue = !!@isVisible
    @calculateVisibility()
    prevValue != @isVisible

  calculateVisibility: ->
    @isVisible = @_calculateIsVisible()

  _calculateIsVisible: ->
    # If we're not in a form_renderer context, this field is visible
    return true unless @renderingRespondentForm()

    # Otherwise, it's only visible if it satisfies its conditions of visibility.
    @satisfiesConditions(@parent.formComponents)

  # NOTE: this method is called directly from FormBuilder
  satisfiesConditions: (formComponents) ->
    # If no conditions, it's visible
    return true unless @isConditional()

    _[@conditionMethod()] @getConditions(), (conditionHash) =>
      conditionChecker = new FormRenderer.ConditionChecker(
        formComponents.get(conditionHash.response_field_id),
        conditionHash
      )

      conditionChecker.isVisible()

  conditionMethod: ->
    if @get('condition_method') == 'any'
      'any'
    else
      'all'

  renderingRespondentForm: ->
    # If we don't have a form_renderer context, fields can still be rendered.
    # This function lets us branch based on whether we're on a form or e.g. in a formbuilder.
    !!@fr
