# frozen_string_literal: true

require_relative 'formula_custom_field/engine'

module FormulaCustomField
  CUSTOMIZED_MODELS = %w[Issue Project TimeEntry User Group Version Enumeration Document].freeze

  def self.table_ready?
    CustomField.column_names.include?('is_formula')
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    false
  end

  def self.formula_field_ids
    return [] unless table_ready?

    CustomField.where(is_formula: true).pluck(:id)
  end

  # called from init.rb inside to_prepare (safe to run on every code reload)
  def self.apply_patches
    require_relative 'formula_custom_field/calculator'
    require_relative 'formula_custom_field/custom_field_patch'
    require_relative 'formula_custom_field/customized_patch'

    CustomField.include(CustomFieldPatch) unless CustomField.include?(CustomFieldPatch)

    CUSTOMIZED_MODELS.each do |name|
      model = name.safe_constantize
      next unless model && model.method_defined?(:custom_field_values)

      model.include(CustomizedPatch) unless model.include?(CustomizedPatch)
    end

    Issue.prepend(IssuePatch) unless Issue.include?(IssuePatch)
  end
end
