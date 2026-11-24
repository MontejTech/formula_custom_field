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

  # Computes every formula field of one customized object (issue, project, ...).
  class Calculator
    def initialize(customized)
      @obj = customized
      @cfvs = customized.custom_field_values
      @by_id = @cfvs.index_by { |v| v.custom_field.id }
      @memo = {}
      @stack = []
    end

    # { custom_field_id => String value to store }
    def compute
      result = {}
      @cfvs.each do |cfv|
        field = cfv.custom_field
        next unless field.formula_field?

        result[field.id] = serialize(field, formula_result(cfv))
      rescue FormulaError => e
        log(field, e)
        result[field.id] = ''
      end
      result
    end

    # sets the computed values on the in-memory custom field values (persisted by Redmine on save)
    def apply!
      compute.each { |id, value| @by_id[id].value = value }
    end

    private

    def formula_result(cfv)
      field = cfv.custom_field
      return @memo[field.id] if @memo.key?(field.id)
      raise EvaluationError, "circular reference to '#{field.name}'" if @stack.include?(field.id)

      @stack.push(field.id)
      begin
        @memo[field.id] = evaluate(field)
      rescue FormulaError => e
        log(field, e)
        @memo[field.id] = nil
      ensure
        @stack.pop
      end
    end

    def evaluate(field)
      Evaluator.new { |kind, key| resolve(kind, key) }.evaluate(field.formula_ast)
    end

    def resolve(kind, key)
      case kind
      when :id then field_value(@by_id[key])
      when :attr then attribute(key)
      end
    end

    def field_value(cfv)
      return nil if cfv.nil?
      return formula_result(cfv) if cfv.custom_field.formula_field?

      cfv.custom_field.cast_value(cfv.value)
    end

    def attribute(name)
      raise EvaluationError, "attribute '#{name}' is not available" unless Attributes.allowed?(@obj.class, name)

      @obj.public_send(name)
    end

    def serialize(field, value)
      return '' if Values.blank?(value)

      case field.field_format
      when 'int' then BigDecimal(Values.num(value).round(0, :half_up)).to_i.to_s
      when 'float' then Values.num(value).round(10, :half_up).to_s('F')
      when 'bool' then Values.truthy?(value) ? '1' : '0'
      when 'date'
        raise EvaluationError, 'the formula must return a date' unless value.is_a?(Date)

        value.iso8601
      else Values.text(value)
      end
    end

    def log(field, error)
      Rails.logger.warn("[formula_custom_field] #{@obj.class.name}##{@obj.id} field '#{field.name}': #{error.message}")
    end
  end
end
