# frozen_string_literal: true

module FormulaCustomField
  # Adds `is_formula` / `formula_expression` to CustomField, with validation.
  module CustomFieldPatch
    extend ActiveSupport::Concern

    SUPPORTED_FORMATS = %w[int float string text date bool].freeze

    included do
      safe_attributes 'is_formula', 'formula_expression'
      validate :validate_formula_expression, if: :formula_field?
    end

    def formula_field?
      has_attribute?(:is_formula) && is_formula? && formula_expression.present?
    end

    # parsed formula (cached per expression)
    def formula_ast
      if @formula_ast_source != formula_expression
        @formula_ast_source = formula_expression
        @formula_ast = Parser.parse(formula_expression)
      end
      @formula_ast
    end

    # custom fields referenced by this formula (used for cycle detection)
    def formula_dependencies
      Parser.references(formula_ast).map do |_, kind, key|
        case kind
        when :id then sibling_fields.detect { |f| f.id == key }
        end
      end.compact
    end

    private

    def sibling_fields
      @sibling_fields ||= CustomField.where(type: type).to_a
    end

    def validate_formula_expression
      unless SUPPORTED_FORMATS.include?(field_format) && !multiple?
        errors.add(:formula_expression, formula_t(:error_formula_unsupported_format, formats: SUPPORTED_FORMATS.join(', ')))
        return
      end

      @sibling_fields = nil
      @formula_ast_source = nil
      refs = Parser.references(formula_ast)
      refs.each { |_, kind, key| check_reference(kind, key) }
      check_cycle
    rescue FormulaError => e
      errors.add(:formula_expression, e.message)
    end

    def check_reference(kind, key)
      case kind
      when :id
        errors.add(:formula_expression, formula_t(:error_formula_unknown_field, id: key)) unless
          sibling_fields.any? { |f| f.id == key }
      when :attr
        errors.add(:formula_expression, formula_t(:error_formula_unknown_attribute, name: key)) unless
          Attributes.allowed?(self.class.respond_to?(:customized_class) ? self.class.customized_class : nil, key)
      end
    end

    def check_cycle(visited = [], field = self)
      field.formula_dependencies.each do |dep|
        if dep.id == id
          errors.add(:formula_expression, formula_t(:error_formula_circular))
          return
        end
        next if visited.include?(dep.id) || !dep.formula_field?

        check_cycle(visited << dep.id, dep)
        return if errors[:formula_expression].any?
      end
    end

    def formula_t(key, **options)
      ::I18n.t(key, **options)
    end
  end
end
