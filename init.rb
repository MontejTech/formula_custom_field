# frozen_string_literal: true

require_relative 'lib/formula_custom_field'

Redmine::Plugin.register :formula_custom_field do
  name 'Formula Custom Fields'
  author 'Dipak Mali - Montej Tech LLP'
  description 'Custom fields whose value is calculated on the server from a safe formula (no JavaScript, no eval)'
  version '0.1.0'
  url 'https://github.com/MontejTech/formula_custom_field'
  requires_redmine version_or_higher: '5.0.0'
end

# Redmine-dependent parts (one constant per file; also autoloadable by Zeitwerk)
%w[calculator custom_field_patch customized_patch issue_patch hooks].each do |f|
  require_relative "lib/formula_custom_field/#{f}"
end

# Redmine runs every plugin's init.rb inside its own to_prepare block (on boot and on each
# code reload), so patch directly here. A nested `to_prepare` would never be executed.
FormulaCustomField.apply_patches
