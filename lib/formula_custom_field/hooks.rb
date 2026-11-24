# frozen_string_literal: true

module FormulaCustomField
  # adds the formula options to Administration > Custom fields
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_custom_fields_form_upper_box,
              partial: 'hooks/formula_custom_field/custom_field_form'
  end
end
