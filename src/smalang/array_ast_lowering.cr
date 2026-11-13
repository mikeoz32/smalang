require "./ast_pass"
require "set"

module Smalang
  class ArrayAstLowerer
    BYTE_TYPE = AstType::UInt8

    @source : ParsedModule
    @semantic : SemanticModule
    @arena : AstArena
    @type_arena : AstTypeArena
    @generated_name_index : Int32
    @failure : Tuple(SourceSpan, String)?
    @source_names : Set(String)
    @current_array_result_type : TypeId?
    @current_result_storage_name : AstName?

    def initialize(@semantic : SemanticModule)
      @source = @semantic.parsed_module
      @arena = AstArena.new(@source.arena.size)
      @type_arena = AstTypeArena.new(@source.source_file.source.bytesize.to_i32)
      @generated_name_index = 0
      @failure = nil
      @source_names = Set(String).new
      @current_array_result_type = nil
      @current_result_storage_name = nil
    end

    def lower : AstPassResult
      copy_source_types
      collect_source_names
      root_id = rewrite_node(@source.root_id)
      if failure = @failure
        return AstPassResult.failure(failure[0], failure[1])
      end
      parsed_module = ParsedModule.new(@source.source_file, @arena, @type_arena, root_id)
      AstPassResult.success(parsed_module)
    end

    private def rewrite_node(node_id : NodeId) : NodeId
      case node = @source.arena.node(node_id)
      when ModuleNode
        function_ids = Array(NodeId).new(node.functions.count)
        node.functions.count.times do |index|
          function_ids << rewrite_node(@source.arena.child(node.functions, index))
        end
        @arena.add(ModuleNode.new(node.span, @arena.append_children(function_ids)))
      when FunctionNode
        rewrite_function(node_id, node)
      else
        fail_at(node.span, "array lowering expected a module or function")
        @arena.add(ErrorNode.new(node.span))
      end
    end

    private def copy_source_types : Nil
      @source.type_arena.size.times do |type_id|
        syntax = @source.type_arena.type(type_id)
        case syntax
        when ScalarTypeSyntax
          @type_arena.add(ScalarTypeSyntax.new(syntax.span, syntax.type))
        when ArrayTypeSyntax
          @type_arena.add(ArrayTypeSyntax.new(syntax.span, syntax.element_type_id, syntax.length))
        when PointerTypeSyntax
          @type_arena.add(PointerTypeSyntax.new(syntax.span, syntax.pointee_type_id))
        end
      end
    end

    private def collect_source_names : Nil
      tokens = Lexer.new.tokenize(@source.source_file.source, @source.source_file.name)
      tokens.tokens.each do |token|
        next unless token.kind == TokenKind::Identifier
        @source_names.add(@source.source_file.slice(token.span))
      end
    end

    private def rewrite_function(node_id : NodeId, node : FunctionNode) : NodeId
      function_result_type = source_type_id(node.return_type)
      array_result_type = array_type?(function_result_type) ? function_result_type : nil
      previous_result_type = @current_array_result_type
      previous_result_name = @current_result_storage_name
      @current_array_result_type = array_result_type
      @current_result_storage_name = generated_name(node.name.span, "return_storage") if array_result_type

      parameter_ids = Array(NodeId).new(node.parameters.count + (array_result_type ? 1 : 0))
      if result_name = @current_result_storage_name
        parameter_ids << generated_parameter(result_name, byte_pointer_type(node.name.span), BindingMutability::Immutable, node.name.span)
      end
      node.parameters.count.times do |index|
        parameter_id = @source.arena.child(node.parameters, index)
        parameter = @source.arena.node(parameter_id).as(ParameterNode)
        parameter_ids << rewrite_parameter(parameter)
      end

      statement_ids = Array(NodeId).new(node.statements.count)
      node.statements.count.times do |index|
        statement_ids.concat(rewrite_statement(@source.arena.child(node.statements, index)))
        return restore_failed_function(node, previous_result_type, previous_result_name) if @failure
      end
      body_ids = rewrite_statement(node.body)
      statement_ids.concat(body_ids)

      rewritten = FunctionNode.new(
        node.span,
        node.name,
        lower_type(node.return_type),
        @arena.append_children(parameter_ids),
        @arena.append_children(statement_ids[0...-1]),
        statement_ids.last? || @arena.add(ErrorNode.new(node.span))
      )
      result = @arena.add(rewritten)
      @current_array_result_type = previous_result_type
      @current_result_storage_name = previous_result_name
      result
    end

    private def restore_failed_function(node : FunctionNode, previous_type : TypeId?, previous_name : AstName?) : NodeId
      @current_array_result_type = previous_type
      @current_result_storage_name = previous_name
      @arena.add(ErrorNode.new(node.span))
    end

    private def rewrite_parameter(node : ParameterNode) : NodeId
      @arena.add(ParameterNode.new(node.span, node.name, lower_type(node.type), node.mutability))
    end

    private def rewrite_statement(node_id : NodeId) : Array(NodeId)
      return [] of NodeId if @failure
      case node = @source.arena.node(node_id)
      when VariableDeclarationNode
        [rewrite_variable_declaration(node)]
      when AssignmentNode
        rewrite_assignment(node_id, node)
      when ReturnNode
        rewrite_return(node)
      when UnsafeBlockNode
        inner = Array(NodeId).new(node.statements.count)
        node.statements.count.times do |index|
          inner.concat(rewrite_statement(@source.arena.child(node.statements, index)))
        end
        [@arena.add(UnsafeBlockNode.new(node.span, @arena.append_children(inner)))]
      when CallStatementNode
        call = rewrite_expression(node.call)
        [@arena.add(CallStatementNode.new(node.span, call))]
      when StoreStatementNode
        [rewrite_store_statement(node)]
      when FreeStatementNode
        [rewrite_free_statement(node)]
      else
        fail_at(node.span, "unsupported statement in array lowering")
        [] of NodeId
      end
    end

    private def rewrite_variable_declaration(node : VariableDeclarationNode) : NodeId
      type_id = source_type_id(node.type)
      if array_type?(type_id)
        initializer = materialize_array_value(node.initializer, type_id, node.span)
        @arena.add(VariableDeclarationNode.new(node.span, node.name, byte_pointer_type(node.span), node.mutability, initializer))
      else
        @arena.add(VariableDeclarationNode.new(node.span, node.name, lower_type(node.type), node.mutability, rewrite_expression(node.initializer)))
      end
    end

    private def rewrite_assignment(node_id : NodeId, node : AssignmentNode) : Array(NodeId)
      target = @source.arena.node(node.target)
      target_type = assignment_target_type(node_id, node.target)
      if target.is_a?(IdentifierExpr) && target_type && array_type?(target_type)
        span = node.span
        source_name = generated_name(span, "assignment_value")
        source_type = byte_pointer_type(span)
        source_value = materialize_array_value(node.value, target_type, span)
        source_declaration = generated_declaration(source_name, source_type, source_value, span)
        copy = copy_memory_statement(
          identifier(target.name, target.span),
          identifier(source_name, span),
          storage_size(target_type, span),
          span
        )
        return [source_declaration, unsafe_block([copy], span)]
      end

      if target.is_a?(IndexExpr)
        return rewrite_index_assignment(node, target)
      end

      rewritten_target = rewrite_expression(node.target)
      rewritten_value = rewrite_expression(node.value)
      [@arena.add(AssignmentNode.new(node.span, rewritten_target, rewritten_value))]
    end

    private def assignment_target_type(assignment_id : NodeId, target_id : NodeId) : TypeId?
      target = @source.arena.node(target_id)
      return @semantic.type_of(target_id) unless target.is_a?(IdentifierExpr)

      symbol_id = @semantic.symbol_for(assignment_id)
      symbol = symbol_id.try { |id| @semantic.symbol(id).as?(SemanticBindingSymbol) }
      symbol.try(&.type_id) || @semantic.type_of(target_id)
    end

    private def rewrite_return(node : ReturnNode) : Array(NodeId)
      result_type = @current_array_result_type
      result_name = @current_result_storage_name
      return [@arena.add(ReturnNode.new(node.span, rewrite_expression(node.value)))] unless result_type && result_name

      source_name = generated_name(node.span, "return_value")
      source_value = materialize_array_value(node.value, result_type, node.span)
      source_declaration = generated_declaration(source_name, byte_pointer_type(node.span), source_value, node.span)
      copy = copy_memory_statement(
        identifier(result_name, node.span),
        identifier(source_name, node.span),
        storage_size(result_type, node.span),
        node.span
      )
      result = @arena.add(ReturnNode.new(node.span, identifier(result_name, node.span)))
      [source_declaration, unsafe_block([copy], node.span), result]
    end

    private def rewrite_index_assignment(node : AssignmentNode, target : IndexExpr) : Array(NodeId)
      value_type = @semantic.type_of(node.target)
      return [] of NodeId unless value_type
      prefix = Array(NodeId).new
      value_name = generated_name(node.span, "indexed_value")
      value_type_syntax = array_type?(value_type) ? byte_pointer_type(node.span) : type_syntax(value_type, node.span)
      value_expression = if array_type?(value_type)
                           materialize_array_value(node.value, value_type, node.span)
                         else
                           rewrite_expression(node.value)
                         end
      prefix << generated_declaration(value_name, value_type_syntax, value_expression, node.span)

      root_id, index_ids = flattened_indices(node.target)
      base_name = generated_name(@source.arena.node(root_id).span, "indexed_base")
      prefix << generated_declaration(base_name, byte_pointer_type(node.span), rewrite_expression(root_id), @source.arena.node(root_id).span)
      address = identifier(base_name, node.span)
      current_type = @semantic.type_of(root_id)
      return [] of NodeId unless current_type

      index_ids.each do |index_id|
        source_index = @source.arena.node(index_id)
        array_type = @semantic.type_table.array_type(current_type)
        unless array_type
          fail_at(source_index.span, "indexed assignment base is not an array")
          return [] of NodeId
        end
        index_name = generated_name(source_index.span, "array_index")
        prefix << generated_declaration(index_name, scalar_type_syntax(AstType::UInt, source_index.span), rewrite_expression(index_id), source_index.span)
        prefix << bounds_guard(identifier(index_name, source_index.span), array_type.length, source_index.span)
        stride = storage_size(array_type.element_type_id, source_index.span)
        address = pointer_offset(address, scaled_index(index_name, stride, source_index.span), source_index.span)
        current_type = array_type.element_type_id
      end

      destination_type = @semantic.type_of(node.target)
      return [] of NodeId unless destination_type
      operation = if array_type?(destination_type)
                    copy_memory_statement(address, identifier(value_name, node.span), storage_size(destination_type, node.span), node.span)
                  else
                    store_statement(cast_pointer(address, destination_type, node.span), identifier(value_name, node.span), node.span)
                  end
      prefix << unsafe_block([operation], node.span)
      prefix
    end

    private def rewrite_store_statement(node : StoreStatementNode) : NodeId
      arguments = rewrite_arguments(node.arguments)
      @arena.add(StoreStatementNode.new(node.span, @arena.append_children(arguments)))
    end

    private def rewrite_free_statement(node : FreeStatementNode) : NodeId
      arguments = rewrite_arguments(node.arguments)
      @arena.add(FreeStatementNode.new(node.span, @arena.append_children(arguments)))
    end

    private def rewrite_expression(node_id : NodeId) : NodeId
      return @arena.add(ErrorNode.new(@source.arena.node(node_id).span)) if @failure
      node = @source.arena.node(node_id)
      case node
      when IdentifierExpr
        @arena.add(IdentifierExpr.new(node.span, node.name))
      when IntegerLiteralExpr
        @arena.add(node.synthetic_value ? IntegerLiteralExpr.new(node.span, node.synthetic_value.not_nil!) : IntegerLiteralExpr.new(node.span))
      when BooleanLiteralExpr
        @arena.add(BooleanLiteralExpr.new(node.span, node.value))
      when BinaryExpr
        left = rewrite_expression(node.left)
        right = rewrite_expression(node.right)
        @arena.add(BinaryExpr.new(node.span, node.operator, left, right))
      when ArrayLiteralExpr
        rewrite_array_literal(node_id, node)
      when IndexExpr
        rewrite_index_read(node_id, node)
      when CallExpr
        rewrite_call(node_id, node)
      when MatchExpressionNode
        rewrite_match_expression(node)
      when TypeOperandExpr
        @arena.add(TypeOperandExpr.new(node.span, node.type_id))
      when SequenceExpr
        statements = Array(NodeId).new(node.statements.count)
        node.statements.count.times { |index| statements.concat(rewrite_statement(@source.arena.child(node.statements, index))) }
        value = rewrite_expression(node.value)
        @arena.add(SequenceExpr.new(node.span, @arena.append_children(statements), value))
      when IntegerCompareExpr
        left = rewrite_expression(node.left)
        right = rewrite_expression(node.right)
        @arena.add(IntegerCompareExpr.new(node.span, node.operator, left, right))
      when UnsafeExpr
        @arena.add(UnsafeExpr.new(node.span, rewrite_expression(node.value)))
      when AllocateExpr
        @arena.add(AllocateExpr.new(node.span, @arena.append_children(rewrite_arguments(node.arguments))))
      when StackAllocateExpr
        @arena.add(StackAllocateExpr.new(node.span, @arena.append_children(rewrite_arguments(node.arguments))))
      when PointerOffsetExpr
        @arena.add(PointerOffsetExpr.new(node.span, @arena.append_children(rewrite_arguments(node.arguments))))
      when LoadExpr
        @arena.add(LoadExpr.new(node.span, @arena.append_children(rewrite_arguments(node.arguments))))
      when StoreExpr
        @arena.add(StoreExpr.new(node.span, @arena.append_children(rewrite_arguments(node.arguments))))
      when FreeExpr
        @arena.add(FreeExpr.new(node.span, @arena.append_children(rewrite_arguments(node.arguments))))
      else
        fail_at(node.span, "unsupported expression in array lowering")
        @arena.add(ErrorNode.new(node.span))
      end
    end

    private def rewrite_array_literal(node_id : NodeId, node : ArrayLiteralExpr) : NodeId
      type_id = @semantic.type_of(node_id)
      return @arena.add(ErrorNode.new(node.span)) unless type_id
      storage_name = generated_name(node.span, "array_literal")
      storage = identifier(storage_name, node.span)
      statements = [generated_storage_declaration(storage_name, type_id, node.span)] of NodeId
      emit_literal_elements(node_id, type_id, storage_name, 0_u128, node.span, statements)
      sequence_expression(node.span, [unsafe_block(statements, node.span)], storage)
    end

    private def emit_literal_elements(node_id : NodeId, type_id : TypeId, storage_name : AstName, base_offset : UInt128, span : SourceSpan, statements : Array(NodeId)) : Nil
      literal = @source.arena.node(node_id).as?(ArrayLiteralExpr)
      array_type = @semantic.type_table.array_type(type_id)
      unless literal && array_type
        fail_at(span, "array literal type information is missing")
        return
      end
      stride = storage_size(array_type.element_type_id, span)
      literal.elements.count.times do |index|
        element_id = @source.arena.child(literal.elements, index)
        element_offset = base_offset + stride * index.to_u128
        if nested_type = @semantic.type_table.array_type(array_type.element_type_id)
          emit_literal_elements(element_id, array_type.element_type_id, storage_name, element_offset, @source.arena.node(element_id).span, statements)
        else
          address = pointer_offset(identifier(storage_name, span), literal_uint(element_offset, span), span)
          target_type = array_type.element_type_id
          statements << store_statement(cast_pointer(address, target_type, span), fold_array_constant(element_id, target_type), span)
        end
      end
    end

    private def rewrite_index_read(node_id : NodeId, node : IndexExpr) : NodeId
      root_id, index_ids = flattened_indices(node_id)
      root_type = @semantic.type_of(root_id)
      result_type = @semantic.type_of(node_id)
      return @arena.add(ErrorNode.new(node.span)) unless root_type && result_type

      prefix = Array(NodeId).new
      base_name = generated_name(@source.arena.node(root_id).span, "indexed_base")
      prefix << generated_declaration(base_name, byte_pointer_type(node.span), rewrite_expression(root_id), @source.arena.node(root_id).span)
      address = identifier(base_name, node.span)
      current_type = root_type
      index_ids.each do |index_id|
        source_index = @source.arena.node(index_id)
        array_type = @semantic.type_table.array_type(current_type)
        unless array_type
          fail_at(source_index.span, "indexed expression base is not an array")
          return @arena.add(ErrorNode.new(node.span))
        end
        index_name = generated_name(source_index.span, "array_index")
        prefix << generated_declaration(index_name, scalar_type_syntax(AstType::UInt, source_index.span), rewrite_expression(index_id), source_index.span)
        prefix << bounds_guard(identifier(index_name, source_index.span), array_type.length, source_index.span)
        address = pointer_offset(address, scaled_index(index_name, storage_size(array_type.element_type_id, source_index.span), source_index.span), source_index.span)
        current_type = array_type.element_type_id
      end

      if array_type?(result_type)
        result_name = generated_name(node.span, "indexed_copy")
        copy = copy_memory_statement(identifier(result_name, node.span), address, storage_size(result_type, node.span), node.span)
        prefix << unsafe_block([generated_storage_declaration(result_name, result_type, node.span), copy], node.span)
        sequence_expression(node.span, prefix, identifier(result_name, node.span))
      else
        value = @arena.add(UnsafeExpr.new(node.span, load_expression(cast_pointer(address, result_type, node.span), node.span)))
        sequence_expression(node.span, prefix, value)
      end
    end

    private def rewrite_call(node_id : NodeId, node : CallExpr) : NodeId
      name = @source.source_file.slice(node.callee)
      if name == "size_of" || name == "align_of"
        arguments = Array(NodeId).new(node.arguments.count)
        node.arguments.count.times do |index|
          arguments << rewrite_type_operand(@source.arena.child(node.arguments, index))
        end
        return @arena.add(CallExpr.new(node.span, node.callee, @arena.append_children(arguments), node.type_argument))
      end
      symbol_id = @semantic.symbol_for(node_id)
      function_symbol = symbol_id.try { |id| @semantic.symbol(id).as?(SemanticFunctionSymbol) }
      result_type = @semantic.type_of(node_id)
      array_result = result_type && array_type?(result_type) ? result_type : nil
      prefix = Array(NodeId).new
      result_storage_name = nil.as(AstName?)
      if array_result
        result_storage_name = generated_name(node.span, "call_result")
        prefix << unsafe_block([generated_storage_declaration(result_storage_name.not_nil!, array_result.not_nil!, node.span)], node.span)
      end

      arguments = Array(NodeId).new(node.arguments.count + (array_result ? 1 : 0))
      arguments << identifier(result_storage_name.not_nil!, node.span) if result_storage_name
      node.arguments.count.times do |index|
        argument_id = @source.arena.child(node.arguments, index)
        parameter_type = function_symbol.try(&.parameter_type(index))
        if parameter_type && array_type?(parameter_type)
          arguments << materialize_array_value(argument_id, parameter_type, @source.arena.node(argument_id).span)
        else
          arguments << rewrite_expression(argument_id)
        end
      end
      call = @arena.add(CallExpr.new(node.span, node.callee, @arena.append_children(arguments), node.type_argument))
      return call if prefix.empty?
      sequence_expression(node.span, prefix, call)
    end

    private def rewrite_match_expression(node : MatchExpressionNode) : NodeId
      scrutinee = rewrite_expression(node.scrutinee)
      cases = Array(NodeId).new(node.cases.count)
      node.cases.count.times do |index|
        case_id = @source.arena.child(node.cases, index)
        match_case = @source.arena.node(case_id).as(MatchCaseNode)
        pattern = rewrite_pattern(match_case.pattern)
        result = rewrite_expression(match_case.result)
        cases << @arena.add(MatchCaseNode.new(match_case.span, pattern, result))
      end
      @arena.add(MatchExpressionNode.new(node.span, scrutinee, @arena.append_children(cases)))
    end

    private def rewrite_pattern(node_id : NodeId) : NodeId
      case pattern = @source.arena.node(node_id)
      when BooleanMatchPatternNode
        @arena.add(BooleanMatchPatternNode.new(pattern.span, pattern.value))
      when WildcardMatchPatternNode
        @arena.add(WildcardMatchPatternNode.new(pattern.span))
      else
        fail_at(pattern.span, "unsupported match pattern in array lowering")
        @arena.add(ErrorNode.new(pattern.span))
      end
    end

    private def materialize_array_value(expression_id : NodeId, type_id : TypeId, span : SourceSpan) : NodeId
      source_name = generated_name(span, "array_source")
      destination_name = generated_name(span, "array_value")
      source_declaration = generated_declaration(source_name, byte_pointer_type(span), rewrite_expression(expression_id), span)
      destination_declaration = generated_storage_declaration(destination_name, type_id, span)
      copy = copy_memory_statement(
        identifier(destination_name, span),
        identifier(source_name, span),
        storage_size(type_id, span),
        span
      )
      sequence_expression(span, [source_declaration, unsafe_block([destination_declaration, copy], span)], identifier(destination_name, span))
    end

    private def generated_storage_declaration(name : AstName, array_type_id : TypeId, span : SourceSpan) : NodeId
      size = storage_size(array_type_id, span)
      size = 1_u64 if size.zero?
      alignment = storage_alignment(array_type_id, span)
      size_expression = literal_uint(size, span)
      alignment_expression = literal_uint(alignment, span)
      arguments = @arena.append_children([size_expression, alignment_expression])
      allocation = @arena.add(CallExpr.new(span, generated_name(span, "stack_storage", false), arguments))
      generated_declaration(name, byte_pointer_type(span), allocation, span)
    end

    private def generated_declaration(name : AstName, type_id : AstTypeId, initializer : NodeId, span : SourceSpan) : NodeId
      @arena.add(VariableDeclarationNode.new(span, name, type_id, BindingMutability::Immutable, initializer))
    end

    private def generated_parameter(name : AstName, type_id : AstTypeId, mutability : BindingMutability, span : SourceSpan) : NodeId
      @arena.add(ParameterNode.new(span, name, type_id, mutability))
    end

    private def unsafe_block(statements : Array(NodeId), span : SourceSpan) : NodeId
      @arena.add(UnsafeBlockNode.new(span, @arena.append_children(statements)))
    end

    private def sequence_expression(span : SourceSpan, statements : Array(NodeId), value : NodeId) : NodeId
      return value if statements.empty?
      @arena.add(SequenceExpr.new(span, @arena.append_children(statements), value))
    end

    private def copy_memory_statement(destination : NodeId, source : NodeId, byte_count : UInt64, span : SourceSpan) : NodeId
      arguments = @arena.append_children([destination, source, literal_uint(byte_count, span)])
      call = @arena.add(CallExpr.new(span, generated_name(span, "copy_memory", false), arguments))
      @arena.add(CallStatementNode.new(span, call))
    end

    private def store_statement(address : NodeId, value : NodeId, span : SourceSpan) : NodeId
      @arena.add(StoreStatementNode.new(span, @arena.append_children([address, value])))
    end

    private def load_expression(address : NodeId, span : SourceSpan) : NodeId
      @arena.add(LoadExpr.new(span, @arena.append_children([address])))
    end

    private def cast_pointer(address : NodeId, pointee_type_id : TypeId, span : SourceSpan) : NodeId
      target_type = type_syntax(pointee_type_id, span)
      @arena.add(CallExpr.new(span, generated_name(span, "cast", false), @arena.append_children([address]), target_type))
    end

    private def pointer_offset(address : NodeId, byte_offset : NodeId, span : SourceSpan) : NodeId
      @arena.add(PointerOffsetExpr.new(span, @arena.append_children([address, byte_offset])))
    end

    private def scaled_index(index_name : AstName, stride : UInt64, span : SourceSpan) : NodeId
      index = identifier(index_name, span)
      return index if stride == 1
      scale = literal_uint(stride, span)
      @arena.add(BinaryExpr.new(span, BinaryOperator::Multiply, index, scale))
    end

    private def bounds_guard(index : NodeId, length : UInt128, span : SourceSpan) : NodeId
      length_value = uint64_value(length, span)
      limit = literal_uint(length_value, span)
      condition = @arena.add(IntegerCompareExpr.new(span, IntegerComparisonOperator::LessThan, index, limit))
      @arena.add(RuntimeGuardStatementNode.new(span, condition, RuntimeExceptionKind::IndexOutOfBounds))
    end

    private def flattened_indices(node_id : NodeId) : Tuple(NodeId, Array(NodeId))
      indices = Array(NodeId).new
      current_id = node_id
      while index = @source.arena.node(current_id).as?(IndexExpr)
        indices << index.index
        current_id = index.array
      end
      indices.reverse!
      {current_id, indices}
    end

    private def rewrite_arguments(range : NodeRange) : Array(NodeId)
      arguments = Array(NodeId).new(range.count)
      range.count.times do |index|
        arguments << rewrite_expression(@source.arena.child(range, index))
      end
      arguments
    end

    private def rewrite_type_operand(node_id : NodeId) : NodeId
      case node = @source.arena.node(node_id)
      when IdentifierExpr
        @arena.add(IdentifierExpr.new(node.span, node.name))
      when IndexExpr
        array = rewrite_type_operand(node.array)
        index = rewrite_type_operand(node.index)
        @arena.add(IndexExpr.new(node.span, array, index))
      when TypeOperandExpr
        @arena.add(TypeOperandExpr.new(node.span, node.type_id))
      else
        rewrite_expression(node_id)
      end
    end

    private def fold_array_constant(node_id : NodeId, type_id : TypeId) : NodeId
      node = @source.arena.node(node_id)
      return @arena.add(BooleanLiteralExpr.new(node.span, node.value)) if node.is_a?(BooleanLiteralExpr)
      bits = constant_bits(node_id, type_id)
      return rewrite_expression(node_id) unless bits
      scalar = @semantic.type_table.scalar_type(type_id)
      return rewrite_expression(node_id) unless scalar

      width = scalar.bit_width == 0 ? 1 : scalar.bit_width
      mask = width == 64 ? UInt64::MAX : (1_u64 << width) - 1
      normalized = bits & mask
      value = if scalar.signed && (normalized & (1_u64 << (width - 1))) != 0
                normalized.to_i128 - (1_i128 << width)
              else
                normalized.to_i128
              end
      @arena.add(IntegerLiteralExpr.new(node.span, value))
    end

    private def constant_bits(node_id : NodeId, type_id : TypeId) : UInt64?
      case node = @source.arena.node(node_id)
      when IntegerLiteralExpr
        value = node.synthetic_value || @source.source_file.slice(node.span).to_i128?
        return nil unless value && value >= 0 && value <= UInt64::MAX
        value.to_u64
      when BooleanLiteralExpr
        node.value ? 1_u64 : 0_u64
      when BinaryExpr
        left = constant_bits(node.left, type_id)
        right = constant_bits(node.right, type_id)
        return nil unless left && right
        case node.operator
        when BinaryOperator::Add
          left &+ right
        when BinaryOperator::Subtract
          left &- right
        when BinaryOperator::Multiply
          left &* right
        end
      else
        nil
      end
    end

    private def identifier(name : AstName, span : SourceSpan) : NodeId
      @arena.add(IdentifierExpr.new(span, name))
    end

    private def literal_uint(value : UInt64, span : SourceSpan) : NodeId
      @arena.add(IntegerLiteralExpr.new(span, value.to_i128))
    end

    private def literal_uint(value : UInt128, span : SourceSpan) : NodeId
      literal_uint(uint64_value(value, span), span)
    end

    private def generated_name(span : SourceSpan, role : String, unique : Bool = true) : AstName
      if unique
        name = ""
        loop do
          name = "__sma_#{role}_#{@generated_name_index}"
          @generated_name_index += 1
          break unless @source_names.includes?(name)
        end
        @source_names.add(name)
        AstName.new(span, name)
      else
        AstName.new(span, role)
      end
    end

    private def source_type_id(type_id : AstTypeId) : TypeId
      @semantic.type_table.id_for(type_id, @source.type_arena)
    end

    private def array_type?(type_id : TypeId) : Bool
      !@semantic.type_table.array_type(type_id).nil?
    end

    private def lower_type(type_id : AstTypeId) : AstTypeId
      syntax = @source.type_arena.type(type_id)
      return type_id unless syntax.is_a?(ArrayTypeSyntax)
      storage_size(source_type_id(type_id), syntax.span)
      byte_pointer_type(syntax.span)
    end

    private def byte_pointer_type(span : SourceSpan) : AstTypeId
      scalar = @type_arena.add(ScalarTypeSyntax.new(span, BYTE_TYPE))
      @type_arena.add(PointerTypeSyntax.new(span, scalar))
    end

    private def scalar_type_syntax(type : AstType, span : SourceSpan) : AstTypeId
      @type_arena.add(ScalarTypeSyntax.new(span, type))
    end

    private def type_syntax(type_id : TypeId, span : SourceSpan) : AstTypeId
      if scalar = @semantic.type_table.scalar_type(type_id)
        scalar_type_syntax(ast_scalar_type(scalar.name), span)
      elsif pointer = @semantic.type_table.pointer_type(type_id)
        pointee = type_syntax(pointer.pointee_type_id, span)
        @type_arena.add(PointerTypeSyntax.new(span, pointee))
      else
        fail_at(span, "cannot create source type syntax for lowered value type")
        scalar_type_syntax(AstType::UInt8, span)
      end
    end

    private def ast_scalar_type(name : String) : AstType
      case name
      when "int"    then AstType::Int
      when "uint"   then AstType::UInt
      when "bool"   then AstType::Bool
      when "int8"   then AstType::Int8
      when "uint8"  then AstType::UInt8
      when "int16"  then AstType::Int16
      when "uint16" then AstType::UInt16
      when "int32"  then AstType::Int32
      when "uint32" then AstType::UInt32
      when "int64"  then AstType::Int64
      when "uint64" then AstType::UInt64
      else
        raise "unknown scalar type #{name}"
      end
    end

    private def storage_size(type_id : TypeId, span : SourceSpan) : UInt64
      size = @semantic.type_table.storage_size(type_id)
      unless size && size <= UInt64::MAX
        fail_at(span, "array storage size is not representable as uint")
        return 0_u64
      end
      if size > Int32::MAX.to_u128
        fail_at(span, "array type exceeds x86_64 stack frame or index limits")
        return 0_u64
      end
      size.to_u64
    end

    private def storage_alignment(type_id : TypeId, span : SourceSpan) : UInt64
      alignment = @semantic.type_table.storage_alignment(type_id)
      unless alignment && alignment > 0 && alignment <= UInt64::MAX
        fail_at(span, "array storage alignment is not representable as uint")
        return 1_u64
      end
      alignment.to_u64
    end

    private def uint64_value(value : UInt128, span : SourceSpan) : UInt64
      if value > UInt64::MAX
        fail_at(span, "array length or layout exceeds uint range")
        return 0_u64
      end
      value.to_u64
    end

    private def fail_at(span : SourceSpan, description : String) : Nil
      @failure ||= {span, description}
    end
  end

  class ArrayAstLoweringPass < AstPass
    def label : String
      "array lowering"
    end

    def run(input : SemanticModule) : AstPassResult
      ArrayAstLowerer.new(input).lower
    end
  end
end
