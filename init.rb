# frozen_string_literal: true

require_relative 'lib/formula_custom_field'

Redmine::Plugin.register :formula_custom_field do
  name 'Formula Custom Fields'
  author 'Dipak Mali - Montej Tech LLP'
  description 'Custom fields whose value is calculated on the server from a safe formula (no JavaScript, no eval)'
  version '0.1.0'
  requires_redmine version_or_higher: '5.0.0'
end

# hook listener needs Redmine::Hook, so it lives with the patches and is loaded here
require_relative 'lib/formula_custom_field/calculator'
require_relative 'lib/formula_custom_field/custom_field_patch'
require_relative 'lib/formula_custom_field/customized_patch'

Rails.configuration.to_prepare do
  FormulaCustomField.apply_patches
end
