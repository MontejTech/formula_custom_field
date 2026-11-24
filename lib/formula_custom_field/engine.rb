# frozen_string_literal: true

# Pure-Ruby formula engine (lexer, parser, evaluator, functions).
# It has NO dependency on Redmine/Rails, so it can be unit-tested standalone:
#   ruby -Ilib test/engine_test.rb
#
# Formulas are never passed to Ruby's eval – they are parsed into a small AST and
# interpreted, so a formula can only do arithmetic / text / date work.
require 'bigdecimal'
require 'bigdecimal/util'
require 'date'
require 'strscan'

module FormulaCustomField
  class FormulaError < StandardError; end
  class ParseError < FormulaError; end
  class EvaluationError < FormulaError; end

  # ------------------------------------------------------------------ values
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

  # --------------------------------------------------------------- functions
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

  # ------------------------------------------------------------------- lexer
  class Lexer
    Token = Struct.new(:type, :value, :pos)

    def initialize(source)
      @s = StringScanner.new(source)
    end

    def tokens
      out = []
      until @s.eos?
        next if @s.skip(/\s+/)

        pos = @s.pos
        if (t = @s.scan(/\d+(?:\.\d+)?/))
          out << Token.new(:num, BigDecimal(t), pos)
        elsif @s.scan(/"((?:[^"]|"")*)"/)
          out << Token.new(:str, @s[1].gsub('""', '"'), pos)
        elsif @s.scan(/'((?:[^']|'')*)'/)
          out << Token.new(:str, @s[1].gsub("''", "'"), pos)
        elsif @s.scan(/\{([^{}]*)\}/)
          ref = @s[1].strip
          raise ParseError, "Empty field reference at position #{pos + 1}" if ref.empty?

          out << Token.new(:ref, ref, pos)
        elsif (t = @s.scan(/[A-Za-z_][A-Za-z0-9_]*/))
          out << Token.new(:ident, t, pos)
        elsif (t = @s.scan(/<>|!=|<=|>=|==|[=<>+\-*\/%^&]/))
          out << Token.new(:op, t, pos)
        elsif @s.scan(/\(/)
          out << Token.new(:lparen, '(', pos)
        elsif @s.scan(/\)/)
          out << Token.new(:rparen, ')', pos)
        elsif @s.scan(/,/)
          out << Token.new(:comma, ',', pos)
        else
          raise ParseError, "Unexpected character '#{@s.getch}' at position #{pos + 1}"
        end
      end
      out << Token.new(:eof, nil, @s.pos)
    end
  end

  # ------------------------------------------------------------------ parser
  # AST nodes:
  #   [:num, BigDecimal] [:str, String] [:bool, true/false] [:nil]
  #   [:ref, kind, key]  kind = :id | :attr
  #   [:neg, node] [:bin, op, l, r] [:call, NAME, [args]]
  class Parser
    MAX_LENGTH = 2000
    MAX_DEPTH = 40
    COMPARISON = %w[= == <> != < <= > >=].freeze

    def self.parse(source)
      source = source.to_s
      raise ParseError, 'Formula is empty' if source.strip.empty?
      raise ParseError, "Formula is too long (max #{MAX_LENGTH} characters)" if source.length > MAX_LENGTH

      new(Lexer.new(source).tokens).parse
    end

    # every [:ref, kind, key] used in the AST
    def self.references(node, acc = [])
      return acc unless node.is_a?(Array)

      case node[0]
      when :ref then acc << node
      when :neg then references(node[1], acc)
      when :bin
        references(node[2], acc)
        references(node[3], acc)
      when :call then node[2].each { |a| references(a, acc) }
      end
      acc
    end

    def initialize(tokens)
      @t = tokens
      @i = 0
      @depth = 0
    end

    def parse
      node = comparison
      raise ParseError, "Unexpected '#{peek.value}' at position #{peek.pos + 1}" unless peek.type == :eof

      node
    end

    private

    def peek
      @t[@i]
    end

    def advance
      tok = @t[@i]
      @i += 1
      tok
    end

    def op?(*ops)
      peek.type == :op && ops.include?(peek.value)
    end

    def nested
      @depth += 1
      raise ParseError, 'Formula is nested too deeply' if @depth > MAX_DEPTH

      yield
    ensure
      @depth -= 1
    end

    def binary_level(ops, lower)
      left = send(lower)
      while op?(*ops)
        op = advance.value
        op = '=' if op == '=='
        op = '<>' if op == '!='
        left = [:bin, op, left, send(lower)]
      end
      left
    end

    def comparison; binary_level(COMPARISON, :concat); end
    def concat;     binary_level(%w[&], :additive);    end
    def additive;   binary_level(%w[+ -], :term);      end
    def term;       binary_level(%w[* / %], :unary);   end

    def unary
      nested do
        if op?('-')
          advance
          [:neg, unary]
        elsif op?('+')
          advance
          unary
        else
          power
        end
      end
    end

    def power
      base = primary
      return base unless op?('^')

      advance
      [:bin, '^', base, unary]
    end

    def primary
      tok = advance
      case tok.type
      when :num then [:num, tok.value]
      when :str then [:str, tok.value]
      when :ref then reference(tok.value)
      when :lparen
        node = nested { comparison }
        expect(:rparen, "Missing ')'")
        node
      when :ident then identifier(tok)
      when :eof then raise ParseError, 'Formula ends unexpectedly'
      else raise ParseError, "Unexpected '#{tok.value}' at position #{tok.pos + 1}"
      end
    end

    def reference(text)
      if text.start_with?('#') && text[1..-1] =~ /\A\d+\z/
        [:ref, :id, text[1..-1].to_i]
      elsif text.start_with?('@')
        name = text[1..-1].strip
        raise ParseError, "Invalid attribute reference {#{text}}" if name.empty?

        [:ref, :attr, name]
      else
        raise ParseError, "Invalid reference {#{text}}: write {#id} for a custom field or {@attribute} for a built-in attribute"
      end
    end

    def identifier(tok)
      name = tok.value.upcase
      if peek.type == :lparen
        advance
        args = []
        nested do
          if peek.type != :rparen
            loop do
              args << comparison
              break unless peek.type == :comma

              advance
            end
          end
        end
        expect(:rparen, "Missing ')' after arguments of #{name}")
        raise ParseError, "Unknown function #{name}" unless Functions.known?(name)

        Functions.check_arity!(name, args.size)
        [:call, name, args]
      else
        case name
        when 'TRUE' then [:bool, true]
        when 'FALSE' then [:bool, false]
        when 'BLANK', 'NULL' then [:nil]
        else raise ParseError, "Unknown name '#{tok.value}' at position #{tok.pos + 1} (custom fields are referenced as {#id})"
        end
      end
    end

    def expect(type, message)
      raise ParseError, message unless peek.type == type

      advance
    end
  end

  # --------------------------------------------------------------- evaluator
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

  # convenience for tests / console
  def self.evaluate(source, &resolver)
    Evaluator.new(&resolver).evaluate(Parser.parse(source))
  end
end
