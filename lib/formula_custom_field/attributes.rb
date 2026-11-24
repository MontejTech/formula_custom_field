# frozen_string_literal: true

module FormulaCustomField
  # Attributes a formula may read with {@attribute}. Column names of the customized
  # model, minus anything that looks sensitive, plus a few safe computed extras.
  module Attributes
    EXTRAS = { 'Issue' => %w[spent_hours total_spent_hours total_estimated_hours] }.freeze
    SENSITIVE = /password|salt|token|key|twofa|mail|api/i.freeze

    def self.allowed?(klass, name)
      return false if klass.nil? || name.to_s =~ SENSITIVE

      klass.column_names.include?(name.to_s) || Array(EXTRAS[klass.name]).include?(name.to_s)
    end
  end
end
