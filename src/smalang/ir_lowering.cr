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
    @current_function : IrFunction?
    @current_block_id : BlockId?
    @expression_value_id : ValueId?

    def initialize(context : IrLoweringContext)
      super(context)
      @binding_values_by_symbol = Hash(SymbolId, ValueId).new
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
      node.parameters.count.times do |index|
        parameter_node_id = @context.parsed_module.arena.child(node.parameters, index)
        parameter_symbol_id = @context.semantic_module.symbol_for(parameter_node_id)
        unless parameter_symbol_id
          parameter_node = @context.parsed_module.arena.node(parameter_node_id).as(ParameterNode)
          @context.report(parameter_node.name, "missing semantic symbol for parameter")
          return
        end

        parameter_symbol = @context.semantic_module.symbol(parameter_symbol_id).as?(SemanticParameterSymbol)
        unless parameter_symbol
          parameter_node = @context.parsed_module.arena.node(parameter_node_id).as(ParameterNode)
          @context.report(parameter_node.name, "semantic symbol is not a parameter")
          return
        end

        @binding_values_by_symbol[parameter_symbol_id] = parameters[index].value_id
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

    def visit(node : VariableDeclarationNode) : Nil
      value_id = lower_expression(node.initializer)
      return unless value_id

      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.name, "missing semantic binding for local declaration")
        return
      end

      @binding_values_by_symbol[symbol_id] = value_id
    end

    def visit(node : AssignmentNode) : Nil
      value_id = lower_expression(node.value)
      return unless value_id

      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.target, "missing semantic binding for assignment")
        return
      end

      @binding_values_by_symbol[symbol_id] = value_id
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

    def visit(node : CallExpr) : Nil
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

    def visit(node : IdentifierExpr) : Nil
      symbol_id = @context.semantic_module.symbol_for(current_node_id)
      unless symbol_id
        @context.report(node.span, "missing semantic binding for identifier")
        return
      end

      value_id = @binding_values_by_symbol[symbol_id]?
      unless value_id
        @context.report(node.span, "identifier has no corresponding IR binding value")
        return
      end

      @expression_value_id = value_id
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
