# frozen_string_literal: true

require 'bigdecimal'
require 'date'

module FormulaCustomField
  module Functions
    @registry = {}

    class << self
      attr_reader :registry

      def define(name, min, max = min, &impl)
        @registry[name] = { min: min, max: max, impl: impl }
      end

      def known?(name)
        @registry.key?(name)
      end

      def check_arity!(name, count)
        spec = @registry.fetch(name)
        return if count >= spec[:min] && count <= spec[:max]

        range = spec[:max] == Float::INFINITY ? "at least #{spec[:min]}" : (spec[:min] == spec[:max] ? spec[:min].to_s : "#{spec[:min]}-#{spec[:max]}")
        raise ParseError, "#{name} expects #{range} argument(s), got #{count}"
      end

      def call(name, args)
        @registry.fetch(name)[:impl].call(*args)
      end

      def names
        @registry.keys.sort
      end

      def numbers(args)
        args.flatten.map { |a| Values.num(a) }.compact
      end

      def today
        Date.respond_to?(:current) ? Date.current : Date.today
      end

      def round_with(mode, n, digits)
        n = Values.num(n)
        return nil if n.nil?

        d = digits.nil? ? 0 : Values.num(digits).to_i
        BigDecimal(n.round(d, mode)) # round(0 / negative) returns an Integer
      end
    end

    define('IF', 2, 3) { |*| nil } # evaluated lazily by the Evaluator
    define('AND', 1, Float::INFINITY) { |*a| a.flatten.all? { |x| Values.truthy?(x) } }
    define('OR', 1, Float::INFINITY) { |*a| a.flatten.any? { |x| Values.truthy?(x) } }
    define('NOT', 1) { |a| !Values.truthy?(a) }
    define('ISBLANK', 1) { |a| Values.blank?(a) }
    define('COALESCE', 1, Float::INFINITY) { |*a| a.find { |x| !Values.blank?(x) } }

    define('ABS', 1) { |a| Values.num(a)&.abs }
    define('ROUND', 1, 2) { |n, d = nil| round_with(:half_up, n, d) }
    define('ROUNDUP', 1, 2) { |n, d = nil| round_with(:up, n, d) }
    define('ROUNDDOWN', 1, 2) { |n, d = nil| round_with(:down, n, d) }
    define('CEIL', 1) { |n| (x = Values.num(n)) && BigDecimal(x.ceil) }
    define('FLOOR', 1) { |n| (x = Values.num(n)) && BigDecimal(x.floor) }
    define('SQRT', 1) do |n|
      x = Values.num(n)
      x.nil? || x.negative? ? nil : x.sqrt(20)
    end
    define('SUM', 1, Float::INFINITY) { |*a| numbers(a).sum(BigDecimal(0)) }
    define('MIN', 1, Float::INFINITY) { |*a| numbers(a).min }
    define('MAX', 1, Float::INFINITY) { |*a| numbers(a).max }
    define('AVG', 1, Float::INFINITY) do |*a|
      n = numbers(a)
      n.empty? ? nil : n.sum(BigDecimal(0)).div(n.size, 20)
    end

    define('TODAY', 0) { today }
    define('DATE', 3) do |y, m, d|
      parts = [y, m, d].map { |x| Values.num(x) }
      next nil if parts.any?(&:nil?)

      begin
        Date.new(*parts.map(&:to_i))
      rescue ArgumentError
        nil
      end
    end
    define('DAYS', 2) do |e, s|
      e = Values.to_date(e)
      s = Values.to_date(s)
      e && s ? BigDecimal((e - s).to_i) : nil
    end
    define('YEAR', 1) { |d| (x = Values.to_date(d)) && BigDecimal(x.year) }
    define('MONTH', 1) { |d| (x = Values.to_date(d)) && BigDecimal(x.month) }
    define('DAY', 1) { |d| (x = Values.to_date(d)) && BigDecimal(x.day) }

    define('CONCAT', 1, Float::INFINITY) { |*a| a.map { |x| Values.text(x) }.join }
    define('UPPER', 1) { |s| Values.text(s).upcase }
    define('LOWER', 1) { |s| Values.text(s).downcase }
    define('TRIM', 1) { |s| Values.text(s).strip }
    define('LEN', 1) { |s| BigDecimal(Values.text(s).length) }
  end
end
