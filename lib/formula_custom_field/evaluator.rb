# frozen_string_literal: true

module FormulaCustomField
  class Evaluator
    # resolver: ->(kind, key) { raw value }
    def initialize(&resolver)
      @resolver = resolver
    end

    def evaluate(node)
      case node[0]
      when :num, :str, :bool then node[1]
      when :nil then nil
      when :ref then Values.normalize(@resolver.call(node[1], node[2]))
      when :neg then (n = Values.num(evaluate(node[1]))) && -n
      when :bin then binary(node[1], evaluate(node[2]), evaluate(node[3]))
      when :call then call(node[1], node[2])
      else raise EvaluationError, "Unknown node #{node[0]}"
      end
    end

    private

    def call(name, args)
      if name == 'IF'
        return evaluate(args[1]) if Values.truthy?(evaluate(args[0]))

        return args[2] ? evaluate(args[2]) : nil
      end
      Functions.call(name, args.map { |a| evaluate(a) })
    end

    def binary(op, l, r)
      case op
      when '&' then Values.text(l) + Values.text(r)
      when '=' then Values.eq(l, r)
      when '<>' then !Values.eq(l, r)
      when '<', '<=', '>', '>='
        c = Values.cmp(l, r)
        return false if c.nil?

        { '<' => c.negative?, '<=' => c <= 0, '>' => c.positive?, '>=' => c >= 0 }[op]
      else arithmetic(op, l, r)
      end
    end

    def arithmetic(op, l, r)
      return date_arithmetic(op, l, r) if l.is_a?(Date) || r.is_a?(Date)

      a = Values.num(l)
      b = Values.num(r)
      return nil if a.nil? || b.nil?

      case op
      when '+' then a + b
      when '-' then a - b
      when '*' then a * b
      when '/' then b.zero? ? nil : a.div(b, 20)
      when '%' then b.zero? ? nil : a % b
      when '^' then power(a, b)
      end
    end

    def power(a, b)
      return nil if a.negative? && !b.frac.zero?

      f = a.to_f**b.to_f
      f.is_a?(Float) && f.finite? ? BigDecimal(f.to_s) : nil
    end

    def date_arithmetic(op, l, r)
      return nil if l.nil? || r.nil?

      if l.is_a?(Date) && r.is_a?(Date)
        raise EvaluationError, 'two dates can only be subtracted' unless op == '-'

        BigDecimal((l - r).to_i)
      elsif l.is_a?(Date) && %w[+ -].include?(op)
        n = Values.num(r).to_i
        op == '+' ? l + n : l - n
      elsif r.is_a?(Date) && op == '+'
        r + Values.num(l).to_i
      else
        raise EvaluationError, "operator #{op} cannot be used with a date"
      end
    end
  end
end
