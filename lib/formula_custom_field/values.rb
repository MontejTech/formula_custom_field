# frozen_string_literal: true

require 'bigdecimal'
require 'date'

module FormulaCustomField
  module Values
    module_function

    # Converts anything coming from Redmine into one of:
    # nil, true/false, BigDecimal, Date, String, Array of those
    def normalize(v)
      case v
      when nil, true, false, BigDecimal, String then v
      when Integer then BigDecimal(v)
      when Float then v.finite? ? BigDecimal(v.to_s) : nil
      when Date then v.to_date
      when Time then v.to_date
      when Array then v.map { |x| normalize(x) }
      else v.to_s
      end
    end

    def blank?(v)
      v.nil? || (v.is_a?(String) && v.strip.empty?) || (v.is_a?(Array) && v.empty?)
    end

    # numeric coercion; nil stays nil (blank propagates)
    def num(v)
      case v
      when nil then nil
      when BigDecimal then v
      when true then BigDecimal(1)
      when false then BigDecimal(0)
      when String
        s = v.strip
        return nil if s.empty?

        begin
          BigDecimal(s)
        rescue ArgumentError
          raise EvaluationError, "'#{v}' is not a number"
        end
      when Date then raise EvaluationError, 'a date cannot be used as a number here'
      else raise EvaluationError, 'a multi-valued field cannot be used as a number'
      end
    end

    def to_date(v)
      case v
      when nil then nil
      when Date then v
      when String
        return nil if v.strip.empty?

        begin
          Date.iso8601(v.strip)
        rescue ArgumentError
          raise EvaluationError, "'#{v}' is not a date (use YYYY-MM-DD)"
        end
      else raise EvaluationError, 'expected a date'
      end
    end

    def fmt_number(bd)
      return bd.to_i.to_s if bd.frac.zero?

      bd.round(10, :half_up).to_s('F').sub(/0+\z/, '').sub(/\.\z/, '')
    end

    def text(v)
      case v
      when nil then ''
      when true then 'TRUE'
      when false then 'FALSE'
      when BigDecimal then fmt_number(v)
      when Date then v.iso8601
      when Array then v.map { |x| text(x) }.join(', ')
      else v.to_s
      end
    end

    def truthy?(v)
      case v
      when nil, false then false
      when BigDecimal then !v.zero?
      when String then !v.strip.empty?
      when Array then !v.empty?
      else true
      end
    end

    def eq(a, b)
      return true if blank?(a) && blank?(b)
      return false if blank?(a) || blank?(b)
      return false unless a.class == b.class
      return a.casecmp?(b) if a.is_a?(String)

      a == b
    end

    # returns -1/0/1, or nil when one side is blank
    def cmp(a, b)
      return nil if blank?(a) || blank?(b)
      raise EvaluationError, 'cannot compare a list' if a.is_a?(Array) || b.is_a?(Array)
      raise EvaluationError, 'cannot compare values of different types' unless a.class == b.class
      return a.downcase <=> b.downcase if a.is_a?(String)

      a <=> b
    end
  end
end
