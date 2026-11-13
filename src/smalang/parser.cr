module Smalang
  alias NodeId = Int32
  alias AstTypeId = Int32

  struct AstName
    getter span : SourceSpan
    getter synthetic_text : String?

    def initialize(@span : SourceSpan)
      @synthetic_text = nil
    end

    def initialize(@span : SourceSpan, @synthetic_text : String)
    end

    def text(source_file : SourceFile) : String
      @synthetic_text || source_file.slice(@span)
    end

    def generated? : Bool
      !@synthetic_text.nil?
    end
  end

  class SourceFile
    def slice(name : AstName) : String
      name.text(self)
    end
  end

  enum AstType : UInt8
    Int
    UInt
    Bool
    Int8
    UInt8
    Int16
    UInt16
    Int32
    UInt32
    Int64
    UInt64
  end

  abstract class AstTypeSyntax
    getter span : SourceSpan

    def initialize(@span : SourceSpan)
    end
  end

  class ScalarTypeSyntax < AstTypeSyntax
    getter type : AstType

    def initialize(span : SourceSpan, @type : AstType)
      super(span)
    end
  end

  class ArrayTypeSyntax < AstTypeSyntax
    getter element_type_id : AstTypeId
    getter length : UInt128

    def initialize(span : SourceSpan, @element_type_id : AstTypeId, @length : UInt128)
      super(span)
    end
  end

  class PointerTypeSyntax < AstTypeSyntax
    getter pointee_type_id : AstTypeId

    def initialize(span : SourceSpan, @pointee_type_id : AstTypeId)
      super(span)
    end
  end

  class AstTypeArena
    @types : Array(AstTypeSyntax)

    def initialize(source_size : Int32)
      capacity = source_size // 16
      capacity = 1 if capacity < 1
      @types = Array(AstTypeSyntax).new(capacity)
    end

    def add(type : AstTypeSyntax) : AstTypeId
      @types << type
      @types.size - 1
    end

    def type(id : AstTypeId) : AstTypeSyntax
      @types[id]
    end

    def size : Int32
      @types.size
    end
  end

  enum BindingMutability : UInt8
    Immutable
    Mutable
  end

  enum BinaryOperator : UInt8
    Add
    Subtract
    Multiply
  end

  enum IntegerComparisonOperator : UInt8
    Equal
    NotEqual
    LessThan
    LessThanOrEqual
    GreaterThan
    GreaterThanOrEqual
  end

  enum RuntimeExceptionKind : UInt8
    DivisionByZero
    IndexOutOfBounds
    OutOfMemory
    InvalidArgument
  end

  abstract class SourceMatchPatternVisitor
    abstract def visit(pattern : BooleanMatchPatternNode) : Nil
    abstract def visit(pattern : WildcardMatchPatternNode) : Nil
  end

  abstract class SourceMatchPatternNode
    getter span : SourceSpan

    def initialize(@span : SourceSpan)
    end

    abstract def accept(visitor : SourceMatchPatternVisitor) : Nil
    abstract def accept(visitor : AstVisitor) : Nil
  end

  class BooleanMatchPatternNode < SourceMatchPatternNode
    getter value : Bool

    def initialize(span : SourceSpan, @value : Bool)
      super(span)
    end

    def accept(visitor : SourceMatchPatternVisitor) : Nil
      visitor.visit(self)
    end

    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  class WildcardMatchPatternNode < SourceMatchPatternNode
    def accept(visitor : SourceMatchPatternVisitor) : Nil
      visitor.visit(self)
    end

    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
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
    getter name : AstName
    getter return_type : AstTypeId
    getter parameters : NodeRange
    getter statements : NodeRange
    getter body : NodeId

    def initialize(@span : SourceSpan, name : SourceSpan, @return_type : AstTypeId, @parameters : NodeRange, @statements : NodeRange, @body : NodeId)
      @name = AstName.new(name)
    end

    def initialize(@span : SourceSpan, @name : AstName, @return_type : AstTypeId, @parameters : NodeRange, @statements : NodeRange, @body : NodeId)
    end
  end

  struct ParameterNode
    getter span : SourceSpan
    getter name : AstName
    getter type : AstTypeId
    getter mutability : BindingMutability

    def initialize(@span : SourceSpan, name : SourceSpan, @type : AstTypeId, @mutability : BindingMutability)
      @name = AstName.new(name)
    end

    def initialize(@span : SourceSpan, @name : AstName, @type : AstTypeId, @mutability : BindingMutability)
    end
  end

  struct VariableDeclarationNode
    getter span : SourceSpan
    getter name : AstName
    getter type : AstTypeId
    getter mutability : BindingMutability
    getter initializer : NodeId

    def initialize(@span : SourceSpan, name : SourceSpan, @type : AstTypeId, @mutability : BindingMutability, @initializer : NodeId)
      @name = AstName.new(name)
    end

    def initialize(@span : SourceSpan, @name : AstName, @type : AstTypeId, @mutability : BindingMutability, @initializer : NodeId)
    end
  end

  struct AssignmentNode
    getter span : SourceSpan
    getter target : NodeId
    getter value : NodeId

    def initialize(@span : SourceSpan, @target : NodeId, @value : NodeId)
    end
  end

  struct ReturnNode
    getter span : SourceSpan
    getter value : NodeId

    def initialize(@span : SourceSpan, @value : NodeId)
    end
  end

  struct UnsafeBlockNode
    getter span : SourceSpan
    getter statements : NodeRange

    def initialize(@span : SourceSpan, @statements : NodeRange)
    end
  end

  struct CallStatementNode
    getter span : SourceSpan
    getter call : NodeId

    def initialize(@span : SourceSpan, @call : NodeId)
    end
  end

  struct AllocateExpr
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct StackAllocateExpr
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct PointerOffsetExpr
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct LoadExpr
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct StoreExpr
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct FreeExpr
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct StoreStatementNode
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct FreeStatementNode
    getter span : SourceSpan
    getter arguments : NodeRange

    def initialize(@span : SourceSpan, @arguments : NodeRange)
    end
  end

  struct MatchCaseNode
    getter span : SourceSpan
    getter pattern : NodeId
    getter result : NodeId

    def initialize(@span : SourceSpan, @pattern : NodeId, @result : NodeId)
    end
  end

  struct MatchExpressionNode
    getter span : SourceSpan
    getter scrutinee : NodeId
    getter cases : NodeRange

    def initialize(@span : SourceSpan, @scrutinee : NodeId, @cases : NodeRange)
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

  struct ArrayLiteralExpr
    getter span : SourceSpan
    getter elements : NodeRange

    def initialize(@span : SourceSpan, @elements : NodeRange)
    end
  end

  struct IndexExpr
    getter span : SourceSpan
    getter array : NodeId
    getter index : NodeId

    def initialize(@span : SourceSpan, @array : NodeId, @index : NodeId)
    end
  end

  struct CallExpr
    getter span : SourceSpan
    getter callee : AstName
    getter arguments : NodeRange
    getter type_argument : AstTypeId?

    def initialize(@span : SourceSpan, callee : SourceSpan, @arguments : NodeRange, @type_argument : AstTypeId? = nil)
      @callee = AstName.new(callee)
    end

    def initialize(@span : SourceSpan, @callee : AstName, @arguments : NodeRange, @type_argument : AstTypeId? = nil)
    end
  end

  struct IdentifierExpr
    getter span : SourceSpan
    getter name : AstName

    def initialize(@span : SourceSpan)
      @name = AstName.new(@span)
    end

    def initialize(@span : SourceSpan, @name : AstName)
    end
  end

  struct IntegerLiteralExpr
    getter span : SourceSpan
    getter synthetic_value : Int128?

    def initialize(@span : SourceSpan)
      @synthetic_value = nil
    end

    def initialize(@span : SourceSpan, @synthetic_value : Int128)
    end
  end

  struct BooleanLiteralExpr
    getter span : SourceSpan
    getter value : Bool

    def initialize(@span : SourceSpan, @value : Bool)
    end
  end

  struct TypeOperandExpr
    getter span : SourceSpan
    getter type_id : AstTypeId

    def initialize(@span : SourceSpan, @type_id : AstTypeId)
    end
  end

  struct SequenceExpr
    getter span : SourceSpan
    getter statements : NodeRange
    getter value : NodeId

    def initialize(@span : SourceSpan, @statements : NodeRange, @value : NodeId)
    end
  end

  struct IntegerCompareExpr
    getter span : SourceSpan
    getter operator : IntegerComparisonOperator
    getter left : NodeId
    getter right : NodeId

    def initialize(@span : SourceSpan, @operator : IntegerComparisonOperator, @left : NodeId, @right : NodeId)
    end
  end

  struct RuntimeGuardStatementNode
    getter span : SourceSpan
    getter condition : NodeId
    getter exception_kind : RuntimeExceptionKind

    def initialize(@span : SourceSpan, @condition : NodeId, @exception_kind : RuntimeExceptionKind)
    end
  end

  struct UnsafeExpr
    getter span : SourceSpan
    getter value : NodeId

    def initialize(@span : SourceSpan, @value : NodeId)
    end
  end

  struct ErrorNode
    getter span : SourceSpan
    getter recovered_node : NodeId?

    def initialize(@span : SourceSpan, @recovered_node : NodeId? = nil)
    end
  end

  alias AstNode = ModuleNode | FunctionNode | ParameterNode | VariableDeclarationNode | AssignmentNode | ReturnNode | UnsafeBlockNode | CallStatementNode | AllocateExpr | StackAllocateExpr | PointerOffsetExpr | LoadExpr | StoreExpr | FreeExpr | StoreStatementNode | FreeStatementNode | MatchExpressionNode | MatchCaseNode | SourceMatchPatternNode | BinaryExpr | ArrayLiteralExpr | IndexExpr | CallExpr | IdentifierExpr | IntegerLiteralExpr | BooleanLiteralExpr | TypeOperandExpr | SequenceExpr | IntegerCompareExpr | RuntimeGuardStatementNode | UnsafeExpr | ErrorNode

  abstract class AstVisitor
    abstract def visit(node : ModuleNode) : Nil
    abstract def visit(node : FunctionNode) : Nil
    abstract def visit(node : ParameterNode) : Nil
    abstract def visit(node : VariableDeclarationNode) : Nil
    abstract def visit(node : AssignmentNode) : Nil
    abstract def visit(node : ReturnNode) : Nil
    abstract def visit(node : UnsafeBlockNode) : Nil
    abstract def visit(node : CallStatementNode) : Nil
    abstract def visit(node : AllocateExpr) : Nil
    abstract def visit(node : StackAllocateExpr) : Nil
    abstract def visit(node : PointerOffsetExpr) : Nil
    abstract def visit(node : LoadExpr) : Nil
    abstract def visit(node : StoreExpr) : Nil
    abstract def visit(node : FreeExpr) : Nil
    abstract def visit(node : StoreStatementNode) : Nil
    abstract def visit(node : FreeStatementNode) : Nil
    abstract def visit(node : MatchExpressionNode) : Nil
    abstract def visit(node : MatchCaseNode) : Nil
    abstract def visit(node : BooleanMatchPatternNode) : Nil
    abstract def visit(node : WildcardMatchPatternNode) : Nil
    abstract def visit(node : BinaryExpr) : Nil
    abstract def visit(node : ArrayLiteralExpr) : Nil
    abstract def visit(node : IndexExpr) : Nil
    abstract def visit(node : CallExpr) : Nil
    abstract def visit(node : IdentifierExpr) : Nil
    abstract def visit(node : IntegerLiteralExpr) : Nil

    def visit(node : TypeOperandExpr) : Nil
    end

    def visit(node : SequenceExpr) : Nil
    end

    def visit(node : IntegerCompareExpr) : Nil
    end

    def visit(node : RuntimeGuardStatementNode) : Nil
    end

    def visit(node : UnsafeExpr) : Nil
    end

    abstract def visit(node : BooleanLiteralExpr) : Nil
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

  struct VariableDeclarationNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct AssignmentNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct ReturnNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct UnsafeBlockNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct CallStatementNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct AllocateExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct StackAllocateExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct PointerOffsetExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct LoadExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct StoreExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct FreeExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct StoreStatementNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct FreeStatementNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct MatchExpressionNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct MatchCaseNode
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

  struct ArrayLiteralExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct IndexExpr
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

  struct BooleanLiteralExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct TypeOperandExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct SequenceExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct IntegerCompareExpr
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct RuntimeGuardStatementNode
    def accept(visitor : AstVisitor) : Nil
      visitor.visit(self)
    end
  end

  struct UnsafeExpr
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
    getter type_arena : AstTypeArena
    getter root_id : NodeId

    def initialize(@source_file : SourceFile, @arena : AstArena, @type_arena : AstTypeArena, @root_id : NodeId)
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

    @type_arena : AstTypeArena?

    def initialize(@tokens : TokenStream)
      @cursor = 0
      @indent_depth = 0
      @diagnostics = Array(ParseDiagnostic).new
      @type_arena = nil
    end

    def parse : ParseResult
      @cursor = 0
      @indent_depth = 0
      @diagnostics.clear
      arena = AstArena.new(@tokens.source_file.source.bytesize)
      type_arena = AstTypeArena.new(@tokens.source_file.source.bytesize)
      @type_arena = type_arena
      function_ids = Array(NodeId).new

      until current_token.kind == TokenKind::Eof
        start = current_token.span.start
        if top_level_function_start?
          begin
            function_ids << parse_function(arena, type_arena)
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
      parsed_module = ParsedModule.new(@tokens.source_file, arena, type_arena, root_id)
      ParseResult.new(parsed_module, @diagnostics)
    end

    private def parse_function(arena : AstArena, type_arena : AstTypeArena) : NodeId
      start = expect(TokenKind::Def, "expected a function definition").span.start
      name = expect(TokenKind::Identifier, "expected a function name").span
      expect(TokenKind::LeftParen, "expected '(' after the function name")
      parameters = parse_parameters(arena, type_arena)
      expect(TokenKind::RightParen, "expected ')' after the parameter list")
      expect(TokenKind::Arrow, "expected '->' before the return type")
      return_type = parse_type(type_arena)
      expect(TokenKind::Colon, "expected ':' after the function signature")
      expect(TokenKind::Newline, "expected a newline after the function signature")
      expect(TokenKind::Indent, "expected an indented function body")

      statements, body = parse_function_body(arena, type_arena)
      function_end = current_token.span.start
      if current_token.kind == TokenKind::Dedent
        function_end = advance.span.start
      end
      function_span = span_between(start, function_end)
      arena.add(FunctionNode.new(function_span, name, return_type, parameters, statements, body))
    end

    private def parse_parameters(arena : AstArena, type_arena : AstTypeArena) : NodeRange
      parse_delimited_list(arena, "parameter") { parse_parameter(arena, type_arena) }
    end

    private def parse_parameter(arena : AstArena, type_arena : AstTypeArena) : NodeId
      name = expect(TokenKind::Identifier, "expected a parameter name").span
      expect(TokenKind::Colon, "expected ':' after the parameter name")
      type, mutability = parse_binding_type(type_arena)
      span = SourceSpan.new(name.start, previous_token.span.end_offset - name.start)
      arena.add(ParameterNode.new(span, name, type, mutability))
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

    private def parse_type(type_arena : AstTypeArena) : AstTypeId
      if current_token.kind == TokenKind::Identifier
        case @tokens.source_file.slice(current_token.span)
        when "array"
          start = advance.span.start
          expect(TokenKind::LeftBracket, "expected '[' after 'array'")
          element_type_id = parse_type(type_arena)
          expect(TokenKind::Comma, "expected ',' before the array length")
          length_token = expect(TokenKind::IntegerLiteral, "expected a nonnegative integer array length")
          length = @tokens.source_file.slice(length_token.span).to_u128?
          unless length
            fail("array length is too large")
          end
          finish = expect(TokenKind::RightBracket, "expected ']' after the array type").span.end_offset
          return type_arena.add(ArrayTypeSyntax.new(span_between(start, finish), element_type_id, length))
        when "ptr"
          start = advance.span.start
          expect(TokenKind::LeftBracket, "expected '[' after 'ptr'")
          pointee_type_id = parse_type(type_arena)
          finish = expect(TokenKind::RightBracket, "expected ']' after the pointer type").span.end_offset
          return type_arena.add(PointerTypeSyntax.new(span_between(start, finish), pointee_type_id))
        end
      end

      case current_token.kind
      when TokenKind::IntType
        add_scalar_type(type_arena, AstType::Int)
      when TokenKind::UIntType
        add_scalar_type(type_arena, AstType::UInt)
      when TokenKind::BoolType
        add_scalar_type(type_arena, AstType::Bool)
      when TokenKind::Int8Type
        add_scalar_type(type_arena, AstType::Int8)
      when TokenKind::UInt8Type
        add_scalar_type(type_arena, AstType::UInt8)
      when TokenKind::Int16Type
        add_scalar_type(type_arena, AstType::Int16)
      when TokenKind::UInt16Type
        add_scalar_type(type_arena, AstType::UInt16)
      when TokenKind::Int32Type
        add_scalar_type(type_arena, AstType::Int32)
      when TokenKind::UInt32Type
        add_scalar_type(type_arena, AstType::UInt32)
      when TokenKind::Int64Type
        add_scalar_type(type_arena, AstType::Int64)
      when TokenKind::UInt64Type
        add_scalar_type(type_arena, AstType::UInt64)
      else
        fail("expected a type")
      end
    end

    private def add_scalar_type(type_arena : AstTypeArena, type : AstType) : AstTypeId
      token = advance
      type_arena.add(ScalarTypeSyntax.new(token.span, type))
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

    private def parse_function_body(arena : AstArena, type_arena : AstTypeArena) : Tuple(NodeRange, NodeId)
      statements = Array(NodeId).new
      diagnostic_count = @diagnostics.size
      until function_body_terminator?
        if current_token.kind == TokenKind::Newline
          advance
          next
        end

        cursor_before = @cursor
        begin
          if current_token.kind == TokenKind::Return
            return_node = parse_return(arena)
            unless function_body_terminator?
              diagnostic = report("return must be the final function statement")
              finish = synchronize_function_end
              error = arena.add(ErrorNode.new(span_between(diagnostic.span.start, finish), return_node))
              return {arena.append_children(statements), error}
            end
            return {arena.append_children(statements), return_node}
          end

          statements << if current_token.kind == TokenKind::Unsafe
            parse_unsafe_block(arena, type_arena)
          else
            parse_binding_statement(arena, type_arena)
          end
        rescue failure : ParseFailure
          @diagnostics << failure.diagnostic
          if @indent_depth > 1
            finish = synchronize_function_end
            error = arena.add(ErrorNode.new(span_between(failure.diagnostic.span.start, finish)))
            return {arena.append_children(statements), error}
          end
          synchronize_statement
          finish = previous_token.span.end_offset
          error_span = span_between(failure.diagnostic.span.start, finish)
          statements << arena.add(ErrorNode.new(error_span))
        end
        advance if @cursor == cursor_before && !function_body_terminator?
      end

      finish = synchronize_function_end
      if @diagnostics.size > diagnostic_count
        diagnostic = @diagnostics[diagnostic_count]
        return {arena.append_children(statements), arena.add(ErrorNode.new(span_between(diagnostic.span.start, finish)))}
      end

      diagnostic = report("expected a final return statement")
      {arena.append_children(statements), arena.add(ErrorNode.new(span_between(diagnostic.span.start, finish)))}
    end

    private def parse_unsafe_block(arena : AstArena, type_arena : AstTypeArena) : NodeId
      start = expect(TokenKind::Unsafe, "expected 'unsafe'").span.start
      expect(TokenKind::Colon, "expected ':' after 'unsafe'")
      expect(TokenKind::Newline, "expected a newline after 'unsafe:'")
      expect(TokenKind::Indent, "expected an indented unsafe block")
      statements = Array(NodeId).new

      until unsafe_block_terminator?
        if current_token.kind == TokenKind::Newline
          advance
          next
        end

        if current_token.kind == TokenKind::Return
          fail("return cannot appear inside an unsafe block")
        end
        if current_token.kind == TokenKind::Unsafe
          fail("nested unsafe blocks are not supported")
        end

        cursor_before = @cursor
        begin
          statements << parse_binding_statement(arena, type_arena)
        rescue failure : ParseFailure
          @diagnostics << failure.diagnostic
          synchronize_statement
          finish = previous_token.span.end_offset
          statements << arena.add(ErrorNode.new(span_between(failure.diagnostic.span.start, finish)))
        end
        advance if @cursor == cursor_before && !unsafe_block_terminator?
      end

      if statements.empty?
        fail("unsafe block cannot be empty")
      end

      finish = expect(TokenKind::Dedent, "expected the end of the unsafe block").span.start
      arena.add(UnsafeBlockNode.new(span_between(start, finish), arena.append_children(statements)))
    end

    private def unsafe_block_terminator? : Bool
      (current_token.kind == TokenKind::Dedent && @indent_depth == 2) ||
        current_token.kind == TokenKind::Eof || top_level_function_start?
    end

    private def parse_binding_statement(arena : AstArena, type_arena : AstTypeArena) : NodeId
      name = expect(TokenKind::Identifier, "expected a local declaration, assignment, or return").span
      case current_token.kind
      when TokenKind::Colon
        parse_variable_declaration(arena, type_arena, name)
      when TokenKind::Assign
        target = arena.add(IdentifierExpr.new(name))
        parse_assignment(arena, target)
      when TokenKind::LeftBracket
        target = arena.add(IdentifierExpr.new(name))
        target = parse_postfix(arena, target)
        expect(TokenKind::Assign, "expected '=' after the assignment target")
        parse_assignment_value(arena, target)
      when TokenKind::LeftParen
        case @tokens.source_file.slice(name)
        when "store"
          parse_store_statement(arena, name)
        when "free"
          parse_free_statement(arena, name)
        else
          call_id = parse_call(arena, name)
          finish = finish_simple_statement
          arena.add(CallStatementNode.new(span_between(name.start, finish), call_id))
        end
      else
        fail("expected ':' or '=' after the binding name")
      end
    end

    private def parse_variable_declaration(arena : AstArena, type_arena : AstTypeArena, name : SourceSpan) : NodeId
      expect(TokenKind::Colon, "expected ':' after the binding name")
      type, mutability = parse_binding_type(type_arena)
      expect(TokenKind::Assign, "expected '=' before the binding initializer")
      initializer = parse_expression(arena)
      finish = finish_simple_statement
      arena.add(VariableDeclarationNode.new(span_between(name.start, finish), name, type, mutability, initializer))
    end

    private def parse_assignment(arena : AstArena, target : NodeId) : NodeId
      expect(TokenKind::Assign, "expected '=' after the assignment target")
      parse_assignment_value(arena, target)
    end

    private def parse_assignment_value(arena : AstArena, target : NodeId) : NodeId
      value = parse_expression(arena)
      finish = finish_simple_statement
      target_span = arena.node(target).span
      arena.add(AssignmentNode.new(span_between(target_span.start, finish), target, value))
    end

    private def finish_simple_statement : Int32
      if current_token.kind == TokenKind::Newline
        advance.span.start
      elsif current_token.kind == TokenKind::Dedent || current_token.kind == TokenKind::Eof || top_level_function_start?
        current_token.span.start
      else
        fail("expected a newline after the statement")
      end
    end

    private def function_body_terminator? : Bool
      current_token.kind == TokenKind::Dedent || current_token.kind == TokenKind::Eof || top_level_function_start?
    end

    private def parse_binding_type(type_arena : AstTypeArena) : Tuple(AstTypeId, BindingMutability)
      case current_token.kind
      when TokenKind::Mut
        advance
        expect(TokenKind::LeftBracket, "expected '[' after 'mut'")
        type = parse_type(type_arena)
        expect(TokenKind::RightBracket, "expected ']' after the mutable binding type")
        {type, BindingMutability::Mutable}
      when TokenKind::Const
        advance
        expect(TokenKind::LeftBracket, "expected '[' after 'const'")
        type = parse_type(type_arena)
        expect(TokenKind::RightBracket, "expected ']' after the constant binding type")
        {type, BindingMutability::Immutable}
      else
        {parse_type(type_arena), BindingMutability::Immutable}
      end
    end

    private def parse_expression(arena : AstArena, minimum_precedence : Int32 = PRECEDENCE, allow_type_names : Bool = false) : NodeId
      left = begin
        parse_postfix(arena, parse_primary(arena, allow_type_names), allow_type_names)
      rescue failure : ParseFailure
        raise failure if @indent_depth > 1
        @diagnostics << failure.diagnostic
        synchronize_expression
        arena.add(ErrorNode.new(failure.diagnostic.span))
      end

      while operator = current_binary_operator
        break if PRECEDENCE < minimum_precedence

        advance
        right = parse_expression(arena, PRECEDENCE + 1, allow_type_names)
        left_span = arena.node(left).span
        right_span = arena.node(right).span
        span = SourceSpan.new(left_span.start, right_span.end_offset - left_span.start)
        left = arena.add(BinaryExpr.new(span, operator, left, right))
      end

      left
    end

    private def parse_primary(arena : AstArena, allow_type_names : Bool = false) : NodeId
      case current_token.kind
      when TokenKind::IntegerLiteral
        token = advance
        arena.add(IntegerLiteralExpr.new(token.span))
      when TokenKind::TrueLiteral
        token = advance
        arena.add(BooleanLiteralExpr.new(token.span, true))
      when TokenKind::FalseLiteral
        token = advance
        arena.add(BooleanLiteralExpr.new(token.span, false))
      when TokenKind::LeftBracket
        parse_array_literal(arena)
      when TokenKind::Match
        parse_match_expression(arena)
      when TokenKind::Identifier
        name = current_token.span
        if allow_type_names && @tokens.source_file.slice(name) == "array"
          type_id = parse_type(@type_arena.not_nil!)
          type = @type_arena.not_nil!.type(type_id)
          arena.add(TypeOperandExpr.new(type.span, type_id))
        else
          advance
          if @tokens.source_file.slice(name) == "cast" && generic_type_call_follows?
            parse_cast_call(arena, name)
          elsif current_token.kind == TokenKind::LeftParen
            parse_call(arena, name)
          else
            arena.add(IdentifierExpr.new(name))
          end
        end
      when TokenKind::IntType, TokenKind::UIntType, TokenKind::BoolType, TokenKind::Int8Type, TokenKind::UInt8Type, TokenKind::Int16Type, TokenKind::UInt16Type, TokenKind::Int32Type, TokenKind::UInt32Type, TokenKind::Int64Type, TokenKind::UInt64Type
        fail("expected an expression, found #{current_token.kind}") unless allow_type_names
        arena.add(IdentifierExpr.new(advance.span))
      when TokenKind::LeftParen
        open_paren = advance
        expression = parse_expression(arena, allow_type_names: allow_type_names)
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

    private def parse_cast_call(arena : AstArena, callee : SourceSpan) : NodeId
      expect(TokenKind::LeftBracket, "expected '[' after 'cast'")
      target_type = parse_type(@type_arena.not_nil!)
      expect(TokenKind::RightBracket, "expected ']' after cast target type")
      arguments, call_span, closed = parse_call_arguments(arena, callee)
      call_id = arena.add(CallExpr.new(call_span, callee, arguments, target_type))
      closed ? call_id : arena.add(ErrorNode.new(call_span, call_id))
    end

    private def generic_type_call_follows? : Bool
      return false unless current_token.kind == TokenKind::LeftBracket

      depth = 0
      index = @cursor
      while index < @tokens.tokens.size
        case @tokens.tokens[index].kind
        when TokenKind::LeftBracket
          depth += 1
        when TokenKind::RightBracket
          depth -= 1
          if depth == 0
            next_index = index + 1
            return next_index < @tokens.tokens.size && @tokens.tokens[next_index].kind == TokenKind::LeftParen
          end
        when TokenKind::Eof
          return false
        end
        index += 1
      end

      false
    end

    private def parse_array_literal(arena : AstArena) : NodeId
      start = expect(TokenKind::LeftBracket, "expected '['").span.start
      element_ids = Array(NodeId).new
      unless current_token.kind == TokenKind::RightBracket
        loop do
          element_ids << parse_expression(arena)
          break unless current_token.kind == TokenKind::Comma

          comma = advance
          if current_token.kind == TokenKind::RightBracket
            fail("trailing commas are not supported")
          end
        end
      end

      finish = expect(TokenKind::RightBracket, "expected ']' after the array literal").span.end_offset
      elements = arena.append_children(element_ids)
      arena.add(ArrayLiteralExpr.new(span_between(start, finish), elements))
    end

    private def parse_postfix(arena : AstArena, expression_id : NodeId, allow_type_names : Bool = false) : NodeId
      current = expression_id
      while current_token.kind == TokenKind::LeftBracket
        advance
        index_id = parse_expression(arena, allow_type_names: allow_type_names)
        finish = expect(TokenKind::RightBracket, "expected ']' after the index").span.end_offset
        expression_span = arena.node(current).span
        current = arena.add(IndexExpr.new(span_between(expression_span.start, finish), current, index_id))
      end
      current
    end

    private def parse_match_expression(arena : AstArena) : NodeId
      start = expect(TokenKind::Match, "expected 'match'").span.start
      scrutinee = parse_expression(arena)
      expect(TokenKind::Colon, "expected ':' after the match value")
      expect(TokenKind::Newline, "expected a newline after the match header")
      expect(TokenKind::Indent, "expected an indented match body")

      case_ids = Array(NodeId).new
      while current_token.kind == TokenKind::Case
        case_ids << parse_match_case(arena)
      end
      fail("expected a case clause in the match body") if case_ids.empty?

      end_offset = arena.node(case_ids.last).span.end_offset
      expect(TokenKind::Dedent, "expected the end of the match body")
      cases = arena.append_children(case_ids)
      arena.add(MatchExpressionNode.new(span_between(start, end_offset), scrutinee, cases))
    end

    private def parse_match_case(arena : AstArena) : NodeId
      start = expect(TokenKind::Case, "expected 'case'").span.start
      pattern_token = current_token
      pattern = case pattern_token.kind
                when TokenKind::TrueLiteral
                  advance
                  arena.add(BooleanMatchPatternNode.new(pattern_token.span, true))
                when TokenKind::FalseLiteral
                  advance
                  arena.add(BooleanMatchPatternNode.new(pattern_token.span, false))
                when TokenKind::Identifier
                  if @tokens.source_file.slice(pattern_token.span) == "_"
                    advance
                    arena.add(WildcardMatchPatternNode.new(pattern_token.span))
                  else
                    fail("expected 'True', 'False', or '_' as a case pattern")
                  end
                else
                  fail("expected 'True', 'False', or '_' as a case pattern")
                end

      expect(TokenKind::Colon, "expected ':' after the case pattern")
      result = parse_expression(arena)
      result_span = arena.node(result).span
      if current_token.kind == TokenKind::Newline
        advance
      elsif !nested_expression_ended_case_line?(result_span)
        fail("expected a newline after the case result")
      end
      arena.add(MatchCaseNode.new(span_between(start, result_span.end_offset), pattern, result))
    end

    private def nested_expression_ended_case_line?(result_span : SourceSpan) : Bool
      return false unless current_token.kind == TokenKind::Case || current_token.kind == TokenKind::Dedent

      result_line = @tokens.source_file.position_at(result_span.end_offset).line
      next_token_line = @tokens.source_file.position_at(current_token.span.start).line
      next_token_line > result_line
    end

    private def parse_call(arena : AstArena, callee : SourceSpan) : NodeId
      name = @tokens.source_file.slice(callee)
      allow_type_names = name == "size_of" || name == "align_of"
      arguments, call_span, closed = parse_call_arguments(arena, callee, allow_type_names)
      expression_id = case @tokens.source_file.slice(callee)
                      when "alloc"
                        arena.add(AllocateExpr.new(call_span, arguments))
                      when "alloc_stack"
                        arena.add(StackAllocateExpr.new(call_span, arguments))
                      when "offset"
                        arena.add(PointerOffsetExpr.new(call_span, arguments))
                      when "load"
                        arena.add(LoadExpr.new(call_span, arguments))
                      when "store"
                        arena.add(StoreExpr.new(call_span, arguments))
                      when "free"
                        arena.add(FreeExpr.new(call_span, arguments))
                      else
                        arena.add(CallExpr.new(call_span, callee, arguments))
                      end
      closed ? expression_id : arena.add(ErrorNode.new(call_span, expression_id))
    end

    private def parse_store_statement(arena : AstArena, callee : SourceSpan) : NodeId
      arguments, _, closed = parse_call_arguments(arena, callee)
      finish = finish_simple_statement
      span = span_between(callee.start, finish)
      statement_id = arena.add(StoreStatementNode.new(span, arguments))
      closed ? statement_id : arena.add(ErrorNode.new(span, statement_id))
    end

    private def parse_free_statement(arena : AstArena, callee : SourceSpan) : NodeId
      arguments, _, closed = parse_call_arguments(arena, callee)
      finish = finish_simple_statement
      span = span_between(callee.start, finish)
      statement_id = arena.add(FreeStatementNode.new(span, arguments))
      closed ? statement_id : arena.add(ErrorNode.new(span, statement_id))
    end

    private def parse_call_arguments(arena : AstArena, callee : SourceSpan, allow_type_names : Bool = false) : Tuple(NodeRange, SourceSpan, Bool)
      expect(TokenKind::LeftParen, "expected '(' after the function name")
      arguments = parse_delimited_list(arena, "argument") { parse_expression(arena, allow_type_names: allow_type_names) }
      close_paren = if current_token.kind == TokenKind::RightParen
                      advance
                    else
                      report_missing("expected ')' after the argument list, found #{current_token.kind}")
                      synchronize_parenthesized
                      advance if current_token.kind == TokenKind::RightParen
                    end

      finish = close_paren.try(&.span.end_offset) || previous_token.span.end_offset
      finish = callee.end_offset if finish < callee.end_offset
      {arguments, span_between(callee.start, finish), !close_paren.nil?}
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
      until current_token.kind == TokenKind::Eof ||
            (current_token.kind == TokenKind::Dedent && @indent_depth == 1) ||
            top_level_function_start?
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
      case token.kind
      when TokenKind::Indent
        @indent_depth += 1
      when TokenKind::Dedent
        @indent_depth -= 1 if @indent_depth > 0
      end
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
