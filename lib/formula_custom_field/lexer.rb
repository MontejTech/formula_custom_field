# frozen_string_literal: true

require 'bigdecimal'
require 'strscan'

module FormulaCustomField
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
end
