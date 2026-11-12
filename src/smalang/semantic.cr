require "./lexer"
require "./parser"
require "./heap_storage_layout"

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

    def supported_source_type?(_type_table : SemanticTypeTable) : Bool
      true
    end

    def supported_array_element?(_type_table : SemanticTypeTable) : Bool
      true
    end
  end

  struct ArrayTypeInfo
    getter element_type_id : TypeId
    getter length : UInt128

    def initialize(@element_type_id : TypeId, @length : UInt128)
    end

    def supported_source_type?(type_table : SemanticTypeTable) : Bool
      type_table.supported_array_element_type?(@element_type_id)
    end

    def supported_array_element?(type_table : SemanticTypeTable) : Bool
      supported_source_type?(type_table)
    end
  end

  struct PointerTypeInfo
    getter pointee_type_id : TypeId

    def initialize(@pointee_type_id : TypeId)
    end

    def supported_source_type?(type_table : SemanticTypeTable) : Bool
      type_table.scalar_type(@pointee_type_id) != nil
    end

    def supported_array_element?(_type_table : SemanticTypeTable) : Bool
      false
    end
  end

  class SemanticTypeTable
    POINTER_WIDTH = 64

    getter int_type_id : TypeId
    getter uint_type_id : TypeId
    getter bool_type_id : TypeId

    alias TypeInfo = IntegerTypeInfo | ArrayTypeInfo | PointerTypeInfo

    @types : Array(TypeInfo)
    @type_ids_by_ast_type : Hash(AstType, TypeId)
    @array_type_ids : Hash(Tuple(TypeId, UInt128), TypeId)
    @pointer_type_ids : Hash(TypeId, TypeId)

    def initialize
      @types = [] of TypeInfo
      @type_ids_by_ast_type = {} of AstType => TypeId
      @array_type_ids = {} of Tuple(TypeId, UInt128) => TypeId
      @pointer_type_ids = {} of TypeId => TypeId
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

    def id_for(source_type_id : AstTypeId, arena : AstTypeArena) : TypeId
      case syntax = arena.type(source_type_id)
      when ScalarTypeSyntax
        id_for(syntax.type)
      when ArrayTypeSyntax
        element_type_id = id_for(syntax.element_type_id, arena)
        key = {element_type_id, syntax.length}
        @array_type_ids[key]? || register_array_type(element_type_id, syntax.length)
      when PointerTypeSyntax
        pointee_type_id = id_for(syntax.pointee_type_id, arena)
        @pointer_type_ids[pointee_type_id]? || register_pointer_type(pointee_type_id)
      else
        raise "unknown AST type syntax"
      end
    end

    def label(type_id : TypeId) : String
      case type_info = @types[type_id]
      when IntegerTypeInfo
        type_info.name
      when ArrayTypeInfo
        "array[#{label(type_info.element_type_id)}, #{type_info.length}]"
      when PointerTypeInfo
        "ptr[#{label(type_info.pointee_type_id)}]"
      else
        raise "unknown semantic type info"
      end
    end

    def fits_nonnegative_literal?(type_id : TypeId, value : UInt128) : Bool
      type_info = @types[type_id].as?(IntegerTypeInfo)
      type_info ? type_info.fits_nonnegative_literal?(value) : false
    end

    def supports_integer_arithmetic?(type_id : TypeId) : Bool
      type_info = @types[type_id].as?(IntegerTypeInfo)
      type_info ? type_info.bit_width > 0 : false
    end

    def array_type(type_id : TypeId) : ArrayTypeInfo?
      @types[type_id].as?(ArrayTypeInfo)
    end

    def pointer_type(type_id : TypeId) : PointerTypeInfo?
      @types[type_id].as?(PointerTypeInfo)
    end

    def scalar_type_id(name : String) : TypeId?
      case name
      when "int"    then @type_ids_by_ast_type[AstType::Int]?
      when "uint"   then @type_ids_by_ast_type[AstType::UInt]?
      when "bool"   then @type_ids_by_ast_type[AstType::Bool]?
      when "int8"   then @type_ids_by_ast_type[AstType::Int8]?
      when "uint8"  then @type_ids_by_ast_type[AstType::UInt8]?
      when "int16"  then @type_ids_by_ast_type[AstType::Int16]?
      when "uint16" then @type_ids_by_ast_type[AstType::UInt16]?
      when "int32"  then @type_ids_by_ast_type[AstType::Int32]?
      when "uint32" then @type_ids_by_ast_type[AstType::UInt32]?
      when "int64"  then @type_ids_by_ast_type[AstType::Int64]?
      when "uint64" then @type_ids_by_ast_type[AstType::UInt64]?
      else
        nil
      end
    end

    def storage_alignment(type_id : TypeId) : UInt128?
      case type_info = @types[type_id]
      when IntegerTypeInfo
        type_info.bit_width == 0 ? 1_u128 : (type_info.bit_width // 8).to_u128
      when PointerTypeInfo
        (POINTER_WIDTH // 8).to_u128
      when ArrayTypeInfo
        storage_alignment(type_info.element_type_id)
      else
        nil
      end
    end

    def pointer_type_id(pointee_type_id : TypeId) : TypeId
      @pointer_type_ids[pointee_type_id]? || register_pointer_type(pointee_type_id)
    end

    def scalar_type(type_id : TypeId) : IntegerTypeInfo?
      @types[type_id].as?(IntegerTypeInfo)
    end

    def storage_size(type_id : TypeId) : UInt128?
      case type_info = @types[type_id]
      when IntegerTypeInfo
        type_info.bit_width == 0 ? 1_u128 : (type_info.bit_width // 8).to_u128
      when ArrayTypeInfo
        element_size = storage_size(type_info.element_type_id)
        return nil unless element_size
        return 0_u128 if type_info.length == 0
        return nil if element_size > UInt128::MAX // type_info.length
        element_size * type_info.length
      when PointerTypeInfo
        (POINTER_WIDTH // 8).to_u128
      else
        nil
      end
    end

    private def register_type(ast_type : AstType, type_info : IntegerTypeInfo) : Nil
      @type_ids_by_ast_type[ast_type] = @types.size
      @types << type_info
    end

    private def register_array_type(element_type_id : TypeId, length : UInt128) : TypeId
      type_id = @types.size
      @types << ArrayTypeInfo.new(element_type_id, length)
      @array_type_ids[{element_type_id, length}] = type_id
      type_id
    end

    private def register_pointer_type(pointee_type_id : TypeId) : TypeId
      type_id = @types.size
      @types << PointerTypeInfo.new(pointee_type_id)
      @pointer_type_ids[pointee_type_id] = type_id
      type_id
    end

    def supported_source_type?(type_id : TypeId) : Bool
      @types[type_id].supported_source_type?(self)
    end

    def supported_array_element_type?(type_id : TypeId) : Bool
      @types[type_id].supported_array_element?(self)
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

  abstract class SemanticBindingSymbol < SemanticSymbol
    getter type_id : TypeId
    getter mutability : BindingMutability

    def initialize(id : SymbolId, declaration_id : NodeId, name_span : SourceSpan, @type_id : TypeId, @mutability : BindingMutability)
      super(id, declaration_id, name_span)
    end

    def mutable? : Bool
      @mutability == BindingMutability::Mutable
    end
  end

  class SemanticParameterSymbol < SemanticBindingSymbol
    def initialize(id : SymbolId, declaration_id : NodeId, name_span : SourceSpan, type_id : TypeId, mutability : BindingMutability)
      super(id, declaration_id, name_span, type_id, mutability)
    end
  end

  class SemanticLocalSymbol < SemanticBindingSymbol
    def initialize(id : SymbolId, declaration_id : NodeId, name_span : SourceSpan, type_id : TypeId, mutability : BindingMutability)
      super(id, declaration_id, name_span, type_id, mutability)
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

  class FunctionBindingScope
    @symbols_by_name : Hash(String, SemanticBindingSymbol)

    def initialize
      @symbols_by_name = Hash(String, SemanticBindingSymbol).new
    end

    def declare(name : String, symbol : SemanticBindingSymbol) : Bool
      return false if @symbols_by_name.has_key?(name)
      @symbols_by_name[name] = symbol
      true
    end

    def resolve(name : String) : SemanticBindingSymbol?
      @symbols_by_name[name]?
    end
  end

  class SemanticModule
    getter parsed_module : ParsedModule
    getter type_table : SemanticTypeTable

    @node_types : Array(TypeId?)
    @node_symbols : Array(SymbolId?)
    @constant_uint_values : Array(UInt64?)
    @address_taken_symbols : Array(SymbolId)
    @symbols : Array(SemanticSymbol)

    def initialize(@parsed_module : ParsedModule, @type_table : SemanticTypeTable, node_types : Array(TypeId?), node_symbols : Array(SymbolId?), constant_uint_values : Array(UInt64?), address_taken_symbols : Array(SymbolId), symbols : Array(SemanticSymbol))
      @node_types = node_types.dup
      @node_symbols = node_symbols.dup
      @constant_uint_values = constant_uint_values.dup
      @address_taken_symbols = address_taken_symbols.dup
      @symbols = symbols.dup
    end

    def type_of(node_id : NodeId) : TypeId?
      @node_types[node_id]?
    end

    def symbol_for(node_id : NodeId) : SymbolId?
      @node_symbols[node_id]?
    end

    def constant_uint_value(node_id : NodeId) : UInt64?
      @constant_uint_values[node_id]?
    end

    def address_taken?(symbol_id : SymbolId) : Bool
      @address_taken_symbols.includes?(symbol_id)
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
    @constant_uint_values : Array(UInt64?)
    @address_taken_symbols : Array(SymbolId)
    @symbols : Array(SemanticSymbol)
    @functions_by_declaration : Hash(NodeId, SemanticFunctionSymbol)

    def initialize(@parsed_module : ParsedModule)
      @arena = parsed_module.arena
      @type_table = SemanticTypeTable.new
      @module_scope = ModuleFunctionScope.new
      @node_types = Array(TypeId?).new(@arena.size) { nil }
      @node_symbols = Array(SymbolId?).new(@arena.size) { nil }
      @constant_uint_values = Array(UInt64?).new(@arena.size) { nil }
      @address_taken_symbols = Array(SymbolId).new
      @symbols = Array(SemanticSymbol).new
      @functions_by_declaration = Hash(NodeId, SemanticFunctionSymbol).new
      @diagnostic = nil
    end

    def add_function(declaration_id : NodeId, declaration : FunctionNode) : SemanticFunctionSymbol?
      name = @parsed_module.source_file.slice(declaration.name)
      if unsafe_memory_operation_name?(name)
        report(declaration.name, "function name '#{name}' is reserved for an unsafe memory operation")
        return nil
      end
      if @module_scope.resolve(name)
        report(declaration.name, "duplicate function '#{name}'")
        return nil
      end

      parameter_types = parameter_type_ids(declaration.parameters)
      return nil if @diagnostic

      declaration.parameters.count.times do |index|
        parameter_id = @arena.child(declaration.parameters, index)
        parameter = @arena.node(parameter_id).as(ParameterNode)
        type_id = parameter_types[index]
        unless @type_table.supported_source_type?(type_id)
          type_syntax = @parsed_module.type_arena.type(parameter.type)
          report(type_syntax.span, "unsupported type '#{@type_table.label(type_id)}'")
          return nil
        end
      end

      result_type_id = @type_table.id_for(declaration.return_type, @parsed_module.type_arena)
      unless @type_table.supported_source_type?(result_type_id)
        type_syntax = @parsed_module.type_arena.type(declaration.return_type)
        report(type_syntax.span, "unsupported type '#{@type_table.label(result_type_id)}'")
        return nil
      end

      symbol = SemanticFunctionSymbol.new(
        @symbols.size,
        declaration_id,
        declaration.name,
        parameter_types,
        result_type_id
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
        @type_table.id_for(declaration.type, @parsed_module.type_arena),
        declaration.mutability
      )
      @symbols << symbol
      @node_symbols[declaration_id] = symbol.id
      symbol
    end

    def add_local_binding(declaration_id : NodeId, declaration : VariableDeclarationNode) : SemanticLocalSymbol
      symbol = SemanticLocalSymbol.new(
        @symbols.size,
        declaration_id,
        declaration.name,
        @type_table.id_for(declaration.type, @parsed_module.type_arena),
        declaration.mutability
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

    def set_constant_uint_value(node_id : NodeId, value : UInt64) : Nil
      @constant_uint_values[node_id] = value
    end

    def set_address_taken(symbol_id : SymbolId) : Nil
      @address_taken_symbols << symbol_id unless @address_taken_symbols.includes?(symbol_id)
    end

    def constant_uint_value(node_id : NodeId) : UInt64?
      @constant_uint_values[node_id]?
    end

    def type_of(node_id : NodeId) : TypeId?
      @node_types[node_id]?
    end

    def report(span : SourceSpan, description : String) : Nil
      return if @diagnostic
      @diagnostic = SemanticDiagnostic.new(@parsed_module.source_file, span, description)
    end

    def finish : SemanticModule
      SemanticModule.new(@parsed_module, @type_table, @node_types, @node_symbols, @constant_uint_values, @address_taken_symbols, @symbols)
    end

    private def parameter_type_ids(parameters : NodeRange) : Array(TypeId)
      types = Array(TypeId).new(parameters.count)
      parameters.count.times do |index|
        parameter_id = @arena.child(parameters, index)
        parameter = @arena.node(parameter_id).as(ParameterNode)
        types << @type_table.id_for(parameter.type, @parsed_module.type_arena)
      end
      types
    end

    private def unsafe_memory_operation_name?(name : String) : Bool
      name == "alloc" || name == "alloc_stack" || name == "offset" || name == "cast" || name == "stack_storage" || name == "heap_storage" || name == "heap_free" || name == "copy_memory" || name == "size_of" || name == "align_of" || name == "address_of" || name == "load" || name == "store" || name == "free"
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
        fail_at(span, "bool match must cover True and False, or use one final wildcard case")
      end
    end

    def visit(pattern : BooleanMatchPatternNode) : Nil
      if @has_wildcard
        fail_at(pattern.span, "case is unreachable after wildcard pattern")
      elsif pattern.value
        if @has_true
          fail_at(pattern.span, "duplicate bool pattern True")
        else
          @has_true = true
        end
      elsif @has_false
        fail_at(pattern.span, "duplicate bool pattern False")
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

    def visit(node : VariableDeclarationNode) : Nil
    end

    def visit(node : AssignmentNode) : Nil
    end

    def visit(node : ReturnNode) : Nil
    end

    def visit(node : UnsafeBlockNode) : Nil
    end

    def visit(node : CallStatementNode) : Nil
    end

    def visit(node : AllocateExpr) : Nil
    end

    def visit(node : StackAllocateExpr) : Nil
    end

    def visit(node : PointerOffsetExpr) : Nil
    end

    def visit(node : LoadExpr) : Nil
    end

    def visit(node : StoreExpr) : Nil
    end

    def visit(node : FreeExpr) : Nil
    end

    def visit(node : StoreStatementNode) : Nil
    end

    def visit(node : FreeStatementNode) : Nil
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

    def visit(node : ArrayLiteralExpr) : Nil
    end

    def visit(node : IndexExpr) : Nil
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
    @current_binding_scope : FunctionBindingScope?
    @expected_type_id : TypeId?
    @unsafe_depth : Int32

    def initialize(context : SemanticContext)
      super(context)
      @current_function = nil
      @current_binding_scope = nil
      @expected_type_id = nil
      @unsafe_depth = 0
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

      binding_scope = FunctionBindingScope.new
      node.parameters.count.times do |index|
        return if @context.diagnostic
        parameter_id = @context.arena.child(node.parameters, index)
        parameter = @context.arena.node(parameter_id).as(ParameterNode)
        name = @context.parsed_module.source_file.slice(parameter.name)
        if binding_scope.resolve(name)
          @context.report(parameter.name, "duplicate parameter '#{name}'")
          return
        end

        parameter_symbol = @context.add_parameter(parameter_id, parameter)
        binding_scope.declare(name, parameter_symbol)
      end

      @current_function = function_symbol
      @current_binding_scope = binding_scope
      node.statements.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.arena.child(node.statements, index))
      end
      visit_node(node.body)
      @current_function = nil
      @current_binding_scope = nil
    end

    def visit(node : VariableDeclarationNode) : Nil
      scope = @current_binding_scope.not_nil!
      name = @context.parsed_module.source_file.slice(node.name)
      if scope.resolve(name)
        @context.report(node.name, "duplicate binding '#{name}'")
        return
      end

      type_id = @context.type_table.id_for(node.type, @context.parsed_module.type_arena)
      unless @context.type_table.supported_source_type?(type_id)
        type_syntax = @context.parsed_module.type_arena.type(node.type)
        @context.report(type_syntax.span, "unsupported type '#{@context.type_table.label(type_id)}'")
        return
      end
      initializer_type_id = analyze_expression(node.initializer, type_id)
      return if @context.diagnostic
      unless initializer_type_id == type_id
        actual_type = initializer_type_id.try { |id| type_label(id) } || "unknown"
        @context.report(node.name, "initializer has type #{actual_type}, expected #{type_label(type_id)}")
        return
      end

      symbol = @context.add_local_binding(current_node_id, node)
      scope.declare(name, symbol)
    end

    def visit(node : AssignmentNode) : Nil
      scope = @current_binding_scope.not_nil!
      target = @context.arena.node(node.target)
      case target
      when IdentifierExpr
        name = @context.parsed_module.source_file.slice(target.span)
        binding = scope.resolve(name)
        unless binding
          @context.report(target.span, "unknown name '#{name}'")
          return
        end
        unless binding.mutable?
          @context.report(target.span, "cannot assign to immutable binding '#{name}'")
          return
        end

        value_type_id = analyze_expression(node.value, binding.type_id)
        return if @context.diagnostic
        unless value_type_id == binding.type_id
          actual_type = value_type_id.try { |id| type_label(id) } || "unknown"
          @context.report(target.span, "assignment has type #{actual_type}, expected #{type_label(binding.type_id)}")
          return
        end
        @context.set_symbol(current_node_id, binding.id)
      when IndexExpr
        target_type_id = analyze_expression(node.target)
        return if @context.diagnostic
        root_binding = mutable_array_binding(node.target)
        return if @context.diagnostic
        unless root_binding
          @context.report(target.span, "indexed assignment requires a mutable array binding")
          return
        end
        unless root_binding.mutable?
          @context.report(target.span, "cannot modify elements of immutable binding '#{binding_name(root_binding)}'")
          return
        end

        value_type_id = target_type_id.try { |id| analyze_expression(node.value, id) }
        return if @context.diagnostic
        unless target_type_id && value_type_id == target_type_id
          actual_type = value_type_id.try { |id| type_label(id) } || "unknown"
          expected_type = target_type_id.try { |id| type_label(id) } || "unknown"
          @context.report(target.span, "indexed assignment has type #{actual_type}, expected #{expected_type}")
          return
        end
        @context.set_symbol(current_node_id, root_binding.id)
      else
        @context.report(target.span, "invalid assignment target")
      end
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

    def visit(node : UnsafeBlockNode) : Nil
      @unsafe_depth += 1
      begin
        node.statements.count.times do |index|
          return if @context.diagnostic
          visit_node(@context.arena.child(node.statements, index))
        end
      ensure
        @unsafe_depth -= 1
      end
    end

    def visit(node : CallStatementNode) : Nil
      call = @context.arena.node(node.call).as?(CallExpr)
      name = call.try { |expression| @context.parsed_module.source_file.slice(expression.callee) }
      if call && name == "heap_free"
        analyze_heap_free(call)
      elsif call && name == "copy_memory"
        analyze_copy_memory(call)
      else
        @context.report(node.span, "expression statements are not supported")
      end
    end

    def visit(node : AllocateExpr) : Nil
      analyze_allocation(node.arguments, node.span, "alloc")
    end

    def visit(node : StackAllocateExpr) : Nil
      analyze_allocation(node.arguments, node.span, "alloc_stack")
    end

    def visit(node : PointerOffsetExpr) : Nil
      return unless require_unsafe_context(node.span, "offset")
      unless node.arguments.count == 2
        @context.report(node.span, "offset expects 2 arguments, got #{node.arguments.count}")
        return
      end

      address_id = @context.arena.child(node.arguments, 0)
      address_type_id = analyze_expression(address_id)
      return if @context.diagnostic
      pointer_type = address_type_id.try { |type_id| @context.type_table.pointer_type(type_id) }
      unless pointer_type
        actual_type = address_type_id.try { |type_id| type_label(type_id) } || "untyped expression"
        @context.report(@context.arena.node(address_id).span, "offset requires ptr[T], got #{actual_type}")
        return
      end

      index_id = @context.arena.child(node.arguments, 1)
      index_type_id = analyze_expression(index_id, @context.type_table.uint_type_id)
      return if @context.diagnostic
      unless index_type_id == @context.type_table.uint_type_id
        actual_type = index_type_id.try { |type_id| type_label(type_id) } || "untyped expression"
        @context.report(@context.arena.node(index_id).span, "offset index has type #{actual_type}, expected uint")
        return
      end

      @context.set_type(current_node_id, address_type_id.not_nil!)
    end

    private def analyze_pointer_cast(node : CallExpr) : Nil
      return unless require_unsafe_context(node.span, "cast")
      unless node.type_argument
        @context.report(node.span, "cast requires an explicit target type: cast[U](address)")
        return
      end
      unless node.arguments.count == 1
        @context.report(node.span, "cast expects 1 argument, got #{node.arguments.count}")
        return
      end

      address_id = @context.arena.child(node.arguments, 0)
      address_type_id = analyze_expression(address_id)
      return if @context.diagnostic

      pointer_type = address_type_id.try { |type_id| @context.type_table.pointer_type(type_id) }
      unless pointer_type
        actual_type = address_type_id.try { |type_id| type_label(type_id) } || "untyped expression"
        @context.report(@context.arena.node(address_id).span, "cast requires ptr[T], got #{actual_type}")
        return
      end
      unless @context.type_table.scalar_type(pointer_type.pointee_type_id)
        @context.report(@context.arena.node(address_id).span, "cast supports scalar pointer types only")
        return
      end

      target_type_id = @context.type_table.id_for(node.type_argument.not_nil!, @context.parsed_module.type_arena)
      unless @context.type_table.scalar_type(target_type_id)
        target_type = @context.type_table.label(target_type_id)
        target_span = @context.parsed_module.type_arena.type(node.type_argument.not_nil!).span
        @context.report(target_span, "cast target type must be scalar, got #{target_type}")
        return
      end

      @context.set_type(current_node_id, @context.type_table.pointer_type_id(target_type_id))
    end

    private def analyze_type_layout_query(node : CallExpr, operation_name : String) : Nil
      return unless require_unsafe_context(node.span, operation_name)
      unless node.arguments.count == 1
        @context.report(node.span, "#{operation_name} expects 1 type argument, got #{node.arguments.count}")
        return
      end

      argument_id = @context.arena.child(node.arguments, 0)
      type_id = type_operand_id(argument_id)
      unless type_id
        @context.report(@context.arena.node(argument_id).span, "#{operation_name} expects a supported type name")
        return
      end

      layout = if operation_name == "size_of"
                 @context.type_table.storage_size(type_id)
               else
                 @context.type_table.storage_alignment(type_id)
               end
      unless layout && layout <= UInt64::MAX
        @context.report(@context.arena.node(argument_id).span, "#{operation_name} layout is not representable as uint")
        return
      end

      @context.set_type(current_node_id, @context.type_table.uint_type_id)
      @context.set_constant_uint_value(current_node_id, layout.to_u64)
    end

    private def type_operand_id(node_id : NodeId) : TypeId?
      case node = @context.arena.node(node_id)
      when IdentifierExpr
        name = @context.parsed_module.source_file.slice(node.span)
        @context.type_table.scalar_type_id(name)
      when IndexExpr
        pointer_name = @context.arena.node(node.array).as?(IdentifierExpr)
        return nil unless pointer_name && @context.parsed_module.source_file.slice(pointer_name.span) == "ptr"
        pointee_type_id = type_operand_id(node.index)
        return nil unless pointee_type_id && @context.type_table.scalar_type(pointee_type_id)
        @context.type_table.pointer_type_id(pointee_type_id)
      else
        nil
      end
    end

    private def analyze_address_of(node : CallExpr) : Nil
      return unless require_unsafe_context(node.span, "address_of")
      unless node.arguments.count == 1
        @context.report(node.span, "address_of expects 1 argument, got #{node.arguments.count}")
        return
      end

      place_id = @context.arena.child(node.arguments, 0)
      identifier = @context.arena.node(place_id).as?(IdentifierExpr)
      unless identifier
        @context.report(@context.arena.node(place_id).span, "address_of requires a scalar local binding or parameter")
        return
      end

      name = @context.parsed_module.source_file.slice(identifier.span)
      binding = @current_binding_scope.try(&.resolve(name))
      unless binding
        @context.report(identifier.span, "unknown name '#{name}'")
        return
      end
      unless @context.type_table.scalar_type(binding.type_id)
        @context.report(identifier.span, "address_of supports scalar local bindings and parameters only")
        return
      end

      @context.set_address_taken(binding.id)
      @context.set_symbol(current_node_id, binding.id)
      @context.set_type(current_node_id, @context.type_table.pointer_type_id(binding.type_id))
    end

    private def analyze_stack_storage(node : CallExpr) : Nil
      return unless require_unsafe_context(node.span, "stack_storage")
      unless node.arguments.count == 2
        @context.report(node.span, "stack_storage expects 2 arguments, got #{node.arguments.count}")
        return
      end

      byte_size_id = @context.arena.child(node.arguments, 0)
      alignment_id = @context.arena.child(node.arguments, 1)
      uint_type_id = @context.type_table.uint_type_id
      byte_size_type_id = analyze_expression(byte_size_id, uint_type_id)
      return if @context.diagnostic
      unless byte_size_type_id == uint_type_id
        actual_type = byte_size_type_id.try { |type_id| type_label(type_id) } || "unknown"
        @context.report(@context.arena.node(byte_size_id).span, "stack_storage byte size has type #{actual_type}, expected uint")
        return
      end

      alignment_type_id = analyze_expression(alignment_id, uint_type_id)
      return if @context.diagnostic
      unless alignment_type_id == uint_type_id
        actual_type = alignment_type_id.try { |type_id| type_label(type_id) } || "unknown"
        @context.report(@context.arena.node(alignment_id).span, "stack_storage alignment has type #{actual_type}, expected uint")
        return
      end

      unless compile_time_constant_expression?(byte_size_id)
        @context.report(@context.arena.node(byte_size_id).span, "stack_storage byte size must be a compile-time constant")
        return
      end
      byte_size = checked_constant_uint_value(byte_size_id)
      unless byte_size
        @context.report(@context.arena.node(byte_size_id).span, "stack_storage byte size constant expression overflows uint")
        return
      end
      unless compile_time_constant_expression?(alignment_id)
        @context.report(@context.arena.node(alignment_id).span, "stack_storage alignment must be a compile-time constant")
        return
      end
      alignment = checked_constant_uint_value(alignment_id)
      unless alignment
        @context.report(@context.arena.node(alignment_id).span, "stack_storage alignment constant expression overflows uint")
        return
      end

      if byte_size == 0
        @context.report(@context.arena.node(byte_size_id).span, "stack_storage byte size must be greater than zero")
        return
      end
      if alignment == 0
        @context.report(@context.arena.node(alignment_id).span, "stack_storage alignment must be greater than zero")
        return
      end
      if (alignment & (alignment - 1_u64)) != 0
        @context.report(@context.arena.node(alignment_id).span, "stack_storage alignment must be a power of two")
        return
      end

      padding = alignment - 1_u64
      if byte_size > UInt64::MAX - padding
        @context.report(node.span, "stack_storage size and alignment overflow uint")
        return
      end
      if byte_size + padding > Int32::MAX.to_u64
        @context.report(node.span, "stack_storage region exceeds x86_64 frame limits")
        return
      end

      byte_type_id = @context.type_table.id_for(AstType::UInt8)
      @context.set_constant_uint_value(byte_size_id, byte_size)
      @context.set_constant_uint_value(alignment_id, alignment)
      @context.set_type(current_node_id, @context.type_table.pointer_type_id(byte_type_id))
    end

    private def analyze_heap_storage(node : CallExpr) : Nil
      return unless require_unsafe_context(node.span, "heap_storage")
      if node.type_argument
        @context.report(node.span, "heap_storage does not accept a type argument")
        return
      end
      unless node.arguments.count == 2
        @context.report(node.span, "heap_storage expects 2 arguments, got #{node.arguments.count}")
        return
      end

      byte_size_id = @context.arena.child(node.arguments, 0)
      byte_size_type_id = analyze_expression(byte_size_id, @context.type_table.uint_type_id)
      return if @context.diagnostic
      unless byte_size_type_id == @context.type_table.uint_type_id
        actual_type = byte_size_type_id.try { |id| type_label(id) } || "unknown"
        @context.report(@context.arena.node(byte_size_id).span, "heap_storage byte size has type #{actual_type}, expected uint")
        return
      end

      alignment_id = @context.arena.child(node.arguments, 1)
      alignment = checked_heap_storage_alignment(alignment_id, "heap_storage")
      return unless alignment

      if compile_time_constant_expression?(byte_size_id)
        byte_size = checked_constant_uint_value(byte_size_id)
        unless byte_size
          @context.report(@context.arena.node(byte_size_id).span, "heap_storage byte size constant expression overflows uint")
          return
        end
        if byte_size.zero?
          @context.report(@context.arena.node(byte_size_id).span, "heap_storage byte size must be greater than zero")
          return
        end

        overhead = alignment - 1_u64 + HeapStorageLayout::MAPPING_HEADER_BYTES
        if byte_size > UInt64::MAX - overhead
          @context.report(@context.arena.node(byte_size_id).span, "heap_storage size and alignment overflow uint")
          return
        end
        @context.set_constant_uint_value(byte_size_id, byte_size)
      end

      @context.set_constant_uint_value(alignment_id, alignment)
      byte_type_id = @context.type_table.id_for(AstType::UInt8)
      @context.set_type(current_node_id, @context.type_table.pointer_type_id(byte_type_id))
    end

    private def analyze_heap_free(node : CallExpr) : Nil
      return unless require_unsafe_context(node.span, "heap_free")
      if node.type_argument
        @context.report(node.span, "heap_free does not accept a type argument")
        return
      end
      unless node.arguments.count == 3
        @context.report(node.span, "heap_free expects 3 arguments, got #{node.arguments.count}")
        return
      end

      address_id = @context.arena.child(node.arguments, 0)
      address_type_id = analyze_expression(address_id)
      return if @context.diagnostic
      byte_type_id = @context.type_table.id_for(AstType::UInt8)
      expected_address_type_id = @context.type_table.pointer_type_id(byte_type_id)
      unless address_type_id == expected_address_type_id
        actual_type = address_type_id.try { |id| type_label(id) } || "unknown"
        @context.report(@context.arena.node(address_id).span, "heap_free requires ptr[uint8], got #{actual_type}")
        return
      end

      byte_size_id = @context.arena.child(node.arguments, 1)
      byte_size_type_id = analyze_expression(byte_size_id, @context.type_table.uint_type_id)
      return if @context.diagnostic
      unless byte_size_type_id == @context.type_table.uint_type_id
        actual_type = byte_size_type_id.try { |id| type_label(id) } || "unknown"
        @context.report(@context.arena.node(byte_size_id).span, "heap_free byte size has type #{actual_type}, expected uint")
        return
      end

      alignment_id = @context.arena.child(node.arguments, 2)
      checked_heap_storage_alignment(alignment_id, "heap_free")
    end

    private def analyze_copy_memory(node : CallExpr) : Nil
      return unless require_unsafe_context(node.span, "copy_memory")
      if node.type_argument
        @context.report(node.span, "copy_memory does not accept a type argument")
        return
      end
      unless node.arguments.count == 3
        @context.report(node.span, "copy_memory expects 3 arguments, got #{node.arguments.count}")
        return
      end

      byte_type_id = @context.type_table.id_for(AstType::UInt8)
      expected_pointer_type_id = @context.type_table.pointer_type_id(byte_type_id)
      ["destination", "source"].each_with_index do |argument_name, index|
        address_id = @context.arena.child(node.arguments, index)
        address_type_id = analyze_expression(address_id)
        return if @context.diagnostic
        unless address_type_id == expected_pointer_type_id
          actual_type = address_type_id.try { |type_id| type_label(type_id) } || "unknown"
          @context.report(@context.arena.node(address_id).span, "copy_memory #{argument_name} requires ptr[uint8], got #{actual_type}")
          return
        end
      end

      byte_count_id = @context.arena.child(node.arguments, 2)
      byte_count_type_id = analyze_expression(byte_count_id, @context.type_table.uint_type_id)
      return if @context.diagnostic
      unless byte_count_type_id == @context.type_table.uint_type_id
        actual_type = byte_count_type_id.try { |type_id| type_label(type_id) } || "unknown"
        @context.report(@context.arena.node(byte_count_id).span, "copy_memory byte count has type #{actual_type}, expected uint")
      end
    end

    private def checked_heap_storage_alignment(alignment_id : NodeId, operation_name : String) : UInt64?
      alignment_type_id = analyze_expression(alignment_id, @context.type_table.uint_type_id)
      return nil if @context.diagnostic
      unless alignment_type_id == @context.type_table.uint_type_id
        actual_type = alignment_type_id.try { |id| type_label(id) } || "unknown"
        @context.report(@context.arena.node(alignment_id).span, "#{operation_name} alignment has type #{actual_type}, expected uint")
        return nil
      end
      unless compile_time_constant_expression?(alignment_id)
        @context.report(@context.arena.node(alignment_id).span, "#{operation_name} alignment must be a compile-time constant")
        return nil
      end

      alignment = checked_constant_uint_value(alignment_id)
      unless alignment
        @context.report(@context.arena.node(alignment_id).span, "#{operation_name} alignment constant expression overflows uint")
        return nil
      end
      if alignment.zero?
        @context.report(@context.arena.node(alignment_id).span, "#{operation_name} alignment must be greater than zero")
        return nil
      end
      unless (alignment & (alignment - 1_u64)) == 0
        @context.report(@context.arena.node(alignment_id).span, "#{operation_name} alignment must be a power of two")
        return nil
      end

      @context.set_constant_uint_value(alignment_id, alignment)
      alignment
    end

    private def checked_constant_uint_value(node_id : NodeId) : UInt64?
      if known_value = @context.constant_uint_value(node_id)
        return known_value
      end

      case node = @context.arena.node(node_id)
      when IntegerLiteralExpr
        @context.parsed_module.source_file.slice(node.span).to_u64?
      when BinaryExpr
        left = checked_constant_uint_value(node.left)
        right = checked_constant_uint_value(node.right)
        return nil unless left && right
        case node.operator
        when BinaryOperator::Add
          return nil if left > UInt64::MAX - right
          left + right
        when BinaryOperator::Subtract
          return nil if left < right
          left - right
        end
      else
        nil
      end
    end

    def visit(node : LoadExpr) : Nil
      analyze_load(node)
    end

    def visit(node : StoreExpr) : Nil
      @context.report(node.span, "store must be a standalone statement")
    end

    def visit(node : FreeExpr) : Nil
      @context.report(node.span, "free must be a standalone statement")
    end

    def visit(node : StoreStatementNode) : Nil
      return unless require_unsafe_context(node.span, "store")
      check_store_statement(node)
    end

    def visit(node : FreeStatementNode) : Nil
      return unless require_unsafe_context(node.span, "free")
      check_free_statement(node)
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

    def visit(node : ArrayLiteralExpr) : Nil
      expected_type_id = @expected_type_id
      unless expected_type_id
        @context.report(node.span, "array literal requires an expected array type")
        return
      end
      array_type = @context.type_table.array_type(expected_type_id)
      unless array_type
        @context.report(node.span, "array literal has an expected non-array type #{type_label(expected_type_id)}")
        return
      end
      unless node.elements.count.to_u128 == array_type.length
        @context.report(node.span, "array literal has #{node.elements.count} elements, expected #{array_type.length}")
        return
      end

      node.elements.count.times do |index|
        element_id = @context.arena.child(node.elements, index)
        unless compile_time_constant_expression?(element_id)
          @context.report(@context.arena.node(element_id).span, "array literal elements must be compile-time constants")
          return
        end
        element_type_id = analyze_expression(element_id, array_type.element_type_id)
        return if @context.diagnostic
        unless element_type_id == array_type.element_type_id
          actual_type = element_type_id.try { |id| type_label(id) } || "unknown"
          @context.report(@context.arena.node(element_id).span, "array element has type #{actual_type}, expected #{type_label(array_type.element_type_id)}")
          return
        end
      end
      @context.set_type(current_node_id, expected_type_id)
    end

    def visit(node : IndexExpr) : Nil
      array_type_id = analyze_expression(node.array)
      return if @context.diagnostic
      unless array_type_id
        @context.report(@context.arena.node(node.array).span, "cannot infer indexed value type")
        return
      end
      array_type = @context.type_table.array_type(array_type_id)
      unless array_type
        @context.report(@context.arena.node(node.array).span, "indexing requires an array, got #{type_label(array_type_id)}")
        return
      end

      index_type_id = analyze_expression(node.index, @context.type_table.uint_type_id)
      return if @context.diagnostic
      unless index_type_id == @context.type_table.uint_type_id
        actual_type = index_type_id.try { |id| type_label(id) } || "unknown"
        @context.report(@context.arena.node(node.index).span, "array index must have type uint, got #{actual_type}")
        return
      end
      if index = constant_uint_value(node.index)
        if index >= array_type.length
          @context.report(@context.arena.node(node.index).span, "array index #{index} is out of bounds for length #{array_type.length}")
          return
        end
      end
      @context.set_type(current_node_id, array_type.element_type_id)
    end

    def visit(node : CallExpr) : Nil
      name = @context.parsed_module.source_file.slice(node.callee)
      if name == "heap_storage"
        analyze_heap_storage(node)
        return
      end
      if name == "heap_free"
        @context.report(node.span, "heap_free must be a standalone statement")
        return
      end
      if name == "copy_memory"
        @context.report(node.span, "copy_memory must be a standalone statement")
        return
      end
      if name == "size_of" || name == "align_of"
        analyze_type_layout_query(node, name)
        return
      end
      if name == "address_of"
        analyze_address_of(node)
        return
      end
      if name == "stack_storage"
        analyze_stack_storage(node)
        return
      end
      if name == "cast"
        analyze_pointer_cast(node)
        return
      end
      if node.type_argument
        @context.report(node.span, "type arguments are not supported for function '#{name}'")
        return
      end

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

    private def analyze_allocation(arguments : NodeRange, span : SourceSpan, operation_name : String) : Nil
      return unless require_unsafe_context(span, operation_name)
      unless arguments.count == 1
        @context.report(span, "#{operation_name} expects 1 argument, got #{arguments.count}")
        return
      end

      expected_type_id = @expected_type_id
      expected_pointer = expected_type_id.try { |type_id| @context.type_table.pointer_type(type_id) }
      expected_value_type_id = expected_pointer.try(&.pointee_type_id)
      if expected_value_type_id.nil? && expected_type_id && @context.type_table.scalar_type(expected_type_id)
        expected_value_type_id = expected_type_id
      end

      value_id = @context.arena.child(arguments, 0)
      value_type_id = analyze_expression(value_id, expected_value_type_id)
      return if @context.diagnostic
      unless value_type_id
        @context.report(@context.arena.node(value_id).span, "#{operation_name} value requires an explicit scalar type")
        return
      end
      unless @context.type_table.scalar_type(value_type_id)
        @context.report(@context.arena.node(value_id).span, "#{operation_name} supports scalar values only")
        return
      end
      if expected_value_type_id && value_type_id != expected_value_type_id
        @context.report(
          @context.arena.node(value_id).span,
          "#{operation_name} value has type #{type_label(value_type_id)}, expected #{type_label(expected_value_type_id)}"
        )
        return
      end

      @context.set_type(current_node_id, @context.type_table.pointer_type_id(value_type_id))
    end

    private def analyze_load(node : LoadExpr) : Nil
      return unless require_unsafe_context(node.span, "load")
      unless node.arguments.count == 1
        @context.report(node.span, "load expects 1 argument, got #{node.arguments.count}")
        return
      end

      address_id = @context.arena.child(node.arguments, 0)
      address_type_id = analyze_expression(address_id)
      return if @context.diagnostic
      pointer_type = address_type_id.try { |type_id| @context.type_table.pointer_type(type_id) }
      unless pointer_type
        actual_type = address_type_id.try { |type_id| type_label(type_id) } || "untyped expression"
        @context.report(@context.arena.node(address_id).span, "load requires ptr[T], got #{actual_type}")
        return
      end

      @context.set_type(current_node_id, pointer_type.pointee_type_id)
    end

    private def check_store_statement(node : StoreStatementNode) : Nil
      unless node.arguments.count == 2
        @context.report(node.span, "store expects 2 arguments, got #{node.arguments.count}")
        return
      end

      address_id = @context.arena.child(node.arguments, 0)
      address_type_id = analyze_expression(address_id)
      return if @context.diagnostic
      pointer_type = address_type_id.try { |type_id| @context.type_table.pointer_type(type_id) }
      unless pointer_type
        actual_type = address_type_id.try { |type_id| type_label(type_id) } || "untyped expression"
        @context.report(@context.arena.node(address_id).span, "store requires ptr[T], got #{actual_type}")
        return
      end

      value_id = @context.arena.child(node.arguments, 1)
      value_type_id = analyze_expression(value_id, pointer_type.pointee_type_id)
      return if @context.diagnostic
      unless value_type_id == pointer_type.pointee_type_id
        actual_type = value_type_id.try { |type_id| type_label(type_id) } || "unknown"
        @context.report(
          @context.arena.node(value_id).span,
          "store value has type #{actual_type}, expected #{type_label(pointer_type.pointee_type_id)}"
        )
      end
    end

    private def check_free_statement(node : FreeStatementNode) : Nil
      unless node.arguments.count == 1
        @context.report(node.span, "free expects 1 argument, got #{node.arguments.count}")
        return
      end

      address_id = @context.arena.child(node.arguments, 0)
      address_type_id = analyze_expression(address_id)
      return if @context.diagnostic
      unless address_type_id.try { |type_id| @context.type_table.pointer_type(type_id) }
        actual_type = address_type_id.try { |type_id| type_label(type_id) } || "untyped expression"
        @context.report(@context.arena.node(address_id).span, "free requires ptr[T], got #{actual_type}")
      end
    end

    private def require_unsafe_context(span : SourceSpan, operation_name : String) : Bool
      return true if @unsafe_depth > 0
      @context.report(span, "unsafe operation '#{operation_name}' requires an unsafe block")
      false
    end

    def visit(node : IdentifierExpr) : Nil
      name = @context.parsed_module.source_file.slice(node.span)
      binding = @current_binding_scope.try(&.resolve(name))
      unless binding
        @context.report(node.span, "unknown name '#{name}'")
        return
      end

      @context.set_symbol(current_node_id, binding.id)
      @context.set_type(current_node_id, binding.type_id)
    end

    def visit(node : IntegerLiteralExpr) : Nil
      expected_type_id = @expected_type_id
      return unless expected_type_id

      if @context.type_table.pointer_type(expected_type_id)
        @context.set_type(current_node_id, @context.type_table.int_type_id)
        return
      end

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

    private def compile_time_constant_expression?(node_id : NodeId) : Bool
      return true if @context.constant_uint_value(node_id)

      case node = @context.arena.node(node_id)
      when IntegerLiteralExpr, BooleanLiteralExpr
        true
      when ArrayLiteralExpr
        node.elements.count.times.all? do |index|
          compile_time_constant_expression?(@context.arena.child(node.elements, index))
        end
      when BinaryExpr
        compile_time_constant_expression?(node.left) && compile_time_constant_expression?(node.right)
      else
        false
      end
    end

    private def constant_uint_value(node_id : NodeId) : UInt128?
      case node = @context.arena.node(node_id)
      when IntegerLiteralExpr
        @context.parsed_module.source_file.slice(node.span).to_u128?
      when BinaryExpr
        left = constant_uint_value(node.left)
        right = constant_uint_value(node.right)
        return nil unless left && right
        left_value = left.to_u64
        right_value = right.to_u64
        case node.operator
        when BinaryOperator::Add
          (left_value &+ right_value).to_u128
        when BinaryOperator::Subtract
          (left_value &- right_value).to_u128
        end
      else
        nil
      end
    end

    private def mutable_array_binding(node_id : NodeId) : SemanticBindingSymbol?
      case node = @context.arena.node(node_id)
      when IdentifierExpr
        name = @context.parsed_module.source_file.slice(node.span)
        binding = @current_binding_scope.try(&.resolve(name))
        unless binding
          @context.report(node.span, "unknown name '#{name}'")
          return nil
        end
        binding
      when IndexExpr
        mutable_array_binding(node.array)
      else
        nil
      end
    end

    private def binding_name(binding : SemanticBindingSymbol) : String
      @context.parsed_module.source_file.slice(binding.name_span)
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
