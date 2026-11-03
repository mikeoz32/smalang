require "./lexer"
require "./parser"

module Smalang
  alias SymbolId = Int32
  alias TypeId = Int32

  enum SemanticType : UInt8
    Int
    UInt
    Bool
  end

  class SemanticTypeTable
    getter int_type_id : TypeId
    getter uint_type_id : TypeId
    getter bool_type_id : TypeId

    @types : Array(SemanticType)
    @integer_arithmetic_type_ids : Array(TypeId)

    def initialize
      @types = [SemanticType::Int, SemanticType::UInt, SemanticType::Bool]
      @int_type_id = 0
      @uint_type_id = 1
      @bool_type_id = 2
      @integer_arithmetic_type_ids = [@int_type_id, @uint_type_id]
    end

    def id_for(source_type : AstType) : TypeId
      case source_type
      when AstType::Int
        @int_type_id
      when AstType::UInt
        @uint_type_id
      when AstType::Bool
        @bool_type_id
      else
        raise ArgumentError.new("unsupported AST type #{source_type}")
      end
    end

    def label(type_id : TypeId) : String
      @types[type_id].to_s.downcase
    end

    def supports_integer_arithmetic?(type_id : TypeId) : Bool
      @integer_arithmetic_type_ids.includes?(type_id)
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

    def initialize(context : SemanticContext)
      super(context)
      @current_function = nil
      @current_parameter_scope = nil
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
      value_type = analyze_expression(node.value)
      return if @context.diagnostic || value_type.nil?

      function = @current_function.not_nil!
      if value_type != function.result_type_id
        value_span = @context.arena.node(node.value).span
        @context.report(value_span, "return has type #{type_label(value_type)}, expected #{type_label(function.result_type_id)}")
      end
    end

    def visit(node : BinaryExpr) : Nil
      left_type = analyze_expression(node.left)
      return if @context.diagnostic || left_type.nil?
      right_type = analyze_expression(node.right)
      return if @context.diagnostic || right_type.nil?

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
        argument_type = analyze_expression(argument_id)
        return if @context.diagnostic || argument_type.nil?

        expected_type = function.parameter_type(index).not_nil!
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
      @context.set_type(current_node_id, @context.type_table.int_type_id)
    end

    def visit(node : BooleanLiteralExpr) : Nil
      @context.set_type(current_node_id, @context.type_table.bool_type_id)
    end

    private def analyze_expression(node_id : NodeId) : TypeId?
      return nil if @context.diagnostic
      visit_node(node_id)
      @context.type_of(node_id)
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
