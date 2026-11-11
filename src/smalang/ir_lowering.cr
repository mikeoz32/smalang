require "./semantic"
require "./ir"
require "./match_core"

module Smalang
  class IrLoweringDiagnostic
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

  class IrLoweringResult
    getter ir_module : IrModule?
    getter diagnostic : IrLoweringDiagnostic?

    def initialize(@ir_module : IrModule?, @diagnostic : IrLoweringDiagnostic?)
    end

    def success? : Bool
      !@ir_module.nil? && @diagnostic.nil?
    end
  end

  class IrLoweringContext
    getter semantic_module : SemanticModule
    getter ir_module : IrModule
    getter diagnostic : IrLoweringDiagnostic?

    @function_ids_by_symbol : Hash(SymbolId, FunctionId)

    def initialize(@semantic_module : SemanticModule)
      @ir_module = IrModule.new
      @function_ids_by_symbol = Hash(SymbolId, FunctionId).new
      @diagnostic = nil
    end

    def parsed_module : ParsedModule
      @semantic_module.parsed_module
    end

    def register_function(symbol_id : SymbolId, function_id : FunctionId) : Nil
      @function_ids_by_symbol[symbol_id] = function_id
    end

    def function_id_for(symbol_id : SymbolId) : FunctionId?
      @function_ids_by_symbol[symbol_id]?
    end

    def type_of(node_id : NodeId) : TypeId?
      type_id = @semantic_module.type_of(node_id)
      return type_id if type_id

      report(node_id, "missing semantic type for expression")
      nil
    end

    def ir_type_for(type_id : TypeId, span : SourceSpan) : IrType?
      type_table = @semantic_module.type_table
      if array_type = type_table.array_type(type_id)
        element_type = ir_type_for(array_type.element_type_id, span)
        return nil unless element_type
        ir_array_type = IrArrayType.new(element_type, array_type.length)
        storage_size = ir_array_type.storage_size
        if array_type.length > Int32::MAX || !storage_size || storage_size > Int32::MAX
          report(span, "array type exceeds x86_64 stack frame or index limits")
          return nil
        end
        return ir_array_type
      end
      if pointer_type = type_table.pointer_type(type_id)
        pointee_type = ir_type_for(pointer_type.pointee_type_id, span)
        return nil unless pointee_type
        return IrPointerType.new(pointee_type)
      end
      return IrType::Isize if type_id == type_table.int_type_id
      return IrType::Usize if type_id == type_table.uint_type_id
      return IrType::Bool if type_id == type_table.bool_type_id
      return IrType::Int8 if type_id == type_table.id_for(AstType::Int8)
      return IrType::UInt8 if type_id == type_table.id_for(AstType::UInt8)
      return IrType::Int16 if type_id == type_table.id_for(AstType::Int16)
      return IrType::UInt16 if type_id == type_table.id_for(AstType::UInt16)
      return IrType::Int32 if type_id == type_table.id_for(AstType::Int32)
      return IrType::UInt32 if type_id == type_table.id_for(AstType::UInt32)
      return IrType::Int64 if type_id == type_table.id_for(AstType::Int64)
      return IrType::UInt64 if type_id == type_table.id_for(AstType::UInt64)

      report(span, "unsupported semantic type id #{type_id}")
      nil
    end

    def source_location(span : SourceSpan) : IrSourceLocation
      source_file = parsed_module.source_file
      IrSourceLocation.new(source_file.name, source_file.position_at(span.start).line)
    end

    def report(node_id : NodeId, description : String) : Nil
      report(parsed_module.arena.node(node_id).span, description)
    end

    def report(span : SourceSpan, description : String) : Nil
      return if @diagnostic
      @diagnostic = IrLoweringDiagnostic.new(parsed_module.source_file, span, description)
    end

    def report_module(description : String) : Nil
      root = parsed_module.arena.node(parsed_module.root_id).as(ModuleNode)
      report(root.span, description)
    end
  end

  abstract class IrLoweringAstVisitor < AstVisitor
    protected getter context : IrLoweringContext

    @current_node_id : NodeId?

    def initialize(@context : IrLoweringContext)
      @current_node_id = nil
    end

    protected def visit_node(node_id : NodeId) : Nil
      previous_node_id = @current_node_id
      @current_node_id = node_id
      @context.parsed_module.arena.node(node_id).accept(self)
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
      @context.report(node.span, "boolean literals are not supported by IR lowering")
    end

    def visit(node : ErrorNode) : Nil
      @context.report(node.span, "cannot lower syntax containing parse errors")
    end
  end

  class MatchCorePatternConverter < SourceMatchPatternVisitor
    @result : MatchPattern?

    def convert(pattern : SourceMatchPatternNode) : MatchPattern
      @result = nil
      pattern.accept(self)
      @result.not_nil!
    end

    def visit(pattern : BooleanMatchPatternNode) : Nil
      @result = BooleanLiteralPattern.new(pattern.value)
    end

    def visit(pattern : WildcardMatchPatternNode) : Nil
      @result = WildcardPattern.new
    end
  end

  class IrFunctionDeclarationPass < IrLoweringAstVisitor
    def run : Nil
      visit_node(@context.parsed_module.root_id)
    end

    def visit(node : ModuleNode) : Nil
      node.functions.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.parsed_module.arena.child(node.functions, index))
      end
    end

    def visit(node : FunctionNode) : Nil
      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.name, "missing semantic symbol for function")
        return
      end

      function_symbol = @context.semantic_module.symbol(symbol_id).as?(SemanticFunctionSymbol)
      unless function_symbol
        @context.report(node.name, "semantic symbol is not a function")
        return
      end

      unless function_symbol.parameter_count == node.parameters.count
        @context.report(node.name, "semantic function parameter count does not match syntax")
        return
      end

      parameter_types = Array(IrType).new(function_symbol.parameter_count)
      function_symbol.parameter_count.times do |index|
        type_id = function_symbol.parameter_type(index)
        unless type_id
          @context.report(node.name, "missing semantic type for function parameter")
          return
        end

        type = @context.ir_type_for(type_id, node.name)
        return unless type
        parameter_types << type
      end

      result_type = @context.ir_type_for(function_symbol.result_type_id, node.name)
      return unless result_type

      name = @context.parsed_module.source_file.slice(node.name)
      function = @context.ir_module.add_function(name, parameter_types, result_type)
      @context.register_function(symbol_id, function.id)
    end
  end

  class IrFunctionBodyPass < IrLoweringAstVisitor
    @binding_values_by_symbol : Hash(SymbolId, ValueId)
    @binding_addresses_by_symbol : Hash(SymbolId, ValueId)
    @current_function : IrFunction?
    @current_block_id : BlockId?
    @expression_value_id : ValueId?

    def initialize(context : IrLoweringContext)
      super(context)
      @binding_values_by_symbol = Hash(SymbolId, ValueId).new
      @binding_addresses_by_symbol = Hash(SymbolId, ValueId).new
      @current_function = nil
      @current_block_id = nil
      @expression_value_id = nil
    end

    def run : Nil
      visit_node(@context.parsed_module.root_id)
    end

    def visit(node : ModuleNode) : Nil
      node.functions.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.parsed_module.arena.child(node.functions, index))
      end
    end

    def visit(node : FunctionNode) : Nil
      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.name, "missing semantic symbol for function")
        return
      end

      function_id = @context.function_id_for(symbol_id)
      unless function_id
        @context.report(node.name, "function was not declared in IR")
        return
      end

      function = @context.ir_module.function(function_id)
      unless function
        @context.report(node.name, "IR function id #{function_id} is invalid")
        return
      end

      parameters = function.parameters
      unless parameters.size == node.parameters.count
        @context.report(node.name, "IR function parameter count does not match syntax")
        return
      end

      @binding_values_by_symbol.clear
      @binding_addresses_by_symbol.clear
      node.parameters.count.times do |index|
        parameter_node_id = @context.parsed_module.arena.child(node.parameters, index)
        parameter_node = @context.parsed_module.arena.node(parameter_node_id).as(ParameterNode)
        parameter_symbol_id = @context.semantic_module.symbol_for(parameter_node_id)
        unless parameter_symbol_id
          @context.report(parameter_node.name, "missing semantic symbol for parameter")
          return
        end

        parameter_symbol = @context.semantic_module.symbol(parameter_symbol_id).as?(SemanticParameterSymbol)
        unless parameter_symbol
          @context.report(parameter_node.name, "semantic symbol is not a parameter")
          return
        end

        parameter_value_id = parameters[index].value_id
        if @context.semantic_module.address_taken?(parameter_symbol_id)
          pointer_type = binding_pointer_type(parameter_symbol_id, parameter_node.name)
          return unless pointer_type
          address_id = function.emit_stack_allocate(function.entry_block_id, parameter_value_id, pointer_type)
          @binding_addresses_by_symbol[parameter_symbol_id] = address_id
        else
          @binding_values_by_symbol[parameter_symbol_id] = parameter_value_id
        end
      end

      @current_function = function
      @current_block_id = function.entry_block_id
      node.statements.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.parsed_module.arena.child(node.statements, index))
      end
      visit_node(node.body)
      @current_block_id = nil
      @current_function = nil
    end

    def visit(node : ReturnNode) : Nil
      value_id = lower_expression(node.value)
      return unless value_id

      function = @current_function
      unless function
        @context.report(node.span, "return is not inside a function")
        return
      end

      function.emit_return(current_block_id, value_id)
    end

    def visit(node : UnsafeBlockNode) : Nil
      node.statements.count.times do |index|
        return if @context.diagnostic
        visit_node(@context.parsed_module.arena.child(node.statements, index))
      end
    end

    def visit(node : CallStatementNode) : Nil
      @context.report(node.span, "expression statements are not supported")
    end

    def visit(node : AllocateExpr) : Nil
      lower_allocation(node)
    end

    def visit(node : StackAllocateExpr) : Nil
      lower_stack_allocation(node)
    end

    def visit(node : PointerOffsetExpr) : Nil
      lower_pointer_offset(node)
    end

    def visit(node : LoadExpr) : Nil
      lower_load(node)
    end

    def visit(node : StoreExpr) : Nil
      @context.report(node.span, "store must be a standalone statement")
    end

    def visit(node : FreeExpr) : Nil
      @context.report(node.span, "free must be a standalone statement")
    end

    def visit(node : StoreStatementNode) : Nil
      address_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      address_id = lower_expression(address_node_id)
      return unless address_id
      address_type_id = @context.type_of(address_node_id)
      return unless address_type_id
      pointer_type = pointer_ir_type(address_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "unsafe operation is not inside a function")
        return
      end

      value_node_id = @context.parsed_module.arena.child(node.arguments, 1)
      value_id = lower_expression(value_node_id)
      return unless value_id
      function.emit_store(current_block_id, address_id, value_id, pointer_type)
    end

    def visit(node : FreeStatementNode) : Nil
      address_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      address_id = lower_expression(address_node_id)
      return unless address_id
      address_type_id = @context.type_of(address_node_id)
      return unless address_type_id
      pointer_type = pointer_ir_type(address_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "unsafe operation is not inside a function")
        return
      end

      function.emit_free(current_block_id, address_id, pointer_type)
    end

    def visit(node : VariableDeclarationNode) : Nil
      value_id = lower_expression(node.initializer)
      return unless value_id

      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.name, "missing semantic binding for local declaration")
        return
      end

      if @context.semantic_module.address_taken?(symbol_id)
        pointer_type = binding_pointer_type(symbol_id, node.name)
        return unless pointer_type
        function = @current_function
        unless function
          @context.report(node.name, "address-taken binding is not inside a function")
          return
        end
        address_id = function.emit_stack_allocate(current_block_id, value_id, pointer_type)
        @binding_addresses_by_symbol[symbol_id] = address_id
      else
        @binding_values_by_symbol[symbol_id] = value_id
      end
    end

    def visit(node : AssignmentNode) : Nil
      target = @context.parsed_module.arena.node(node.target)
      if target.is_a?(IdentifierExpr)
        value_id = lower_expression(node.value)
        return unless value_id
        symbol_id = @context.semantic_module.symbol_for(current_node_id)
        unless symbol_id
          @context.report(target.span, "missing semantic binding for assignment")
          return
        end
        if address_id = @binding_addresses_by_symbol[symbol_id]?
          pointer_type = binding_pointer_type(symbol_id, target.span)
          return unless pointer_type
          function = @current_function
          unless function
            @context.report(target.span, "address-taken assignment is not inside a function")
            return
          end
          function.emit_store(current_block_id, address_id, value_id, pointer_type)
        else
          @binding_values_by_symbol[symbol_id] = value_id
        end
      elsif index = target.as?(IndexExpr)
        value_id = lower_expression(node.value)
        return unless value_id
        updated_array_id = lower_index_assignment(index, value_id)
        return unless updated_array_id
        symbol_id = @context.semantic_module.symbol_for(current_node_id)
        unless symbol_id
          @context.report(target.span, "missing semantic binding for indexed assignment")
          return
        end
        @binding_values_by_symbol[symbol_id] = updated_array_id
      else
        @context.report(target.span, "invalid assignment target")
      end
    end

    def visit(node : MatchExpressionNode) : Nil
      function = @current_function
      unless function
        @context.report(node.span, "match expression is not inside a function")
        return
      end

      scrutinee_id = lower_expression(node.scrutinee)
      return unless scrutinee_id
      source_block_id = current_block_id

      result_type_id = @context.type_of(current_node_id)
      return unless result_type_id
      result_type = @context.ir_type_for(result_type_id, node.span)
      return unless result_type

      join_block_id = function.add_block("match_join_#{function.block_count}")
      clauses = Array(MatchClause).new(node.cases.count)
      node.cases.count.times do |index|
        case_node_id = @context.parsed_module.arena.child(node.cases, index)
        case_node = @context.parsed_module.arena.node(case_node_id).as(MatchCaseNode)
        body_block_id = function.add_block("match_case_#{function.block_count}")
        @current_block_id = body_block_id

        result_value_id = lower_expression(case_node.result)
        return unless result_value_id
        result_block_id = current_block_id
        function.emit_jump(result_block_id, join_block_id)

        source_pattern = @context.parsed_module.arena.node(case_node.pattern).as(SourceMatchPatternNode)
        pattern = MatchCorePatternConverter.new.convert(source_pattern)
        clauses << MatchClause.new([pattern], body_block_id, result_value_id, result_block_id)
      end

      match_expression = MatchExpression.new([scrutinee_id], result_type, clauses)
      begin
        @expression_value_id = MatchLowerer.new.lower(function, source_block_id, join_block_id, match_expression)
        @current_block_id = join_block_id
      rescue failure : MatchLoweringFailure
        @context.report(node.span, failure.message || "invalid Match core expression")
      end
    end

    def visit(node : BinaryExpr) : Nil
      left = lower_expression(node.left)
      return unless left
      right = lower_expression(node.right)
      return unless right

      type_id = @context.type_of(current_node_id)
      return unless type_id
      type = @context.ir_type_for(type_id, node.span)
      return unless type

      function = @current_function
      unless function
        @context.report(node.span, "expression is not inside a function")
        return
      end

      @expression_value_id = case node.operator
                             when BinaryOperator::Add
                               function.emit_add(current_block_id, type, left, right)
                             when BinaryOperator::Subtract
                               function.emit_subtract(current_block_id, type, left, right)
                             end
    end

    def visit(node : ArrayLiteralExpr) : Nil
      function = @current_function
      unless function
        @context.report(node.span, "array literal is not inside a function")
        return
      end
      type_id = @context.type_of(current_node_id)
      return unless type_id
      type = @context.ir_type_for(type_id, node.span).as?(IrArrayType)
      unless type
        @context.report(node.span, "array literal has no IR array type")
        return
      end

      elements = Array(ValueId).new(node.elements.count)
      node.elements.count.times do |index|
        source_element_id = @context.parsed_module.arena.child(node.elements, index)
        element_id = lower_array_literal_element(source_element_id, type.element_type)
        return unless element_id
        elements << element_id
      end
      @expression_value_id = function.emit_array_literal(current_block_id, type, elements)
    end

    def visit(node : IndexExpr) : Nil
      array_id = lower_expression(node.array)
      return unless array_id
      index_id = lower_expression(node.index)
      return unless index_id
      type_id = @context.type_of(node.array)
      return unless type_id
      array_type = @context.ir_type_for(type_id, @context.parsed_module.arena.node(node.array).span).as?(IrArrayType)
      unless array_type
        @context.report(node.span, "indexed expression has no IR array type")
        return
      end
      function = @current_function
      unless function
        @context.report(node.span, "indexing is not inside a function")
        return
      end
      result = emit_array_get(function, array_id, index_id, array_type, node.span)
      @expression_value_id = result
    end

    def visit(node : CallExpr) : Nil
      name = @context.parsed_module.source_file.slice(node.callee)
      if name == "stack_storage"
        lower_stack_storage(node)
        return
      end
      if name == "size_of" || name == "align_of"
        lower_type_layout_query(node)
        return
      end
      if name == "address_of"
        lower_address_of(node)
        return
      end
      if name == "cast"
        lower_pointer_cast(node)
        return
      end

      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.callee, "missing semantic function binding for call")
        return
      end

      function_id = @context.function_id_for(symbol_id)
      unless function_id
        @context.report(node.callee, "called function was not declared in IR")
        return
      end

      target = @context.ir_module.internal_call_target(function_id)
      unless target
        @context.report(node.callee, "IR call target #{function_id} is invalid")
        return
      end

      arguments = Array(ValueId).new(node.arguments.count)
      node.arguments.count.times do |index|
        argument_node_id = @context.parsed_module.arena.child(node.arguments, index)
        argument = lower_expression(argument_node_id)
        return unless argument
        arguments << argument
      end

      function = @current_function
      unless function
        @context.report(node.span, "call is not inside a function")
        return
      end

      normal_block = function.add_block("invoke_normal_#{function.block_count}")
      unwind_block = function.add_block("invoke_unwind_#{function.block_count}")
      result = function.emit_invoke_call(
        current_block_id,
        target,
        arguments,
        normal_block,
        unwind_block,
        @context.source_location(node.span)
      )
      function.emit_resume_exception(unwind_block, result.exception_id)
      @current_block_id = normal_block
      @expression_value_id = result.value_id
    end

    private def lower_allocation(node : AllocateExpr) : Nil
      value_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      value_id = lower_expression(value_node_id)
      return unless value_id

      result_type_id = @context.type_of(current_node_id)
      return unless result_type_id
      pointer_type = pointer_ir_type(result_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "alloc is not inside a function")
        return
      end

      normal_block = function.add_block("allocate_normal_#{function.block_count}")
      unwind_block = function.add_block("allocate_unwind_#{function.block_count}")
      result = function.emit_invoke_allocate(
        current_block_id,
        value_id,
        pointer_type,
        normal_block,
        unwind_block,
        @context.source_location(node.span)
      )
      function.emit_resume_exception(unwind_block, result.exception_id)
      @current_block_id = normal_block
      @expression_value_id = result.value_id
    end

    private def lower_stack_allocation(node : StackAllocateExpr) : Nil
      value_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      value_id = lower_expression(value_node_id)
      return unless value_id

      result_type_id = @context.type_of(current_node_id)
      return unless result_type_id
      pointer_type = pointer_ir_type(result_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "alloc_stack is not inside a function")
        return
      end

      @expression_value_id = function.emit_stack_allocate(current_block_id, value_id, pointer_type)
    end

    private def lower_pointer_offset(node : PointerOffsetExpr) : Nil
      address_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      address_id = lower_expression(address_node_id)
      return unless address_id

      index_node_id = @context.parsed_module.arena.child(node.arguments, 1)
      index_id = lower_expression(index_node_id)
      return unless index_id

      address_type_id = @context.type_of(address_node_id)
      return unless address_type_id
      pointer_type = pointer_ir_type(address_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "offset is not inside a function")
        return
      end

      @expression_value_id = function.emit_pointer_offset(current_block_id, address_id, index_id, pointer_type)
    end

    private def lower_pointer_cast(node : CallExpr) : Nil
      address_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      address_id = lower_expression(address_node_id)
      return unless address_id

      result_type_id = @context.type_of(current_node_id)
      return unless result_type_id
      pointer_type = pointer_ir_type(result_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "cast is not inside a function")
        return
      end

      @expression_value_id = function.emit_pointer_cast(current_block_id, address_id, pointer_type)
    end

    private def lower_stack_storage(node : CallExpr) : Nil
      byte_size_id = @context.parsed_module.arena.child(node.arguments, 0)
      alignment_id = @context.parsed_module.arena.child(node.arguments, 1)
      byte_size = @context.semantic_module.constant_uint_value(byte_size_id)
      alignment = @context.semantic_module.constant_uint_value(alignment_id)
      unless byte_size && alignment
        @context.report(node.span, "missing compile-time stack_storage layout")
        return
      end

      function = @current_function
      unless function
        @context.report(node.span, "stack_storage is not inside a function")
        return
      end

      @expression_value_id = function.emit_stack_storage(current_block_id, byte_size, alignment)
    end

    private def lower_type_layout_query(node : CallExpr) : Nil
      value = @context.semantic_module.constant_uint_value(current_node_id)
      unless value
        @context.report(node.span, "missing compile-time type layout")
        return
      end

      function = @current_function
      unless function
        @context.report(node.span, "type layout query is not inside a function")
        return
      end

      @expression_value_id = function.emit_constant(current_block_id, IrType::Usize, value.to_i128)
    end

    private def lower_address_of(node : CallExpr) : Nil
      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.span, "missing semantic binding for address_of")
        return
      end

      address_id = @binding_addresses_by_symbol[symbol_id]?
      unless address_id
        @context.report(node.span, "address_of binding has no stack storage")
        return
      end

      @expression_value_id = address_id
    end

    private def lower_load(node : LoadExpr) : Nil
      address_node_id = @context.parsed_module.arena.child(node.arguments, 0)
      address_id = lower_expression(address_node_id)
      return unless address_id
      address_type_id = @context.type_of(address_node_id)
      return unless address_type_id
      pointer_type = pointer_ir_type(address_type_id, node.span)
      return unless pointer_type

      function = @current_function
      unless function
        @context.report(node.span, "load is not inside a function")
        return
      end

      @expression_value_id = function.emit_load(current_block_id, address_id, pointer_type)
    end

    private def pointer_ir_type(type_id : TypeId, span : SourceSpan) : IrPointerType?
      @context.ir_type_for(type_id, span).as?(IrPointerType).tap do |pointer_type|
        @context.report(span, "expected a pointer IR type") unless pointer_type
      end
    end

    private def binding_pointer_type(symbol_id : SymbolId, span : SourceSpan) : IrPointerType?
      binding = @context.semantic_module.symbol(symbol_id).as?(SemanticBindingSymbol)
      unless binding
        @context.report(span, "address-taken symbol is not a binding")
        return nil
      end

      pointee_type = @context.ir_type_for(binding.type_id, span)
      return nil unless pointee_type
      IrPointerType.new(pointee_type)
    end

    def visit(node : IdentifierExpr) : Nil
      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.span, "missing semantic binding for identifier")
        return
      end

      if address_id = @binding_addresses_by_symbol[symbol_id]?
        pointer_type = binding_pointer_type(symbol_id, node.span)
        return unless pointer_type
        function = @current_function
        unless function
          @context.report(node.span, "address-taken binding read is not inside a function")
          return
        end
        @expression_value_id = function.emit_load(current_block_id, address_id, pointer_type)
      else
        value_id = @binding_values_by_symbol[symbol_id]?
        unless value_id
          @context.report(node.span, "identifier has no corresponding IR binding value")
          return
        end

        @expression_value_id = value_id
      end
    end

    def visit(node : IntegerLiteralExpr) : Nil
      text = @context.parsed_module.source_file.slice(node.span)
      value = text.to_i128?
      unless value
        @context.report(node.span, "integer literal cannot be represented by the current IR")
        return
      end

      type_id = @context.type_of(current_node_id)
      return unless type_id
      type = @context.ir_type_for(type_id, node.span)
      return unless type

      function = @current_function
      unless function
        @context.report(node.span, "integer literal is not inside a function")
        return
      end

      @expression_value_id = function.emit_constant(current_block_id, type, value)
    end

    def visit(node : BooleanLiteralExpr) : Nil
      type_id = @context.type_of(current_node_id)
      return unless type_id
      type = @context.ir_type_for(type_id, node.span)
      return unless type

      function = @current_function
      unless function
        @context.report(node.span, "boolean literal is not inside a function")
        return
      end

      value = node.value ? 1_i128 : 0_i128
      @expression_value_id = function.emit_constant(current_block_id, type, value)
    end

    private def lower_expression(node_id : NodeId) : ValueId?
      @expression_value_id = nil
      visit_node(node_id)
      @expression_value_id
    end

    private def lower_index_assignment(target : IndexExpr, value_id : ValueId) : ValueId?
      array_node = @context.parsed_module.arena.node(target.array)
      array_id = lower_expression(target.array)
      return nil unless array_id
      index_id = lower_expression(target.index)
      return nil unless index_id
      array_type_id = @context.type_of(target.array)
      return nil unless array_type_id
      array_type = @context.ir_type_for(array_type_id, array_node.span).as?(IrArrayType)
      unless array_type
        @context.report(target.span, "indexed assignment base has no IR array type")
        return nil
      end
      function = @current_function
      unless function
        @context.report(target.span, "indexed assignment is not inside a function")
        return nil
      end

      updated = emit_array_set(function, array_id, index_id, value_id, array_type, target.span)
      return nil unless updated
      if parent = array_node.as?(IndexExpr)
        lower_index_assignment(parent, updated)
      else
        updated
      end
    end

    private def lower_array_literal_element(node_id : NodeId, type : IrType) : ValueId?
      return lower_expression(node_id) if type.is_a?(IrArrayType)
      semantic_type_id = @context.type_of(node_id)
      return nil unless semantic_type_id
      ir_type = @context.ir_type_for(semantic_type_id, @context.parsed_module.arena.node(node_id).span)
      return nil unless ir_type
      value = constant_literal_value(node_id, type)
      unless value
        @context.report(node_id, "array literal element is not a supported compile-time constant")
        return nil
      end
      function = @current_function
      unless function
        @context.report(node_id, "array literal is not inside a function")
        return nil
      end
      function.emit_constant(current_block_id, ir_type, value)
    end

    private def constant_literal_value(node_id : NodeId, type : IrType) : Int128?
      bits = constant_literal_bits(node_id, type)
      return nil unless bits
      return bits.to_i128 unless type.integer?

      width = integer_bit_width(type)
      mask = width == 64 ? UInt64::MAX : (1_u64 << width) - 1
      if type.signed? && (bits & (1_u64 << (width - 1))) != 0
        bits.to_i128 - (1_i128 << width)
      else
        bits.to_i128 & mask.to_i128
      end
    end

    private def constant_literal_bits(node_id : NodeId, type : IrType) : UInt64?
      case node = @context.parsed_module.arena.node(node_id)
      when IntegerLiteralExpr
        @context.parsed_module.source_file.slice(node.span).to_u64?
      when BooleanLiteralExpr
        node.value ? 1_u64 : 0_u64
      when BinaryExpr
        left = constant_literal_bits(node.left, type)
        right = constant_literal_bits(node.right, type)
        return nil unless left && right
        bits = case node.operator
               when BinaryOperator::Add
                 left &+ right
               when BinaryOperator::Subtract
                 left &- right
               else
                 return nil
               end
        width = integer_bit_width(type)
        mask = width == 64 ? UInt64::MAX : (1_u64 << width) - 1
        bits & mask
      else
        nil
      end
    end

    private def integer_bit_width(type : IrType) : Int32
      type.fixed_bit_width || 64
    end

    private def emit_array_get(function : IrFunction, array_id : ValueId, index_id : ValueId, type : IrArrayType, span : SourceSpan) : ValueId?
      normal_block = function.add_block("array_get_normal_#{function.block_count}")
      unwind_block = function.add_block("array_get_unwind_#{function.block_count}")
      result = function.emit_invoke_array_get(
        current_block_id,
        array_id,
        index_id,
        type,
        normal_block,
        unwind_block,
        @context.source_location(span)
      )
      function.emit_resume_exception(unwind_block, result.exception_id)
      @current_block_id = normal_block
      result.value_id
    end

    private def emit_array_set(
      function : IrFunction,
      array_id : ValueId,
      index_id : ValueId,
      value_id : ValueId,
      type : IrArrayType,
      span : SourceSpan,
    ) : ValueId?
      normal_block = function.add_block("array_set_normal_#{function.block_count}")
      unwind_block = function.add_block("array_set_unwind_#{function.block_count}")
      result = function.emit_invoke_array_set(
        current_block_id,
        array_id,
        index_id,
        value_id,
        type,
        normal_block,
        unwind_block,
        @context.source_location(span)
      )
      function.emit_resume_exception(unwind_block, result.exception_id)
      @current_block_id = normal_block
      result.value_id
    end

    private def current_block_id : BlockId
      @current_block_id.not_nil!
    end
  end

  class IrLowerer
    def initialize(@semantic_module : SemanticModule)
    end

    def lower : IrLoweringResult
      context = IrLoweringContext.new(@semantic_module)
      IrFunctionDeclarationPass.new(context).run
      return failed_result(context) if context.diagnostic

      IrFunctionBodyPass.new(context).run
      return failed_result(context) if context.diagnostic

      diagnostics = context.ir_module.verify
      unless diagnostics.empty?
        context.report_module("generated invalid IR: #{diagnostics.join("; ")}")
        return failed_result(context)
      end

      IrLoweringResult.new(context.ir_module, nil)
    end

    private def failed_result(context : IrLoweringContext) : IrLoweringResult
      IrLoweringResult.new(nil, context.diagnostic)
    end
  end
end
