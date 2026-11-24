# frozen_string_literal: true

# Standalone test of the formula engine (no Redmine needed):
#   ruby -Ilib test/engine_test.rb
require 'minitest/autorun'
require 'formula_custom_field/engine'

class EngineTest < Minitest::Test
  F = FormulaCustomField

  def calc(src, fields = {})
    F.evaluate(src) { |kind, key| fields[key] }
  end

  def test_arithmetic_precedence_and_exactness
    assert_equal BigDecimal('7'), calc('1 + 2 * 3')
    assert_equal BigDecimal('9'), calc('(1 + 2) * 3')
    assert_equal BigDecimal('0.3'), calc('0.1 + 0.2')
    assert_equal BigDecimal('-4'), calc('-2 ^ 2')
    assert_equal BigDecimal('512'), calc('2 ^ 3 ^ 2')
  end

  def test_division_by_zero_and_blank_propagate_to_nil
    assert_nil calc('1 / 0')
    assert_nil calc('{#1} + 1', 1 => nil)
  end

  def test_margin_example
    f = { 1 => 100.0, 2 => 20 }
    assert_equal BigDecimal('12'), calc('ROUND(({#1} + {#2}) * 10 / 100, 2)', f)
  end

  def test_round_modes
    assert_equal BigDecimal('3'), calc('ROUND(2.5)')
    assert_equal BigDecimal('2.35'), calc('ROUND(2.345, 2)')
    assert_equal BigDecimal('-3'), calc('ROUND(-2.5)')
    assert_equal BigDecimal('2.35'), calc('ROUNDUP(2.341, 2)')
    assert_equal BigDecimal('2.34'), calc('ROUNDDOWN(2.349, 2)')
  end

  def test_if_is_lazy_and_comparisons
    assert_equal BigDecimal('1'), calc('IF({#1} > 5, 1, 2)', 1 => 9)
    assert_equal BigDecimal('2'), calc('IF({#1} > 5, 1, 2)', 1 => nil)
    assert_equal true, calc('"abc" = "ABC"')
    assert_equal true, calc('1 <> 2')
  end

  def test_text_and_functions
    assert_equal 'Qty: 12.5', calc('"Qty: " & {#2}', 2 => 12.5)
    assert_equal BigDecimal('6'), calc('SUM(1, 2, 3)')
    assert_equal BigDecimal('2'), calc('AVG(1, 3)')
    assert_equal 'B', calc('COALESCE({#1}, "B")', 1 => '')
  end

  def test_dates
    assert_equal Date.new(2026, 1, 11), calc('{#3} + 10', 3 => Date.new(2026, 1, 1))
    assert_equal BigDecimal('9'), calc('DAYS({#4}, {#3})', 4 => Date.new(2026, 1, 10), 3 => Date.new(2026, 1, 1))
    assert_equal BigDecimal('9'), calc('{#4} - {#3}', 4 => Date.new(2026, 1, 10), 3 => Date.new(2026, 1, 1))
  end

  def test_references_are_collected
    ast = F::Parser.parse('{#1} + {#12} * {@estimated_hours}')
    assert_equal [[:ref, :id, 1], [:ref, :id, 12], [:ref, :attr, 'estimated_hours']], F::Parser.references(ast)
  end

  def test_parse_errors
    ['', '1 +', '(1', 'FOO(1)', 'ROUND()', 'abc', '1 $ 2', '{}', '{Some Name}', '{#}', '"open'].each do |src|
      assert_raises(F::ParseError, src) { F::Parser.parse(src) }
    end
  end

  def test_no_ruby_code_execution
    assert_raises(F::ParseError) { F::Parser.parse('`ls`') }
    assert_raises(F::ParseError) { F::Parser.parse('system("ls")') }
    assert_raises(F::ParseError) { F::Parser.parse('File.read("/etc/passwd")') }
  end

  def test_runaway_input_is_rejected
    assert_raises(F::ParseError) { F::Parser.parse('(' * 100 + '1' + ')' * 100) }
    assert_raises(F::ParseError) { F::Parser.parse('1+' * 2000 + '1') }
  end

  def test_type_errors
    assert_raises(F::EvaluationError) { calc('{#1} * 2', 1 => 'abc') }
    assert_raises(F::EvaluationError) { calc('1 < "a"') }
  end

  # One example per function – the same ones are documented in the README.
  FUNCTION_EXAMPLES = [
    ['IF(5 > 3, "yes", "no")', 'yes'],
    ['AND(1 < 2, 2 < 3)', true],
    ['OR(1 > 2, 2 < 3)', true],
    ['NOT(1 > 2)', true],
    ['ISBLANK({#1})', true],
    ['COALESCE({#1}, 10)', 10],
    ['ABS(-4.5)', 4.5],
    ['ROUND(2.567, 2)', 2.57],
    ['ROUNDUP(2.561, 2)', 2.57],
    ['ROUNDDOWN(2.569, 2)', 2.56],
    ['CEIL(2.1)', 3],
    ['FLOOR(2.9)', 2],
    ['SQRT(16)', 4],
    ['SUM(1, 2, 3.5)', 6.5],
    ['MIN(4, 2, 9)', 2],
    ['MAX(4, 2, 9)', 9],
    ['AVG(2, 4, 9)', 5],
    ['DATE(2026, 3, 15)', Date.new(2026, 3, 15)],
    ['DAYS(DATE(2026, 3, 15), DATE(2026, 3, 1))', 14],
    ['YEAR(DATE(2026, 3, 15))', 2026],
    ['MONTH(DATE(2026, 3, 15))', 3],
    ['DAY(DATE(2026, 3, 15))', 15],
    ['CONCAT("Order-", 42)', 'Order-42'],
    ['UPPER("abc")', 'ABC'],
    ['LOWER("ABC")', 'abc'],
    ['TRIM("  hi  ")', 'hi'],
    ['LEN("hello")', 5]
  ].freeze

  def test_every_function_example
    FUNCTION_EXAMPLES.each do |src, expected|
      expected = BigDecimal(expected.to_s) if expected.is_a?(Numeric)
      assert_equal expected, calc(src, 1 => nil), src
    end
    assert_kind_of Date, calc('TODAY()')
  end

  def test_all_registered_functions_have_an_example
    documented = FUNCTION_EXAMPLES.map { |src, _| src[/\A[A-Z]+/] } + %w[TODAY]
    inner = FUNCTION_EXAMPLES.flat_map { |src, _| src.scan(/[A-Z]+(?=\()/) }
    assert_empty F::Functions.names - (documented + inner).uniq
  end
end
