# frozen_string_literal: true

module FormulaCustomField
  # Issue only: formula fields are read-only in the issue form, regardless of workflow permissions.
  module IssuePatch
    def read_only_attribute_names(user = nil)
      super + FormulaCustomField.formula_field_ids.map(&:to_s)
    end
  end
end
