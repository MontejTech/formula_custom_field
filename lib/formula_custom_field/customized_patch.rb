# frozen_string_literal: true

module FormulaCustomField
  # Included into every customizable model (Issue, Project, ...): before the record is
  # validated, all its formula custom fields are recalculated server side.
  module CustomizedPatch
    extend ActiveSupport::Concern

    included do
      before_validation :calculate_formula_custom_fields
    end

    private

    def calculate_formula_custom_fields
      return true unless FormulaCustomField.table_ready?
      return true unless custom_field_values.any? { |v| v.custom_field.formula_field? }

      Calculator.new(self).apply!
      true
    end
  end
end
