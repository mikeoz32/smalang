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

  alias AstNode = ModuleNode | FunctionNode | ParameterNode | ReturnNode | BinaryExpr | CallExpr | IdentifierExpr | IntegerLiteralExpr

  abstract class AstVisitor
    abstract def visit(node : ModuleNode) : Nil
    abstract def visit(node : FunctionNode) : Nil
    abstract def visit(node : ParameterNode) : Nil
    abstract def visit(node : ReturnNode) : Nil
    abstract def visit(node : BinaryExpr) : Nil
    abstract def visit(node : CallExpr) : Nil
    abstract def visit(node : IdentifierExpr) : Nil
    abstract def visit(node : IntegerLiteralExpr) : Nil
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

  class ParseError < Exception
    getter source_file : SourceFile
    getter token : Token
    getter description : String

    def initialize(@source_file : SourceFile, @token : Token, @description : String)
      position = source_file.position_at(token.span.start)
      super("#{source_file.name}:#{position.line}:#{position.column}: #{description}")
    end
  end

  class Parser
    PRECEDENCE = 1

    def initialize(@tokens : TokenStream)
      @cursor = 0
    end

    def parse : ParsedModule
      arena = AstArena.new(@tokens.source_file.source.bytesize)
      function_ids = Array(NodeId).new

      until current_token.kind == TokenKind::Eof
        function_ids << parse_function(arena)
      end

      function_range = arena.append_children(function_ids)
      module_span = SourceSpan.new(0, @tokens.source_file.source.bytesize)
      root_id = arena.add(ModuleNode.new(module_span, function_range))
      ParsedModule.new(@tokens.source_file, arena, root_id)
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

      body = parse_return(arena)
      dedent = expect(TokenKind::Dedent, "expected the end of the function body")
      function_span = SourceSpan.new(start, dedent.span.start - start)
      arena.add(FunctionNode.new(function_span, name, return_type, parameters, body))
    end

    private def parse_parameters(arena : AstArena) : NodeRange
      parameter_ids = Array(NodeId).new
      return arena.append_children(parameter_ids) if current_token.kind == TokenKind::RightParen

      loop do
        name = expect(TokenKind::Identifier, "expected a parameter name").span
        expect(TokenKind::Colon, "expected ':' after the parameter name")
        type = parse_type
        span = SourceSpan.new(name.start, previous_token.span.end_offset - name.start)
        parameter_ids << arena.add(ParameterNode.new(span, name, type))

        break unless current_token.kind == TokenKind::Comma
        advance
      end

      arena.append_children(parameter_ids)
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
      newline = expect(TokenKind::Newline, "expected a newline after the return statement")
      span = SourceSpan.new(start, newline.span.start - start)
      arena.add(ReturnNode.new(span, value))
    end

    private def parse_expression(arena : AstArena, minimum_precedence : Int32 = PRECEDENCE) : NodeId
      left = parse_primary(arena)

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
        advance
        expression = parse_expression(arena)
        expect(TokenKind::RightParen, "expected ')' after the expression")
        expression
      else
        fail("expected an expression")
      end
    end

    private def parse_call(arena : AstArena, callee : SourceSpan) : NodeId
      expect(TokenKind::LeftParen, "expected '(' after the function name")
      argument_ids = Array(NodeId).new

      unless current_token.kind == TokenKind::RightParen
        loop do
          argument_ids << parse_expression(arena)
          break unless current_token.kind == TokenKind::Comma
          advance
        end
      end

      arguments = arena.append_children(argument_ids)
      close_paren = expect(TokenKind::RightParen, "expected ')' after the argument list")
      span = SourceSpan.new(callee.start, close_paren.span.end_offset - callee.start)
      arena.add(CallExpr.new(span, callee, arguments))
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
      fail("#{description}, found #{current_token.kind}")
    end

    private def fail(description : String) : NoReturn
      raise ParseError.new(@tokens.source_file, current_token, description)
    end
  end
end
