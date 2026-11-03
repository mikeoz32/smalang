module Smalang
  alias NodeId = Int32

  enum AstType : UInt8
    Int
    UInt
  end

  enum BinaryOperator : UInt8
    Add
    Subtract
  end

  struct NodeRange
    getter start : Int32
    getter count : Int32

    def initialize(@start : Int32, @count : Int32)
    end
  end

  struct ModuleNode
    getter span : SourceSpan
    getter functions : NodeRange

    def initialize(@span : SourceSpan, @functions : NodeRange)
    end
  end

  struct FunctionNode
    getter span : SourceSpan
    getter name : SourceSpan
    getter return_type : AstType
    getter parameters : NodeRange
    getter body : NodeId

    def initialize(@span : SourceSpan, @name : SourceSpan, @return_type : AstType, @parameters : NodeRange, @body : NodeId)
    end
  end

  struct ParameterNode
    getter span : SourceSpan
    getter name : SourceSpan
    getter type : AstType

    def initialize(@span : SourceSpan, @name : SourceSpan, @type : AstType)
    end
  end

  struct ReturnNode
    getter span : SourceSpan
    getter value : NodeId

    def initialize(@span : SourceSpan, @value : NodeId)
    end
  end

  struct BinaryExpr
    getter span : SourceSpan
    getter operator : BinaryOperator
    getter left : NodeId
    getter right : NodeId

    def initialize(@span : SourceSpan, @operator : BinaryOperator, @left : NodeId, @right : NodeId)
    end
  end

  struct CallExpr
    getter span : SourceSpan
    getter callee : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @callee : SourceSpan, @arguments : NodeRange)
    end
  end

  struct IdentifierExpr
    getter span : SourceSpan

    def initialize(@span : SourceSpan)
    end
  end

  struct IntegerLiteralExpr
    getter span : SourceSpan

    def initialize(@span : SourceSpan)
    end
  end

  struct ErrorNode
    getter span : SourceSpan
    getter recovered_node : NodeId?

    def initialize(@span : SourceSpan, @recovered_node : NodeId? = nil)
    end
  end

  alias AstNode = ModuleNode | FunctionNode | ParameterNode | ReturnNode | BinaryExpr | CallExpr | IdentifierExpr | IntegerLiteralExpr | ErrorNode

  abstract class AstVisitor
    abstract def visit(node : ModuleNode) : Nil
    abstract def visit(node : FunctionNode) : Nil
    abstract def visit(node : ParameterNode) : Nil
    abstract def visit(node : ReturnNode) : Nil
    abstract def visit(node : BinaryExpr) : Nil
    abstract def visit(node : CallExpr) : Nil
    abstract def visit(node : IdentifierExpr) : Nil
    abstract def visit(node : IntegerLiteralExpr) : Nil
    abstract def visit(node : ErrorNode) : Nil
  end

  struct ModuleNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct FunctionNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct ParameterNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct ReturnNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct BinaryExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct CallExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct IdentifierExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct IntegerLiteralExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct ErrorNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  class AstArena
    def initialize(source_size : Int32)
      node_capacity = source_size // 4
      node_capacity = 1 if node_capacity < 1
      child_capacity = source_size // 8
      child_capacity = 1 if child_capacity < 1
      @nodes = Array(AstNode).new(node_capacity)
      @children = Array(NodeId).new(child_capacity)
    end

    def add(node : AstNode) : NodeId
      @nodes << node
      @nodes.size - 1
    end

    def node(id : NodeId) : AstNode
      @nodes[id]
    end

    def size : Int32
      @nodes.size
    end

    def append_children(ids : Array(NodeId)) : NodeRange
      start = @children.size
      @children.concat(ids)
      range_from(start)
    end

    private def range_from(start : Int32) : NodeRange
      NodeRange.new(start, @children.size - start)
    end

    def child(range : NodeRange, index : Int32) : NodeId
      @children[range.start + index]
    end
  end

  class ParsedModule
    getter source_file : SourceFile
    getter arena : AstArena
    getter root_id : NodeId

    def initialize(@source_file : SourceFile, @arena : AstArena, @root_id : NodeId)
    end
  end

  class ParseDiagnostic
    getter source_file : SourceFile
    getter span : SourceSpan
    getter description : String

    def initialize(@source_file : SourceFile, @span : SourceSpan, @description : String)
    end

    def message : String
      position = @source_file.position_at(@span.start)
      "#{@source_file.name}:#{position.line}:#{position.column}: #{@description}"
    end
  end

  class ParseFailure < Exception
    getter diagnostic : ParseDiagnostic

    def initialize(@diagnostic : ParseDiagnostic)
      super(diagnostic.message)
    end
  end

  class ParseResult
    getter parsed_module : ParsedModule
    getter diagnostics : Array(ParseDiagnostic)

    def initialize(@parsed_module : ParsedModule, @diagnostics : Array(ParseDiagnostic))
    end

    def success? : Bool
      @diagnostics.empty?
    end
  end

  class Parser
    PRECEDENCE = 1

    def initialize(@tokens : TokenStream)
      @cursor = 0
      @diagnostics = Array(ParseDiagnostic).new
    end

    def parse : ParseResult
      @cursor = 0
      @diagnostics.clear
      arena = AstArena.new(@tokens.source_file.source.bytesize)
      function_ids = Array(NodeId).new

      until current_token.kind == TokenKind::Eof
        start = current_token.span.start
        if top_level_function_start?
          begin
            function_ids << parse_function(arena)
          rescue failure : ParseFailure
            @diagnostics << failure.diagnostic
            finish = synchronize_top_level(start)
            function_ids << arena.add(ErrorNode.new(span_between(start, finish)))
          end
        else
          report("expected a function definition, found #{current_token.kind}")
          finish = synchronize_top_level(start)
          function_ids << arena.add(ErrorNode.new(span_between(start, finish)))
        end
      end

      function_range = arena.append_children(function_ids)
      module_span = SourceSpan.new(0, @tokens.source_file.source.bytesize)
      root_id = arena.add(ModuleNode.new(module_span, function_range))
      parsed_module = ParsedModule.new(@tokens.source_file, arena, root_id)
      ParseResult.new(parsed_module, @diagnostics)
    end

    private def parse_function(arena : AstArena) : NodeId
      start = expect(TokenKind::Def, "expected a function definition").span.start
      name = expect(TokenKind::Identifier, "expected a function name").span
      expect(TokenKind::LeftParen, "expected '(' after the function name")
      parameters = parse_parameters(arena)
      expect(TokenKind::RightParen, "expected ')' after the parameter list")
      expect(TokenKind::Arrow, "expected '->' before the return type")
      return_type = parse_type
      expect(TokenKind::Colon, "expected ':' after the function signature")
      expect(TokenKind::Newline, "expected a newline after the function signature")
      expect(TokenKind::Indent, "expected an indented function body")

      body = parse_function_body(arena)
      function_end = current_token.span.start
      if current_token.kind == TokenKind::Dedent
        function_end = advance.span.start
      end
      function_span = span_between(start, function_end)
      arena.add(FunctionNode.new(function_span, name, return_type, parameters, body))
    end

    private def parse_parameters(arena : AstArena) : NodeRange
      parse_delimited_list(arena, "parameter") { parse_parameter(arena) }
    end

    private def parse_parameter(arena : AstArena) : NodeId
      name = expect(TokenKind::Identifier, "expected a parameter name").span
      expect(TokenKind::Colon, "expected ':' after the parameter name")
      type = parse_type
      span = SourceSpan.new(name.start, previous_token.span.end_offset - name.start)
      arena.add(ParameterNode.new(span, name, type))
    end

    private def parse_delimited_list(arena : AstArena, item_name : String, &parse_item : -> NodeId) : NodeRange
      item_ids = Array(NodeId).new
      return arena.append_children(item_ids) if current_token.kind == TokenKind::RightParen

      loop do
        break if list_terminator?

        cursor_before = @cursor
        begin
          item_ids << yield
        rescue failure : ParseFailure
          @diagnostics << failure.diagnostic
          item_ids << arena.add(ErrorNode.new(failure.diagnostic.span))
          synchronize_list
        end

        if current_token.kind == TokenKind::Comma
          comma = advance
          if current_token.kind == TokenKind::RightParen
            diagnostic = report("trailing commas are not supported", comma)
            item_ids << arena.add(ErrorNode.new(diagnostic.span))
            break
          end
          next
        end

        break if current_token.kind == TokenKind::RightParen || list_terminator?

        diagnostic = report("expected ',' or ')' after a #{item_name}")
        item_ids << arena.add(ErrorNode.new(diagnostic.span))
        synchronize_list
        if current_token.kind == TokenKind::Comma
          comma = advance
          if current_token.kind == TokenKind::RightParen
            diagnostic = report("trailing commas are not supported", comma)
            item_ids << arena.add(ErrorNode.new(diagnostic.span))
            break
          end
        else
          break
        end

        advance if @cursor == cursor_before
      end

      arena.append_children(item_ids)
    end

    private def parse_type : AstType
      case current_token.kind
      when TokenKind::IntType
        advance
        AstType::Int
      when TokenKind::UIntType
        advance
        AstType::UInt
      else
        fail("expected 'int' or 'uint' as a type")
      end
    end

    private def parse_return(arena : AstArena) : NodeId
      start = expect(TokenKind::Return, "expected 'return'").span.start
      value = parse_expression(arena)
      if current_token.kind != TokenKind::Newline && current_token.kind != TokenKind::Dedent && current_token.kind != TokenKind::Eof
        diagnostic = report("expected a newline after the return statement")
        expression_span = arena.node(value).span
        synchronize_statement
        end_offset = previous_token.span.end_offset
        end_offset = diagnostic.span.end_offset if end_offset < diagnostic.span.end_offset
        value = arena.add(ErrorNode.new(span_between(expression_span.start, end_offset), value))
      end

      end_offset = current_token.span.start
      end_offset = advance.span.start if current_token.kind == TokenKind::Newline
      end_offset = previous_token.span.end_offset if end_offset < start
      span = span_between(start, end_offset)
      arena.add(ReturnNode.new(span, value))
    end

    private def parse_function_body(arena : AstArena) : NodeId
      body = begin
        parse_return(arena)
      rescue failure : ParseFailure
        @diagnostics << failure.diagnostic
        finish = synchronize_function_end
        finish = failure.diagnostic.span.end_offset if finish < failure.diagnostic.span.end_offset
        error_span = span_between(failure.diagnostic.span.start, finish)
        return arena.add(ErrorNode.new(error_span))
      end

      return body if current_token.kind == TokenKind::Dedent || current_token.kind == TokenKind::Eof || top_level_function_start?

      diagnostic = report("expected the end of the function body")
      finish = synchronize_function_end
      error_span = span_between(diagnostic.span.start, finish)
      arena.add(ErrorNode.new(error_span, body))
    end

    private def parse_expression(arena : AstArena, minimum_precedence : Int32 = PRECEDENCE) : NodeId
      left = begin
        parse_primary(arena)
      rescue failure : ParseFailure
        @diagnostics << failure.diagnostic
        synchronize_expression
        arena.add(ErrorNode.new(failure.diagnostic.span))
      end

      while operator = current_binary_operator
        break if PRECEDENCE < minimum_precedence

        advance
        right = parse_expression(arena, PRECEDENCE + 1)
        left_span = arena.node(left).span
        right_span = arena.node(right).span
        span = SourceSpan.new(left_span.start, right_span.end_offset - left_span.start)
        left = arena.add(BinaryExpr.new(span, operator, left, right))
      end

      left
    end

    private def parse_primary(arena : AstArena) : NodeId
      case current_token.kind
      when TokenKind::IntegerLiteral
        token = advance
        arena.add(IntegerLiteralExpr.new(token.span))
      when TokenKind::Identifier
        name = advance.span
        if current_token.kind == TokenKind::LeftParen
          parse_call(arena, name)
        else
          arena.add(IdentifierExpr.new(name))
        end
      when TokenKind::LeftParen
        open_paren = advance
        expression = parse_expression(arena)
        if current_token.kind == TokenKind::RightParen
          advance
          expression
        else
          report_missing("expected ')' after the expression, found #{current_token.kind}")
          synchronize_parenthesized
          finish = if current_token.kind == TokenKind::RightParen
                     advance.span.end_offset
                   else
                     previous_token.span.end_offset
                   end
          finish = arena.node(expression).span.end_offset if finish < open_paren.span.end_offset
          error = ErrorNode.new(span_between(open_paren.span.start, finish), expression)
          arena.add(error)
        end
      else
        fail("expected an expression")
      end
    end

    private def parse_call(arena : AstArena, callee : SourceSpan) : NodeId
      expect(TokenKind::LeftParen, "expected '(' after the function name")
      arguments = parse_delimited_list(arena, "argument") { parse_expression(arena) }
      close_paren = if current_token.kind == TokenKind::RightParen
                      advance
                    else
                      report_missing("expected ')' after the argument list, found #{current_token.kind}")
                      synchronize_parenthesized
                      advance if current_token.kind == TokenKind::RightParen
                    end

      finish = close_paren.try(&.span.end_offset) || previous_token.span.end_offset
      finish = callee.end_offset if finish < callee.end_offset
      call_span = span_between(callee.start, finish)
      call_id = arena.add(CallExpr.new(call_span, callee, arguments))
      if close_paren
        call_id
      else
        arena.add(ErrorNode.new(call_span, call_id))
      end
    end

    private def synchronize_expression : Nil
      until expression_terminator?
        advance
      end
    end

    private def synchronize_list : Nil
      until list_terminator? || current_token.kind == TokenKind::Comma || current_token.kind == TokenKind::RightParen
        advance
      end
    end

    private def synchronize_parenthesized : Nil
      until current_token.kind == TokenKind::RightParen || statement_terminator? || current_token.kind == TokenKind::Comma
        advance
      end
    end

    private def synchronize_statement : Nil
      until statement_terminator?
        advance
      end
    end

    private def synchronize_function_end : Int32
      start = current_token.span.start
      cursor_before = @cursor
      until current_token.kind == TokenKind::Dedent || current_token.kind == TokenKind::Eof || top_level_function_start?
        advance
      end

      @cursor == cursor_before ? start : previous_token.span.end_offset
    end

    private def synchronize_top_level(start : Int32) : Int32
      until current_token.kind == TokenKind::Eof
        if top_level_function_start? && current_token.span.start > start
          return current_token.span.start
        end
        advance
      end

      current_token.span.start
    end

    private def expression_terminator? : Bool
      case current_token.kind
      when TokenKind::Plus, TokenKind::Minus, TokenKind::Comma, TokenKind::RightParen,
           TokenKind::Newline, TokenKind::Dedent, TokenKind::Eof
        true
      else
        top_level_function_start?
      end
    end

    private def list_terminator? : Bool
      case current_token.kind
      when TokenKind::Newline, TokenKind::Indent, TokenKind::Dedent, TokenKind::Eof
        true
      else
        top_level_function_start?
      end
    end

    private def statement_terminator? : Bool
      current_token.kind == TokenKind::Newline || current_token.kind == TokenKind::Dedent || current_token.kind == TokenKind::Eof || top_level_function_start?
    end

    private def top_level_function_start? : Bool
      current_token.kind == TokenKind::Def && @tokens.source_file.position_at(current_token.span.start).column == 1
    end

    private def report(description : String, token : Token = current_token) : ParseDiagnostic
      report(description, token.span)
    end

    private def report_missing(description : String) : ParseDiagnostic
      span = SourceSpan.new(current_token.span.start, 0)
      report(description, span)
    end

    private def report(description : String, span : SourceSpan) : ParseDiagnostic
      diagnostic = ParseDiagnostic.new(@tokens.source_file, span, description)
      @diagnostics << diagnostic
      diagnostic
    end

    private def span_between(start : Int32, finish : Int32) : SourceSpan
      SourceSpan.new(start, {finish - start, 0}.max)
    end

    private def current_binary_operator : BinaryOperator?
      case current_token.kind
      when TokenKind::Plus
        BinaryOperator::Add
      when TokenKind::Minus
        BinaryOperator::Subtract
      else
        nil
      end
    end

    private def current_token : Token
      @tokens.tokens[@cursor]
    end

    private def previous_token : Token
      @tokens.tokens[@cursor - 1]
    end

    private def advance : Token
      token = current_token
      @cursor += 1
      token
    end

    private def expect(kind : TokenKind, description : String) : Token
      return advance if current_token.kind == kind
      fail(description)
    end

    private def fail(description : String) : NoReturn
      token = current_token
      span = if missing_token_boundary?(token.kind)
               SourceSpan.new(token.span.start, 0)
             else
               token.span
             end
      raise ParseFailure.new(ParseDiagnostic.new(@tokens.source_file, span, "#{description}, found #{token.kind}"))
    end

    private def missing_token_boundary?(kind : TokenKind) : Bool
      case kind
      when TokenKind::Comma, TokenKind::RightParen, TokenKind::Newline,
           TokenKind::Indent, TokenKind::Dedent, TokenKind::Eof
        true
      else
        false
      end
    end
  end
end
