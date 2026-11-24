# frozen_string_literal: true

module FormulaCustomField
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
end
