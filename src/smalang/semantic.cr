require "./lexer"
require "./parser"

module Smalang
  alias SymbolId = Int32
  alias TypeId = Int32

  struct IntegerTypeInfo
    getter name : String
    getter bit_width : Int32
    getter signed : Bool

    def initialize(@name : String, @bit_width : Int32, @signed : Bool)
    end

    def fits_nonnegative_literal?(value : UInt128) : Bool
      value_bits = @bit_width - (@signed ? 1 : 0)
      value <= (1_u128 << value_bits) - 1
    end
  end

  class SemanticTypeTable
    POINTER_WIDTH = 64

    getter int_type_id : TypeId
    getter uint_type_id : TypeId
    getter bool_type_id : TypeId

    @types : Array(IntegerTypeInfo)
    @type_ids_by_ast_type : Hash(AstType, TypeId)

    def initialize
      @types = [] of IntegerTypeInfo
      @type_ids_by_ast_type = {} of AstType => TypeId
      register_type(AstType::Int, IntegerTypeInfo.new("int", POINTER_WIDTH, true))
      register_type(AstType::UInt, IntegerTypeInfo.new("uint", POINTER_WIDTH, false))
      register_type(AstType::Bool, IntegerTypeInfo.new("bool", 0, false))
      register_type(AstType::Int8, IntegerTypeInfo.new("int8", 8, true))
      register_type(AstType::UInt8, IntegerTypeInfo.new("uint8", 8, false))
      register_type(AstType::Int16, IntegerTypeInfo.new("int16", 16, true))
      register_type(AstType::UInt16, IntegerTypeInfo.new("uint16", 16, false))
      register_type(AstType::Int32, IntegerTypeInfo.new("int32", 32, true))
      register_type(AstType::UInt32, IntegerTypeInfo.new("uint32", 32, false))
      register_type(AstType::Int64, IntegerTypeInfo.new("int64", 64, true))
      register_type(AstType::UInt64, IntegerTypeInfo.new("uint64", 64, false))
      @int_type_id = @type_ids_by_ast_type[AstType::Int]
      @uint_type_id = @type_ids_by_ast_type[AstType::UInt]
      @bool_type_id = @type_ids_by_ast_type[AstType::Bool]
    end

    def id_for(source_type : AstType) : TypeId
      @type_ids_by_ast_type[source_type]
    end

    def label(type_id : TypeId) : String
      @types[type_id].name
    end

    def fits_nonnegative_literal?(type_id : TypeId, value : UInt128) : Bool
      @types[type_id].fits_nonnegative_literal?(value)
    end

    def supports_integer_arithmetic?(type_id : TypeId) : Bool
      @types[type_id].bit_width > 0
    end

    private def register_type(ast_type : AstType, type_info : IntegerTypeInfo) : Nil
      @type_ids_by_ast_type[ast_type] = @types.size
      @types << type_info
    end
  end

  abstract class SemanticSymbol
    getter id : SymbolId
    getter declaration_id : NodeId
    getter name_span : SourceSpan

    def initialize(@id : SymbolId, @declaration_id : NodeId, @name_span : SourceSpan)
    end
  end

  class SemanticFunctionSymbol < SemanticSymbol
    getter result_type_id : TypeId

    @parameter_type_ids : Array(TypeId)

    def initialize(id : SymbolId, declaration_id : NodeId, name_span : SourceSpan, parameter_type_ids : Array(TypeId), @result_type_id : TypeId)
      super(id, declaration_id, name_span)
      @parameter_type_ids = parameter_type_ids.dup
    end

    def parameter_count : Int32
      @parameter_type_ids.size
    end

    def parameter_type(index : Int32) : TypeId?
      @parameter_type_ids[index]?
    end
  end

  class SemanticParameterSymbol < SemanticSymbol
    getter type_id : TypeId

    def initialize(id : SymbolId, declaration_id : NodeId, name_span : SourceSpan, @type_id : TypeId)
      super(id, declaration_id, name_span)
    end
  end

  class ModuleFunctionScope
    @symbols_by_name : Hash(String, SemanticFunctionSymbol)

    def initialize
      @symbols_by_name = Hash(String, SemanticFunctionSymbol).new
    end

    def declare(name : String, symbol : SemanticFunctionSymbol) : Bool
      return false if @symbols_by_name.has_key?(name)
      @symbols_by_name[name] = symbol
      true
    end

    def resolve(name : String) : SemanticFunctionSymbol?
      @symbols_by_name[name]?
    end
  end

  class FunctionParameterScope
    @symbols_by_name : Hash(String, SemanticParameterSymbol)

    def initialize
      @symbols_by_name = Hash(String, SemanticParameterSymbol).new
    end

    def declare(name : String, symbol : SemanticParameterSymbol) : Bool
      return false if @symbols_by_name.has_key?(name)
      @symbols_by_name[name] = symbol
      true
    end

    def resolve(name : String) : SemanticParameterSymbol?
      @symbols_by_name[name]?
    end
  end

  class SemanticModule
    getter parsed_module : ParsedModule
    getter type_table : SemanticTypeTable

    @node_types : Array(TypeId?)
    @node_symbols : Array(SymbolId?)
    @symbols : Array(SemanticSymbol)

    def initialize(@parsed_module : ParsedModule, @type_table : SemanticTypeTable, node_types : Array(TypeId?), node_symbols : Array(SymbolId?), symbols : Array(SemanticSymbol))
      @node_types = node_types.dup
      @node_symbols = node_symbols.dup
      @symbols = symbols.dup
    end

    def type_of(node_id : NodeId) : TypeId?
      @node_types[node_id]?
    end

    def symbol_for(node_id : NodeId) : SymbolId?
      @node_symbols[node_id]?
    end

    def symbol(id : SymbolId) : SemanticSymbol
      @symbols[id]
    end
  end

  class SemanticDiagnostic
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

  class SemanticResult
    getter semantic_module : SemanticModule?
    getter diagnostic : SemanticDiagnostic?

    def initialize(@semantic_module : SemanticModule?, @diagnostic : SemanticDiagnostic?)
    end

    def success? : Bool
      !@semantic_module.nil? && @diagnostic.nil?
    end
  end

  class SemanticContext
    getter parsed_module : ParsedModule
    getter arena : AstArena
    getter type_table : SemanticTypeTable
    getter module_scope : ModuleFunctionScope
    getter diagnostic : SemanticDiagnostic?

    @node_types : Array(TypeId?)
    @node_symbols : Array(SymbolId?)
    @symbols : Array(SemanticSymbol)
    @functions_by_declaration : Hash(NodeId, SemanticFunctionSymbol)

    def initialize(@parsed_module : ParsedModule)
      @arena = parsed_module.arena
      @type_table = SemanticTypeTable.new
      @module_scope = ModuleFunctionScope.new
      @node_types = Array(TypeId?).new(@arena.size) { nil }
      @node_symbols = Array(SymbolId?).new(@arena.size) { nil }
      @symbols = Array(SemanticSymbol).new
      @functions_by_declaration = Hash(NodeId, SemanticFunctionSymbol).new
      @diagnostic = nil
    end

    def add_function(declaration_id : NodeId, declaration : FunctionNode) : SemanticFunctionSymbol?
      name = @parsed_module.source_file.slice(declaration.name)
      if @module_scope.resolve(name)
        report(declaration.name, "duplicate function '#{name}'")
        return nil
      end

      parameter_types = parameter_type_ids(declaration.parameters)
      return nil if @diagnostic

      symbol = SemanticFunctionSymbol.new(
        @symbols.size,
        declaration_id,
        declaration.name,
        parameter_types,
        @type_table.id_for(declaration.return_type)
      )
      @module_scope.declare(name, symbol)
      @symbols << symbol
      @functions_by_declaration[declaration_id] = symbol
      @node_symbols[declaration_id] = symbol.id
      symbol
    end

    def add_parameter(declaration_id : NodeId, declaration : ParameterNode) : SemanticParameterSymbol
      symbol = SemanticParameterSymbol.new(
        @symbols.size,
        declaration_id,
        declaration.name,
        @type_table.id_for(declaration.type)
      )
      @symbols << symbol
      @node_symbols[declaration_id] = symbol.id
      symbol
    end

    def function_for(declaration_id : NodeId) : SemanticFunctionSymbol?
      @functions_by_declaration[declaration_id]?
    end

    def set_type(node_id : NodeId, type_id : TypeId) : Nil
      @node_types[node_id] = type_id
    end

    def set_symbol(node_id : NodeId, symbol_id : SymbolId) : Nil
      @node_symbols[node_id] = symbol_id
    end

    def type_of(node_id : NodeId) : TypeId?
      @node_types[node_id]?
    end

    def report(span : SourceSpan, description : String) : Nil
      return if @diagnostic
      @diagnostic = SemanticDiagnostic.new(@parsed_module.source_file, span, description)
    end

    def finish : SemanticModule
      SemanticModule.new(@parsed_module, @type_table, @node_types, @node_symbols, @symbols)
    end

    private def parameter_type_ids(parameters : NodeRange) : Array(TypeId)
      types = Array(TypeId).new(parameters.count)
      parameters.count.times do |index|
        parameter_id = @arena.child(parameters, index)
        parameter = @arena.node(parameter_id).as(ParameterNode)
        types << @type_table.id_for(parameter.type)
      end
      types
    end
  end

  class BooleanMatchPatternValidator < SourceMatchPatternVisitor
    getter failure : Tuple(SourceSpan, String)?

    @current_index : Int32
    @case_count : Int32
    @has_true : Bool
    @has_false : Bool
    @has_wildcard : Bool

    def initialize
      @failure = nil
      @current_index = 0
      @case_count = 0
      @has_true = false
      @has_false = false
      @has_wildcard = false
    end

    def validate_case(pattern : SourceMatchPatternNode, index : Int32, case_count : Int32) : Nil
      @current_index = index
      @case_count = case_count
      pattern.accept(self)
    end

    def finish(span : SourceSpan) : Nil
      return if @failure

      if @case_count != 2
        fail_at(span, "bool match must have exactly two cases")
      elsif @has_true && @has_false
        return
      elsif @has_wildcard && (@has_true != @has_false)
        return
      else
        fail_at(span, "bool match must cover true and false, or use one final wildcard case")
      end
    end

    def visit(pattern : BooleanMatchPatternNode) : Nil
      if @has_wildcard
        fail_at(pattern.span, "case is unreachable after wildcard pattern")
      elsif pattern.value
        if @has_true
          fail_at(pattern.span, "duplicate bool pattern true")
        else
          @has_true = true
        end
      elsif @has_false
        fail_at(pattern.span, "duplicate bool pattern false")
      else
        @has_false = true
      end
    end

    def visit(pattern : WildcardMatchPatternNode) : Nil
      if @has_wildcard
        fail_at(pattern.span, "duplicate wildcard pattern")
      elsif @current_index != @case_count - 1
        fail_at(pattern.span, "wildcard pattern must be the final case")
      else
        @has_wildcard = true
      end
    end

    private def fail_at(span : SourceSpan, description : String) : Nil
      @failure = {span, description}
    end
  end

  abstract class SemanticAstVisitor < AstVisitor
    protected getter context : SemanticContext

    @current_node_id : NodeId?

    def initialize(@context : SemanticContext)
      @current_node_id = nil
    end

    protected def visit_node(node_id : NodeId) : Nil
      previous_node_id = @current_node_id
      @current_node_id = node_id
      @context.arena.node(node_id).accept(self)
      @current_node_id = previous_node_id
    end

    protected def current_node_id : NodeId
      @current_node_id.not_nil!
    end

    def visit(node : ModuleNode) : Nil
    end

    def visit(node : FunctionNode) : Nil
    end

    def visit(node : ParameterNode) : Nil
    end

    def visit(node : ReturnNode) : Nil
    end

    def visit(node : MatchExpressionNode) : Nil
    end

    def visit(node : MatchCaseNode) : Nil
    end

    def visit(node : BooleanMatchPatternNode) : Nil
    end

    def visit(node : WildcardMatchPatternNode) : Nil
    end

    def visit(node : BinaryExpr) : Nil
    end

    def visit(node : CallExpr) : Nil
    end

    def visit(node : IdentifierExpr) : Nil
    end

    def visit(node : IntegerLiteralExpr) : Nil
    end

    def visit(node : BooleanLiteralExpr) : Nil
    end

    def visit(node : ErrorNode) : Nil
      @context.report(node.span, "cannot analyze syntax with parse errors")
    end
  end

  class FunctionDeclarationCollector < SemanticAstVisitor
    def collect : Nil
      visit_node(@context.parsed_module.root_id)
    end

    def visit(node : ModuleNode) : Nil
      node.functions.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.arena.child(node.functions, index))
      end
    end

    def visit(node : FunctionNode) : Nil
      @context.add_function(current_node_id, node)
      nil
    end
  end

  class FunctionBodyChecker < SemanticAstVisitor
    @current_function : SemanticFunctionSymbol?
    @current_parameter_scope : FunctionParameterScope?
    @expected_type_id : TypeId?

    def initialize(context : SemanticContext)
      super(context)
      @current_function = nil
      @current_parameter_scope = nil
      @expected_type_id = nil
    end

    def check : Nil
      visit_node(@context.parsed_module.root_id)
    end

    def visit(node : ModuleNode) : Nil
      node.functions.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.arena.child(node.functions, index))
      end
    end

    def visit(node : FunctionNode) : Nil
      function_symbol = @context.function_for(current_node_id)
      unless function_symbol
        @context.report(node.name, "function declaration was not registered")
        return
      end

      parameter_scope = FunctionParameterScope.new
      node.parameters.count.times do |index|
        return if @context.diagnostic
        parameter_id = @context.arena.child(node.parameters, index)
        parameter = @context.arena.node(parameter_id).as(ParameterNode)
        name = @context.parsed_module.source_file.slice(parameter.name)
        if parameter_scope.resolve(name)
          @context.report(parameter.name, "duplicate parameter '#{name}'")
          return
        end

        parameter_symbol = @context.add_parameter(parameter_id, parameter)
        parameter_scope.declare(name, parameter_symbol)
      end

      @current_function = function_symbol
      @current_parameter_scope = parameter_scope
      visit_node(node.body)
      @current_function = nil
      @current_parameter_scope = nil
    end

    def visit(node : ReturnNode) : Nil
      function = @current_function.not_nil!
      value_type = analyze_expression(node.value, function.result_type_id)
      return if @context.diagnostic
      unless value_type
        @context.report(@context.arena.node(node.value).span, "integer literal requires an expected integer type")
        return
      end

      if value_type != function.result_type_id
        value_span = @context.arena.node(node.value).span
        @context.report(value_span, "return has type #{type_label(value_type)}, expected #{type_label(function.result_type_id)}")
      end
    end

    def visit(node : MatchExpressionNode) : Nil
      bool_type_id = @context.type_table.bool_type_id
      scrutinee_type = analyze_expression(node.scrutinee, bool_type_id)
      return if @context.diagnostic
      unless scrutinee_type == bool_type_id
        actual_type = scrutinee_type.try { |type_id| type_label(type_id) } || "unknown"
        @context.report(@context.arena.node(node.scrutinee).span, "match value has type #{actual_type}, expected bool")
        return
      end

      return unless validate_boolean_match_cases(node)

      case_types = Array(TypeId?).new(node.cases.count)
      node.cases.count.times do |index|
        case_node = @context.arena.node(@context.arena.child(node.cases, index)).as(MatchCaseNode)
        case_types << analyze_expression(case_node.result, @expected_type_id)
        return if @context.diagnostic
      end

      result_type_id = @expected_type_id || case_types.compact.first?
      return unless result_type_id

      node.cases.count.times do |index|
        case_node = @context.arena.node(@context.arena.child(node.cases, index)).as(MatchCaseNode)
        result_type = case_types[index] || analyze_expression(case_node.result, result_type_id)
        return if @context.diagnostic
        unless result_type
          @context.report(@context.arena.node(case_node.result).span, "match case result requires an expected type")
          return
        end
        if result_type != result_type_id
          @context.report(
            @context.arena.node(case_node.result).span,
            "match case has type #{type_label(result_type)}, expected #{type_label(result_type_id)}"
          )
          return
        end
      end

      @context.set_type(current_node_id, result_type_id)
    end

    def visit(node : BinaryExpr) : Nil
      left_type = analyze_expression(node.left)
      return if @context.diagnostic
      right_type = analyze_expression(node.right)
      return if @context.diagnostic

      expected_type_id = @expected_type_id
      if left_type.nil? && right_type.nil?
        return unless expected_type_id
        left_type = analyze_expression(node.left, expected_type_id)
        return if @context.diagnostic
        right_type = analyze_expression(node.right, expected_type_id)
      elsif left_type.nil? && right_type
        left_type = analyze_expression(node.left, right_type)
      elsif right_type.nil? && left_type
        right_type = analyze_expression(node.right, left_type)
      end

      return if @context.diagnostic || left_type.nil? || right_type.nil?

      if left_type != right_type
        operator = node.operator == BinaryOperator::Add ? "+" : "-"
        @context.report(node.span, "operator '#{operator}' operands must have matching types")
        return
      end

      unless @context.type_table.supports_integer_arithmetic?(left_type)
        operator = node.operator == BinaryOperator::Add ? "+" : "-"
        @context.report(node.span, "operator '#{operator}' requires integer operands")
        return
      end

      @context.set_type(current_node_id, left_type)
    end

    def visit(node : CallExpr) : Nil
      name = @context.parsed_module.source_file.slice(node.callee)
      function = @context.module_scope.resolve(name)
      unless function
        @context.report(node.callee, "unknown function '#{name}'")
        return
      end

      if node.arguments.count != function.parameter_count
        @context.report(node.span, "function '#{name}' expects #{function.parameter_count} argument#{function.parameter_count == 1 ? "" : "s"}, got #{node.arguments.count}")
        return
      end

      node.arguments.count.times do |index|
        argument_id = @context.arena.child(node.arguments, index)
        expected_type = function.parameter_type(index).not_nil!
        argument_type = analyze_expression(argument_id, expected_type)
        return if @context.diagnostic
        unless argument_type
          @context.report(@context.arena.node(argument_id).span, "integer literal requires an expected integer type")
          return
        end

        if argument_type != expected_type
          @context.report(
            @context.arena.node(argument_id).span,
            "argument #{index} has type #{type_label(argument_type)}, expected #{type_label(expected_type)}"
          )
          return
        end
      end

      @context.set_symbol(current_node_id, function.id)
      @context.set_type(current_node_id, function.result_type_id)
    end

    def visit(node : IdentifierExpr) : Nil
      name = @context.parsed_module.source_file.slice(node.span)
      parameter = @current_parameter_scope.try(&.resolve(name))
      unless parameter
        @context.report(node.span, "unknown name '#{name}'")
        return
      end

      @context.set_symbol(current_node_id, parameter.id)
      @context.set_type(current_node_id, parameter.type_id)
    end

    def visit(node : IntegerLiteralExpr) : Nil
      expected_type_id = @expected_type_id
      return unless expected_type_id

      if expected_type_id == @context.type_table.bool_type_id
        @context.set_type(current_node_id, @context.type_table.int_type_id)
        return
      end

      literal_text = @context.parsed_module.source_file.slice(node.span)
      literal_value = literal_text.to_u128?
      unless literal_value && @context.type_table.fits_nonnegative_literal?(expected_type_id, literal_value)
        @context.report(node.span, "literal #{literal_text} does not fit type #{type_label(expected_type_id)}")
        return
      end

      @context.set_type(current_node_id, expected_type_id)
    end

    def visit(node : BooleanLiteralExpr) : Nil
      @context.set_type(current_node_id, @context.type_table.bool_type_id)
    end

    private def analyze_expression(node_id : NodeId, expected_type_id : TypeId? = nil) : TypeId?
      return nil if @context.diagnostic
      previous_expected_type_id = @expected_type_id
      @expected_type_id = expected_type_id
      visit_node(node_id)
      @expected_type_id = previous_expected_type_id
      @context.type_of(node_id)
    end

    private def validate_boolean_match_cases(node : MatchExpressionNode) : Bool
      validator = BooleanMatchPatternValidator.new
      node.cases.count.times do |index|
        case_node = @context.arena.node(@context.arena.child(node.cases, index)).as(MatchCaseNode)
        pattern = @context.arena.node(case_node.pattern).as(SourceMatchPatternNode)
        validator.validate_case(pattern, index, node.cases.count)
        break if validator.failure
      end

      validator.finish(node.span)
      unless failure = validator.failure
        return true
      end
      @context.report(failure[0], failure[1])
      false
    end

    private def type_label(type_id : TypeId) : String
      @context.type_table.label(type_id)
    end
  end

  class SemanticAnalyzer
    def initialize(@parsed_module : ParsedModule)
    end

    def analyze : SemanticResult
      context = SemanticContext.new(@parsed_module)
      FunctionDeclarationCollector.new(context).collect
      return failed_result(context) if context.diagnostic

      entry_diagnostic = entrypoint_diagnostic(context)
      return SemanticResult.new(nil, entry_diagnostic) if entry_diagnostic

      FunctionBodyChecker.new(context).check
      return failed_result(context) if context.diagnostic

      SemanticResult.new(context.finish, nil)
    end

    private def entrypoint_diagnostic(context : SemanticContext) : SemanticDiagnostic?
      root = @parsed_module.arena.node(@parsed_module.root_id).as(ModuleNode)
      main = context.module_scope.resolve("main")
      unless main
        source_file = @parsed_module.source_file
        return SemanticDiagnostic.new(source_file, root.span, "module must define 'main() -> int'")
      end

      unless main.parameter_count == 0
        declaration = @parsed_module.arena.node(main.declaration_id).as(FunctionNode)
        return SemanticDiagnostic.new(
          @parsed_module.source_file,
          declaration.name,
          "main must have no parameters"
        )
      end

      unless main.result_type_id == context.type_table.int_type_id
        declaration = @parsed_module.arena.node(main.declaration_id).as(FunctionNode)
        return SemanticDiagnostic.new(
          @parsed_module.source_file,
          declaration.name,
          "main must return int"
        )
      end

      nil
    end

    private def failed_result(context : SemanticContext) : SemanticResult
      SemanticResult.new(nil, context.diagnostic)
    end
  end
end
