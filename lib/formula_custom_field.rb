# frozen_string_literal: true

# Pure-Ruby formula engine (no Rails needed – testable standalone with `ruby -Ilib test/engine_test.rb`).
# One constant per file, so Redmine's Zeitwerk autoloader is happy.
%w[formula_error parse_error evaluation_error values functions lexer parser evaluator attributes].each do |f|
  require_relative "formula_custom_field/#{f}"
end

module FormulaCustomField
  CUSTOMIZED_MODELS = %w[Issue Project TimeEntry User Group Version Enumeration Document].freeze

  # convenience for tests / console: FormulaCustomField.evaluate('1 + 2')
  def self.evaluate(source, &resolver)
    Evaluator.new(&resolver).evaluate(Parser.parse(source))
  end

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
    CustomField.include(CustomFieldPatch) unless CustomField.include?(CustomFieldPatch)

    CUSTOMIZED_MODELS.each do |name|
      model = name.safe_constantize
      next unless model && model.method_defined?(:custom_field_values)

      model.include(CustomizedPatch) unless model.include?(CustomizedPatch)
    end

    Issue.prepend(IssuePatch) unless Issue.include?(IssuePatch)
  end
end
