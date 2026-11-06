module Smalang
  alias FunctionId = Int32
  alias ValueId = Int32
  alias InstructionId = Int32
  alias BlockId = Int32

  enum IrType : UInt8
    Isize
    Usize
    Bool
    Exception

    def label : String
      to_s.downcase
    end
  end

  enum IrExceptionKind : UInt8
    DivisionByZero
  end

  struct IrSourceLocation
    getter file : String
    getter line : Int32

    def initialize(@file : String, @line : Int32)
    end

    def dump : String
      "(at #{@file.inspect} #{@line})"
    end
  end

  class IrBuildFailure < Exception
  end

  class IrFunctionSignature
    getter result_type : IrType

    @parameter_types : Array(IrType)

    def initialize(parameter_types : Array(IrType), @result_type : IrType)
      @parameter_types = parameter_types.dup
    end

    def parameter_types : Array(IrType)
      @parameter_types.dup
    end

    def ==(other : IrFunctionSignature) : Bool
      @result_type == other.result_type && @parameter_types == other.parameter_types
    end
  end

  struct IrParameter
    getter value_id : ValueId
    getter type : IrType

    def initialize(@value_id : ValueId, @type : IrType)
    end
  end

  struct IrValueInfo
    getter type : IrType
    getter defining_instruction_id : InstructionId?
    getter defining_block_id : BlockId?
    getter edge_source_block_id : BlockId?

    def initialize(
      @type : IrType,
      @defining_instruction_id : InstructionId?,
      @defining_block_id : BlockId? = nil,
      @edge_source_block_id : BlockId? = nil,
    )
    end

    def edge_defined? : Bool
      !@edge_source_block_id.nil?
    end
  end

  struct IrPhiIncoming
    getter predecessor_block_id : BlockId
    getter value_id : ValueId

    def initialize(@predecessor_block_id : BlockId, @value_id : ValueId)
    end
  end

  struct IrExceptionCase
    getter kind : IrExceptionKind?
    getter target_block_id : BlockId

    def initialize(@kind : IrExceptionKind?, @target_block_id : BlockId)
    end

    def catch_all? : Bool
      @kind.nil?
    end
  end

  struct IrInvokeResults
    getter value_id : ValueId
    getter exception_id : ValueId

    def initialize(@value_id : ValueId, @exception_id : ValueId)
    end
  end

  struct IrValueDefinition
    getter value_id : ValueId
    getter type : IrType
    getter defining_block_id : BlockId
    getter instruction_index : Int32
    getter edge_source_block_id : BlockId?

    def initialize(
      @value_id : ValueId,
      @type : IrType,
      @defining_block_id : BlockId,
      @instruction_index : Int32,
      @edge_source_block_id : BlockId? = nil,
    )
    end

    def edge_defined? : Bool
      !@edge_source_block_id.nil?
    end
  end

  class IrBasicBlock
    getter id : BlockId
    getter name : String

    @instruction_ids : Array(InstructionId)

    def initialize(@id : BlockId, @name : String)
      @instruction_ids = [] of InstructionId
    end

    def append_instruction(id : InstructionId) : Nil
      @instruction_ids << id
    end

    def instruction_ids : Array(InstructionId)
      @instruction_ids.dup
    end
  end

  abstract class IrCallTarget
    abstract def symbol : String
    abstract def signature : IrFunctionSignature
    abstract def resolve_signature(ir_module : IrModule) : IrFunctionSignature?
    abstract def module_function_id : FunctionId?
  end

  class InternalFunctionTarget < IrCallTarget
    getter function_id : FunctionId
    getter signature : IrFunctionSignature

    def initialize(@function_id : FunctionId, @symbol : String, signature : IrFunctionSignature)
      @signature = IrFunctionSignature.new(signature.parameter_types, signature.result_type)
    end

    def symbol : String
      "@#{@symbol}"
    end

    def resolve_signature(ir_module : IrModule) : IrFunctionSignature?
      function = ir_module.function(@function_id)
      return nil unless function
      return nil unless function.name == @symbol
      return nil unless function.signature == @signature
      function.signature
    end

    def module_function_id : FunctionId?
      @function_id
    end
  end

  abstract class IrInvokeOperationVisitor
    abstract def visit(operation : IrCallOperation, instruction : IrInvokeInstruction) : Nil
    abstract def visit(operation : IrDivideOperation, instruction : IrInvokeInstruction) : Nil
    abstract def visit(operation : IrRemainderOperation, instruction : IrInvokeInstruction) : Nil
  end

  abstract class IrInstructionVisitor < IrInvokeOperationVisitor
    abstract def visit(instruction : IrConstantInstruction) : Nil
    abstract def visit(instruction : IrAddInstruction) : Nil
    abstract def visit(instruction : IrSubtractInstruction) : Nil
    abstract def visit(instruction : IrMultiplyInstruction) : Nil
    abstract def visit(instruction : IrReturnInstruction) : Nil
    abstract def visit(instruction : IrPhiInstruction) : Nil
    abstract def visit(instruction : IrJumpInstruction) : Nil
    abstract def visit(instruction : IrBranchInstruction) : Nil
    abstract def visit(instruction : IrInvokeInstruction) : Nil
    abstract def visit(instruction : IrResumeExceptionInstruction) : Nil
    abstract def visit(instruction : IrExceptionDispatchInstruction) : Nil
    abstract def visit(instruction : IrSuppressExceptionInstruction) : Nil
    abstract def visit(instruction : IrExceptionReleaseInstruction) : Nil
  end

  abstract class IrInstruction
    getter id : InstructionId
    getter block_id : BlockId
    getter result_id : ValueId?
    getter result_type : IrType?

    def initialize(@id : InstructionId, @block_id : BlockId, @result_id : ValueId?, @result_type : IrType?)
    end

    abstract def used_values : Array(ValueId)
    abstract def expression : String
    abstract def terminator? : Bool
    abstract def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
    abstract def accept(visitor : IrInstructionVisitor) : Nil

    def successor_block_ids : Array(BlockId)
      [] of BlockId
    end

    def value_definitions(instruction_index : Int32) : Array(IrValueDefinition)
      value_id = @result_id
      value_type = @result_type
      return [] of IrValueDefinition unless value_id && value_type
      [IrValueDefinition.new(value_id, value_type, @block_id, instruction_index)] of IrValueDefinition
    end

    def dump(function : IrFunction) : String
      expression
    end
  end

  class IrConstantInstruction < IrInstruction
    getter value : Int128

    def initialize(id : InstructionId, block_id : BlockId, result_id : ValueId, result_type : IrType, @value : Int128)
      super(id, block_id, result_id, result_type)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def terminator? : Bool
      false
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      type = @result_type
      return [] of String unless type
      return [] of String if type == IrType::Isize || type == IrType::Usize
      if type == IrType::Bool
        return [] of String if @value == 0 || @value == 1
        return [context.error("bool constant must be 0 or 1, got #{@value}")]
      end
      [context.error("const result must have an integer type, got #{type.label}")]
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end

    def expression : String
      "(%v#{@result_id.not_nil!} #{@result_type.not_nil!.label} (const #{@value}))"
    end
  end

  abstract class IrBinaryInstruction < IrInstruction
    getter left : ValueId
    getter right : ValueId

    def initialize(id : InstructionId, block_id : BlockId, result_id : ValueId, result_type : IrType, @left : ValueId, @right : ValueId)
      super(id, block_id, result_id, result_type)
    end

    def used_values : Array(ValueId)
      [@left, @right]
    end

    def terminator? : Bool
      false
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      errors = [] of String
      left_type = operand_types[0]?
      right_type = operand_types[1]?
      result_type = @result_type

      [left_type, right_type, result_type].each do |type|
        next unless type
        unless type == IrType::Isize || type == IrType::Usize
          errors << context.error("#{operator_name} requires integer operands and result, got #{type.label}")
          break
        end
      end

      if left_type && right_type && left_type != right_type
        errors << context.error("#{operator_name} operands must have matching types")
      end
      if left_type && result_type && left_type != result_type
        errors << context.error("#{operator_name} result has type #{result_type.label}, expected #{left_type.label}")
      end
      errors
    end

    protected abstract def operator_name : String

    def expression : String
      "(%v#{@result_id.not_nil!} #{@result_type.not_nil!.label} (#{operator_name} %v#{@left} %v#{@right}))"
    end
  end

  class IrAddInstruction < IrBinaryInstruction
    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end

    protected def operator_name : String
      "add"
    end
  end

  class IrSubtractInstruction < IrBinaryInstruction
    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end

    protected def operator_name : String
      "sub"
    end
  end

  class IrMultiplyInstruction < IrBinaryInstruction
    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end

    protected def operator_name : String
      "mul"
    end
  end

  class IrReturnInstruction < IrInstruction
    getter value_id : ValueId

    def initialize(id : InstructionId, block_id : BlockId, @value_id : ValueId)
      super(id, block_id, nil, nil)
    end

    def used_values : Array(ValueId)
      [@value_id]
    end

    def terminator? : Bool
      true
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      value_type = operand_types.first?
      return [] of String unless value_type
      expected_type = context.function.signature.result_type
      return [] of String if value_type == expected_type
      [context.error("return has type #{value_type.label}, expected #{expected_type.label}")]
    end

    def expression : String
      "(return %v#{@value_id})"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  abstract class IrInvokeOperation
    abstract def used_values : Array(ValueId)
    abstract def result_type : IrType
    abstract def expression : String
    abstract def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
    abstract def accept(visitor : IrInvokeOperationVisitor, instruction : IrInvokeInstruction) : Nil
  end

  class IrCallOperation < IrInvokeOperation
    getter target : IrCallTarget

    @arguments : Array(ValueId)

    def initialize(@target : IrCallTarget, arguments : Array(ValueId))
      @arguments = arguments.dup
    end

    def arguments : Array(ValueId)
      @arguments.dup
    end

    def used_values : Array(ValueId)
      @arguments.dup
    end

    def result_type : IrType
      @target.signature.result_type
    end

    def expression : String
      operands = @arguments.map { |value_id| "%v#{value_id}" }
      call = (["call", @target.symbol] + operands).join(" ")
      "(#{call})"
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      signature = @target.resolve_signature(context.ir_module)
      return [context.error("call target #{@target.symbol} does not resolve to a matching function signature")] of String unless signature

      errors = [] of String
      if signature.parameter_types.size != @arguments.size
        errors << context.error("call #{@target.symbol} expects #{signature.parameter_types.size} arguments, got #{@arguments.size}")
      end

      @arguments.each_with_index do |_, index|
        expected_type = signature.parameter_types[index]?
        actual_type = operand_types[index]?
        next unless expected_type && actual_type
        if actual_type != expected_type
          errors << context.error("call argument #{index} has type #{actual_type.label}, expected #{expected_type.label}")
        end
      end
      errors
    end

    def accept(visitor : IrInvokeOperationVisitor, instruction : IrInvokeInstruction) : Nil
      visitor.visit(self, instruction)
    end
  end

  abstract class IrIntegerBinaryInvokeOperation < IrInvokeOperation
    getter left : ValueId
    getter right : ValueId
    getter type : IrType

    def initialize(@type : IrType, @left : ValueId, @right : ValueId)
    end

    def used_values : Array(ValueId)
      [@left, @right]
    end

    def result_type : IrType
      @type
    end

    def expression : String
      "(#{operator_name} %v#{@left} %v#{@right})"
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      errors = [] of String
      unless @type == IrType::Isize || @type == IrType::Usize
        errors << context.error("#{operator_name} result must have an integer type, got #{@type.label}")
      end
      left_type = operand_types[0]?
      right_type = operand_types[1]?
      if left_type && left_type != @type
        errors << context.error("#{operator_name} left operand has type #{left_type.label}, expected #{@type.label}")
      end
      if right_type && right_type != @type
        errors << context.error("#{operator_name} right operand has type #{right_type.label}, expected #{@type.label}")
      end
      errors
    end

    protected abstract def operator_name : String
  end

  class IrDivideOperation < IrIntegerBinaryInvokeOperation
    def initialize(type : IrType, left : ValueId, right : ValueId)
      super(type, left, right)
    end

    protected def operator_name : String
      "div"
    end

    def accept(visitor : IrInvokeOperationVisitor, instruction : IrInvokeInstruction) : Nil
      visitor.visit(self, instruction)
    end
  end

  class IrRemainderOperation < IrIntegerBinaryInvokeOperation
    def initialize(type : IrType, left : ValueId, right : ValueId)
      super(type, left, right)
    end

    protected def operator_name : String
      "rem"
    end

    def accept(visitor : IrInvokeOperationVisitor, instruction : IrInvokeInstruction) : Nil
      visitor.visit(self, instruction)
    end
  end

  class IrPhiInstruction < IrInstruction
    @incoming : Array(IrPhiIncoming)

    def initialize(id : InstructionId, block_id : BlockId, result_id : ValueId, result_type : IrType, incoming : Array(IrPhiIncoming))
      super(id, block_id, result_id, result_type)
      @incoming = incoming.dup
    end

    def incoming : Array(IrPhiIncoming)
      @incoming.dup
    end

    def used_values : Array(ValueId)
      @incoming.map(&.value_id)
    end

    def terminator? : Bool
      false
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      errors = [] of String
      expected_type = @result_type
      @incoming.each_with_index do |_, index|
        actual_type = operand_types[index]?
        next unless expected_type && actual_type
        if actual_type != expected_type
          errors << context.error("phi incoming value has type #{actual_type.label}, expected #{expected_type.label}")
        end
      end
      errors
    end

    def expression : String
      inputs = @incoming.map do |input|
        "[@#{input.predecessor_block_id} %v#{input.value_id}]"
      end
      "(%v#{@result_id.not_nil!} #{@result_type.not_nil!.label} (phi #{inputs.join(" ")}))"
    end

    def dump(function : IrFunction) : String
      inputs = @incoming.map do |input|
        "[@#{function.block_name(input.predecessor_block_id)} %v#{input.value_id}]"
      end
      "(%v#{@result_id.not_nil!} #{@result_type.not_nil!.label} (phi #{inputs.join(" ")}))"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrJumpInstruction < IrInstruction
    getter target_block_id : BlockId

    def initialize(id : InstructionId, block_id : BlockId, @target_block_id : BlockId)
      super(id, block_id, nil, nil)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def successor_block_ids : Array(BlockId)
      [@target_block_id]
    end

    def terminator? : Bool
      true
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      [] of String
    end

    def expression : String
      "(jump @#{@target_block_id})"
    end

    def dump(function : IrFunction) : String
      "(jump @#{function.block_name(@target_block_id)})"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrBranchInstruction < IrInstruction
    getter condition_id : ValueId
    getter true_block_id : BlockId
    getter false_block_id : BlockId

    def initialize(id : InstructionId, block_id : BlockId, @condition_id : ValueId, @true_block_id : BlockId, @false_block_id : BlockId)
      super(id, block_id, nil, nil)
    end

    def used_values : Array(ValueId)
      [@condition_id]
    end

    def successor_block_ids : Array(BlockId)
      [@true_block_id, @false_block_id]
    end

    def terminator? : Bool
      true
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      type = operand_types.first?
      return [] of String unless type
      return [] of String if type == IrType::Isize || type == IrType::Usize || type == IrType::Bool
      [context.error("branch condition must be an integer or bool, got #{type.label}")]
    end

    def expression : String
      "(branch %v#{@condition_id} @#{@true_block_id} @#{@false_block_id})"
    end

    def dump(function : IrFunction) : String
      "(branch %v#{@condition_id} @#{function.block_name(@true_block_id)} @#{function.block_name(@false_block_id)})"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrInvokeInstruction < IrInstruction
    getter operation : IrInvokeOperation
    getter normal_successor : BlockId
    getter exception_successor : BlockId
    getter normal_result_id : ValueId
    getter exception_result_id : ValueId
    getter source_location : IrSourceLocation?

    def initialize(
      id : InstructionId,
      block_id : BlockId,
      @operation : IrInvokeOperation,
      @normal_successor : BlockId,
      @exception_successor : BlockId,
      @normal_result_id : ValueId,
      @exception_result_id : ValueId,
      @source_location : IrSourceLocation?,
    )
      super(id, block_id, nil, nil)
    end

    def used_values : Array(ValueId)
      @operation.used_values
    end

    def successor_block_ids : Array(BlockId)
      [@normal_successor, @exception_successor]
    end

    def value_definitions(instruction_index : Int32) : Array(IrValueDefinition)
      [
        IrValueDefinition.new(@normal_result_id, @operation.result_type, @normal_successor, -1, @block_id),
        IrValueDefinition.new(@exception_result_id, IrType::Exception, @exception_successor, -1, @block_id),
      ] of IrValueDefinition
    end

    def terminator? : Bool
      true
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      @operation.validate(context, operand_types)
    end

    def expression : String
      "(invoke #{@operation.expression} (normal @#{@normal_successor} %v#{@normal_result_id}) (exception @#{@exception_successor} %v#{@exception_result_id})#{location_dump})"
    end

    def dump(function : IrFunction) : String
      "(invoke #{@operation.expression} (normal @#{function.block_name(@normal_successor)} %v#{@normal_result_id}) (exception @#{function.block_name(@exception_successor)} %v#{@exception_result_id})#{location_dump})"
    end

    private def location_dump : String
      @source_location.try { |location| " #{location.dump}" } || ""
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrResumeExceptionInstruction < IrInstruction
    getter exception_id : ValueId

    def initialize(id : InstructionId, block_id : BlockId, @exception_id : ValueId)
      super(id, block_id, nil, nil)
    end

    def used_values : Array(ValueId)
      [@exception_id]
    end

    def terminator? : Bool
      true
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      type = operand_types.first?
      return [] of String unless type
      return [] of String if type == IrType::Exception
      [context.error("resume requires an exception value, got #{type.label}")]
    end

    def expression : String
      "(resume %v#{@exception_id})"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrExceptionDispatchInstruction < IrInstruction
    getter exception_id : ValueId
    getter default_block_id : BlockId?

    @cases : Array(IrExceptionCase)

    def initialize(
      id : InstructionId,
      block_id : BlockId,
      @exception_id : ValueId,
      cases : Array(IrExceptionCase),
      @default_block_id : BlockId?,
    )
      super(id, block_id, nil, nil)
      @cases = cases.dup
    end

    def cases : Array(IrExceptionCase)
      @cases.dup
    end

    def used_values : Array(ValueId)
      [@exception_id]
    end

    def successor_block_ids : Array(BlockId)
      targets = @cases.map(&.target_block_id)
      targets << @default_block_id.not_nil! if @default_block_id
      targets
    end

    def terminator? : Bool
      true
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      errors = [] of String
      exception_type = operand_types.first?
      if exception_type && exception_type != IrType::Exception
        errors << context.error("exception dispatch requires an exception value, got #{exception_type.label}")
      end

      seen_kinds = {} of IrExceptionKind => Bool
      has_catch_all = false
      @cases.each_with_index do |exception_case, index|
        if exception_case.catch_all?
          if has_catch_all
            errors << context.error("exception dispatch has more than one catch-all case")
          end
          if index != @cases.size - 1
            errors << context.error("exception dispatch catch-all must be the final case")
          end
          has_catch_all = true
        elsif kind = exception_case.kind
          if seen_kinds.has_key?(kind)
            errors << context.error("exception dispatch repeats kind #{kind}")
          end
          seen_kinds[kind] = true
        end
      end

      if has_catch_all && @default_block_id
        errors << context.error("exception dispatch cannot have a default after a catch-all case")
      elsif !has_catch_all && !@default_block_id
        errors << context.error("exception dispatch without catch-all requires a default successor")
      end
      errors
    end

    def expression : String
      cases = @cases.map do |exception_case|
        target = "@#{exception_case.target_block_id}"
        if kind = exception_case.kind
          "(kind #{kind} #{target})"
        else
          "(catch-all #{target})"
        end
      end
      cases << "(default @#{@default_block_id.not_nil!})" if @default_block_id
      "(exception-switch %v#{@exception_id} #{cases.join(" ")})"
    end

    def dump(function : IrFunction) : String
      cases = @cases.map do |exception_case|
        target = "@#{function.block_name(exception_case.target_block_id)}"
        if kind = exception_case.kind
          "(kind #{kind} #{target})"
        else
          "(catch-all #{target})"
        end
      end
      cases << "(default @#{function.block_name(@default_block_id.not_nil!)})" if @default_block_id
      "(exception-switch %v#{@exception_id} #{cases.join(" ")})"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrSuppressExceptionInstruction < IrInstruction
    getter new_exception_id : ValueId
    getter old_exception_id : ValueId

    def initialize(id : InstructionId, block_id : BlockId, result_id : ValueId, @new_exception_id : ValueId, @old_exception_id : ValueId)
      super(id, block_id, result_id, IrType::Exception)
    end

    def used_values : Array(ValueId)
      [@new_exception_id, @old_exception_id]
    end

    def terminator? : Bool
      false
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      errors = [] of String
      if @new_exception_id == @old_exception_id
        errors << context.error("suppress operands must have distinct exception values")
      end
      operand_types.each_with_index do |type, index|
        next unless type
        next if type == IrType::Exception
        label = index == 0 ? "new" : "old"
        errors << context.error("suppress #{label} operand must be exception, got #{type.label}")
      end
      errors
    end

    def expression : String
      "(%v#{@result_id.not_nil!} exception (suppress %v#{@new_exception_id} %v#{@old_exception_id}))"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrExceptionReleaseInstruction < IrInstruction
    getter exception_id : ValueId

    def initialize(id : InstructionId, block_id : BlockId, @exception_id : ValueId)
      super(id, block_id, nil, nil)
    end

    def used_values : Array(ValueId)
      [@exception_id]
    end

    def terminator? : Bool
      false
    end

    def validate(context : IrVerificationContext, operand_types : Array(IrType?)) : Array(String)
      type = operand_types.first?
      return [] of String unless type
      return [] of String if type == IrType::Exception
      [context.error("exception.release requires an exception value, got #{type.label}")]
    end

    def expression : String
      "(exception.release %v#{@exception_id})"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
    end
  end

  class IrFunction
    getter id : FunctionId
    getter name : String
    getter signature : IrFunctionSignature
    getter entry_block_id : BlockId

    @parameters : Array(IrParameter)

    def initialize(@id : FunctionId, @name : String, parameter_types : Array(IrType), result_type : IrType)
      @signature = IrFunctionSignature.new(parameter_types, result_type)
      @parameters = [] of IrParameter
      @values = [] of IrValueInfo
      @instructions = [] of IrInstruction
      @blocks = [] of IrBasicBlock

      @entry_block_id = 0
      @blocks << IrBasicBlock.new(@entry_block_id, "entry")
      @signature.parameter_types.each do |type|
        value_id = @values.size
        @values << IrValueInfo.new(type, nil, @entry_block_id)
        @parameters << IrParameter.new(value_id, type)
      end
    end

    def parameters : Array(IrParameter)
      @parameters.dup
    end

    def value_type(value_id : ValueId) : IrType?
      return nil if value_id < 0
      @values[value_id]?.try(&.type)
    end

    def value_info(value_id : ValueId) : IrValueInfo?
      return nil if value_id < 0
      @values[value_id]?
    end

    def block(block_id : BlockId) : IrBasicBlock?
      return nil if block_id < 0
      @blocks[block_id]?
    end

    def block_name(block_id : BlockId) : String
      basic_block = block(block_id)
      raise IrBuildFailure.new("unknown block #{block_id} in function #{@name}") unless basic_block
      basic_block.name
    end

    def instruction(instruction_id : InstructionId) : IrInstruction?
      return nil if instruction_id < 0
      @instructions[instruction_id]?
    end

    def value_count : Int32
      @values.size
    end

    def instruction_count : Int32
      @instructions.size
    end

    def block_count : Int32
      @blocks.size
    end

    def add_block(name : String) : BlockId
      block_id = @blocks.size
      @blocks << IrBasicBlock.new(block_id, name)
      block_id
    end

    def emit_constant(block_id : BlockId, type : IrType, value : Int128) : ValueId
      append_result(block_id, type) do |instruction_id, result_id|
        IrConstantInstruction.new(instruction_id, block_id, result_id, type, value)
      end
    end

    def emit_add(block_id : BlockId, type : IrType, left : ValueId, right : ValueId) : ValueId
      append_result(block_id, type) do |instruction_id, result_id|
        IrAddInstruction.new(instruction_id, block_id, result_id, type, left, right)
      end
    end

    def emit_subtract(block_id : BlockId, type : IrType, left : ValueId, right : ValueId) : ValueId
      append_result(block_id, type) do |instruction_id, result_id|
        IrSubtractInstruction.new(instruction_id, block_id, result_id, type, left, right)
      end
    end

    def emit_multiply(block_id : BlockId, type : IrType, left : ValueId, right : ValueId) : ValueId
      append_result(block_id, type) do |instruction_id, result_id|
        IrMultiplyInstruction.new(instruction_id, block_id, result_id, type, left, right)
      end
    end

    def emit_invoke_call(
      block_id : BlockId,
      target : IrCallTarget,
      arguments : Array(ValueId),
      normal_successor : BlockId,
      exception_successor : BlockId,
      source_location : IrSourceLocation? = nil,
    ) : IrInvokeResults
      append_invoke(block_id, IrCallOperation.new(target, arguments), normal_successor, exception_successor, source_location)
    end

    def emit_invoke_divide(
      block_id : BlockId,
      type : IrType,
      left : ValueId,
      right : ValueId,
      normal_successor : BlockId,
      exception_successor : BlockId,
      source_location : IrSourceLocation? = nil,
    ) : IrInvokeResults
      append_invoke(block_id, IrDivideOperation.new(type, left, right), normal_successor, exception_successor, source_location)
    end

    def emit_invoke_remainder(
      block_id : BlockId,
      type : IrType,
      left : ValueId,
      right : ValueId,
      normal_successor : BlockId,
      exception_successor : BlockId,
      source_location : IrSourceLocation? = nil,
    ) : IrInvokeResults
      append_invoke(block_id, IrRemainderOperation.new(type, left, right), normal_successor, exception_successor, source_location)
    end

    def emit_phi(block_id : BlockId, type : IrType, incoming : Array(IrPhiIncoming)) : ValueId
      append_result(block_id, type) do |instruction_id, result_id|
        IrPhiInstruction.new(instruction_id, block_id, result_id, type, incoming)
      end
    end

    def emit_jump(block_id : BlockId, target_block_id : BlockId) : Nil
      append_terminator(block_id) do |instruction_id|
        IrJumpInstruction.new(instruction_id, block_id, target_block_id)
      end
    end

    def emit_branch(block_id : BlockId, condition_id : ValueId, true_block_id : BlockId, false_block_id : BlockId) : Nil
      append_terminator(block_id) do |instruction_id|
        IrBranchInstruction.new(instruction_id, block_id, condition_id, true_block_id, false_block_id)
      end
    end

    def emit_resume_exception(block_id : BlockId, exception_id : ValueId) : Nil
      append_terminator(block_id) do |instruction_id|
        IrResumeExceptionInstruction.new(instruction_id, block_id, exception_id)
      end
    end

    def emit_exception_release(block_id : BlockId, exception_id : ValueId) : Nil
      block = require_block(block_id)
      instruction_id = @instructions.size
      @instructions << IrExceptionReleaseInstruction.new(instruction_id, block_id, exception_id)
      block.append_instruction(instruction_id)
    end

    def emit_exception_dispatch(
      block_id : BlockId,
      exception_id : ValueId,
      cases : Array(IrExceptionCase),
      default_block_id : BlockId? = nil,
    ) : Nil
      append_terminator(block_id) do |instruction_id|
        IrExceptionDispatchInstruction.new(instruction_id, block_id, exception_id, cases, default_block_id)
      end
    end

    def emit_suppress_exception(block_id : BlockId, new_exception_id : ValueId, old_exception_id : ValueId) : ValueId
      append_result(block_id, IrType::Exception) do |instruction_id, result_id|
        IrSuppressExceptionInstruction.new(instruction_id, block_id, result_id, new_exception_id, old_exception_id)
      end
    end

    def emit_return(block_id : BlockId, value_id : ValueId) : Nil
      block = require_block(block_id)
      instruction_id = @instructions.size
      @instructions << IrReturnInstruction.new(instruction_id, block_id, value_id)
      block.append_instruction(instruction_id)
    end

    def each_block(&block : IrBasicBlock ->) : Nil
      @blocks.each(&block)
    end

    def each_block_with_index(&block : IrBasicBlock, Int32 ->) : Nil
      @blocks.each_with_index(&block)
    end

    private def append_result(block_id : BlockId, type : IrType, &build : InstructionId, ValueId -> IrInstruction) : ValueId
      block = require_block(block_id)
      instruction_id = @instructions.size
      result_id = @values.size
      instruction = build.call(instruction_id, result_id)

      @instructions << instruction
      @values << IrValueInfo.new(type, instruction_id, block_id)
      block.append_instruction(instruction_id)
      result_id
    end

    private def append_invoke(
      block_id : BlockId,
      operation : IrInvokeOperation,
      normal_successor : BlockId,
      exception_successor : BlockId,
      source_location : IrSourceLocation?,
    ) : IrInvokeResults
      block = require_block(block_id)
      require_block(normal_successor)
      require_block(exception_successor)
      if normal_successor == exception_successor
        raise IrBuildFailure.new("invoke normal and exception successors must be different")
      end

      instruction_id = @instructions.size
      normal_result_id = @values.size
      exception_result_id = normal_result_id + 1
      instruction = IrInvokeInstruction.new(
        instruction_id,
        block_id,
        operation,
        normal_successor,
        exception_successor,
        normal_result_id,
        exception_result_id,
        source_location
      )

      @instructions << instruction
      @values << IrValueInfo.new(operation.result_type, instruction_id, normal_successor, block_id)
      @values << IrValueInfo.new(IrType::Exception, instruction_id, exception_successor, block_id)
      block.append_instruction(instruction_id)
      IrInvokeResults.new(normal_result_id, exception_result_id)
    end

    private def append_terminator(block_id : BlockId, &build : InstructionId -> IrInstruction) : Nil
      block = require_block(block_id)
      instruction_id = @instructions.size
      @instructions << build.call(instruction_id)
      block.append_instruction(instruction_id)
    end

    private def require_block(block_id : BlockId) : IrBasicBlock
      block = self.block(block_id)
      raise IrBuildFailure.new("unknown block #{block_id} in function #{@name}") unless block
      block
    end
  end

  class IrModule
    @functions : Array(IrFunction)

    def initialize
      @functions = [] of IrFunction
    end

    def add_function(name : String, parameter_types : Array(IrType), result_type : IrType) : IrFunction
      function = IrFunction.new(@functions.size, name, parameter_types, result_type)
      @functions << function
      function
    end

    def function(function_id : FunctionId) : IrFunction?
      return nil if function_id < 0
      @functions[function_id]?
    end

    def function_count : Int32
      @functions.size
    end

    def each_function(&block : IrFunction ->) : Nil
      @functions.each(&block)
    end

    def each_function_with_index(&block : IrFunction, Int32 ->) : Nil
      @functions.each_with_index(&block)
    end

    def verify : Array(String)
      IrVerifier.new.verify(self)
    end

    def internal_call_target(function_id : FunctionId) : InternalFunctionTarget?
      target_function = function(function_id)
      return nil unless target_function
      InternalFunctionTarget.new(function_id, target_function.name, target_function.signature)
    end
  end

  class IrVerificationContext
    getter ir_module : IrModule
    getter function : IrFunction

    def initialize(@ir_module : IrModule, @function : IrFunction)
    end

    def error(message : String) : String
      "function #{@function.name}: #{message}"
    end
  end

  class IrVerifier
    def verify(ir_module : IrModule) : Array(String)
      diagnostics = [] of String
      ir_module.each_function_with_index do |function, expected_id|
        if function.id != expected_id
          diagnostics << "function #{function.name} has id #{function.id}, expected #{expected_id}"
        end
        diagnostics.concat(verify_function(ir_module, function))
      end
      diagnostics
    end

    private def verify_function(ir_module : IrModule, function : IrFunction) : Array(String)
      diagnostics = [] of String
      context = IrVerificationContext.new(ir_module, function)
      definition_sites = {} of ValueId => IrValueDefinition
      value_types = {} of ValueId => IrType
      block_instructions = {} of BlockId => Array(IrInstruction)
      predecessor_blocks = {} of BlockId => Array(BlockId)
      seen_instruction_ids = {} of InstructionId => Bool

      function.parameters.each_with_index do |parameter, index|
        if definition_sites.has_key?(parameter.value_id)
          diagnostics << context.error("duplicate definition of %v#{parameter.value_id}")
          next
        end

        if info = function.value_info(parameter.value_id)
          if info.type != parameter.type
            diagnostics << context.error("parameter %v#{parameter.value_id} metadata has type #{info.type.label}, expected #{parameter.type.label}")
          end
          if info.defining_instruction_id
            diagnostics << context.error("parameter %v#{parameter.value_id} has an instruction definition")
          end
          if info.defining_block_id != function.entry_block_id
            diagnostics << context.error("parameter %v#{parameter.value_id} is not defined in the entry block")
          end
          if info.edge_defined?
            diagnostics << context.error("parameter %v#{parameter.value_id} cannot be edge-defined")
          end
        else
          diagnostics << context.error("parameter %v#{parameter.value_id} has no value metadata")
        end

        if parameter.value_id != index
          diagnostics << context.error("parameter #{index} has unexpected value id %v#{parameter.value_id}")
        end
        if parameter.type == IrType::Exception
          diagnostics << context.error("function parameter #{index} cannot have exception type")
        end
        definition_sites[parameter.value_id] = IrValueDefinition.new(parameter.value_id, parameter.type, function.entry_block_id, -1)
        value_types[parameter.value_id] = parameter.type
      end

      if function.signature.result_type == IrType::Exception
        diagnostics << context.error("function result cannot have exception type")
      end

      unless function.block(function.entry_block_id)
        diagnostics << context.error("entry block #{function.entry_block_id} does not exist")
      end

      function.each_block_with_index do |basic_block, expected_id|
        if basic_block.id != expected_id
          diagnostics << context.error("block #{basic_block.name} has id #{basic_block.id}, expected #{expected_id}")
        end

        instructions = [] of IrInstruction
        block_instructions[basic_block.id] = instructions
        predecessor_blocks[basic_block.id] = [] of BlockId
        saw_non_phi = false
        saw_terminator = false

        basic_block.instruction_ids.each_with_index do |instruction_id, index|
          if seen_instruction_ids.has_key?(instruction_id)
            diagnostics << context.error("instruction #{instruction_id} appears more than once")
            next
          end
          seen_instruction_ids[instruction_id] = true

          instruction = function.instruction(instruction_id)
          unless instruction
            diagnostics << context.error("instruction #{instruction_id} does not exist")
            next
          end
          instructions << instruction

          if instruction.block_id != basic_block.id
            diagnostics << context.error("instruction #{instruction_id} belongs to block #{instruction.block_id}, not #{basic_block.id}")
          end
          if saw_terminator
            diagnostics << context.error("instruction #{instruction_id} appears after a terminator")
          end
          if instruction.is_a?(IrPhiInstruction)
            if saw_non_phi
              diagnostics << context.error("phi instruction #{instruction_id} must appear before non-phi instructions")
            end
          else
            saw_non_phi = true
          end

          if instruction.terminator?
            if index != basic_block.instruction_ids.size - 1
              diagnostics << context.error("terminator must be the final instruction in its block")
            end
            if saw_terminator
              diagnostics << context.error("block #{basic_block.name} has more than one terminator")
            end
            saw_terminator = true
          end

          successors = instruction.successor_block_ids
          successors.each do |successor_id|
            unless function.block(successor_id)
              diagnostics << context.error("instruction #{instruction_id} targets unknown block #{successor_id}")
            end
          end

          instruction.value_definitions(index).each do |definition|
            if definition_sites.has_key?(definition.value_id)
              diagnostics << context.error("duplicate definition of %v#{definition.value_id}")
              next
            end
            unless info = function.value_info(definition.value_id)
              diagnostics << context.error("%v#{definition.value_id} has no value metadata")
              next
            end
            if info.type != definition.type
              diagnostics << context.error("%v#{definition.value_id} metadata has type #{info.type.label}, instruction defines #{definition.type.label}")
            end
            if info.defining_instruction_id != instruction.id
              diagnostics << context.error("%v#{definition.value_id} points to the wrong defining instruction")
            end
            if info.defining_block_id != definition.defining_block_id
              diagnostics << context.error("%v#{definition.value_id} metadata points to the wrong defining block")
            end
            if info.edge_source_block_id != definition.edge_source_block_id
              diagnostics << context.error("%v#{definition.value_id} metadata points to the wrong defining edge")
            end
            definition_sites[definition.value_id] = definition
            value_types[definition.value_id] = definition.type
          end
        end

        unless saw_terminator
          diagnostics << context.error("block #{basic_block.name} must end with a terminator")
        end
      end

      if seen_instruction_ids.size != function.instruction_count
        diagnostics << context.error("some instructions are not attached to a block")
      end
      if definition_sites.size != function.value_count
        diagnostics << context.error("contains unreferenced SSA value definitions")
      end

      block_instructions.each do |block_id, instructions|
        next if instructions.empty?
        terminator = instructions.last
        terminator.successor_block_ids.each do |successor_id|
          next unless predecessor_blocks.has_key?(successor_id)
          predecessor_blocks[successor_id] << block_id unless predecessor_blocks[successor_id].includes?(block_id)
        end
      end

      reachable_blocks = find_reachable_blocks(function, block_instructions)
      dominators = compute_dominators(function, predecessor_blocks, reachable_blocks)

      block_instructions.each do |block_id, instructions|
        instructions.each_with_index do |instruction, instruction_index|
          operand_types = instruction.used_values.map do |value_id|
            value_type = value_types[value_id]?
            diagnostics << context.error("%v#{value_id} is not defined") unless value_type
            value_type
          end
          diagnostics.concat(instruction.validate(context, operand_types))

          if phi = instruction.as?(IrPhiInstruction)
            verify_phi_inputs(context, phi, block_id, predecessor_blocks, definition_sites, value_types, dominators, block_instructions, diagnostics)
          else
            instruction.used_values.each do |value_id|
              next unless definition_sites.has_key?(value_id)
              unless value_available_at?(value_id, block_id, instruction_index, nil, predecessor_blocks, definition_sites, dominators)
                diagnostics << context.error("%v#{value_id} does not dominate its use in block #{function.block_name(block_id)}")
              end
            end
          end
        end
      end

      if diagnostics.empty?
        diagnostics.concat(verify_exception_ownership(context, function, block_instructions, reachable_blocks))
      end

      diagnostics
    end

    private def verify_exception_ownership(
      context : IrVerificationContext,
      function : IrFunction,
      block_instructions : Hash(BlockId, Array(IrInstruction)),
      reachable_blocks : Array(BlockId),
    ) : Array(String)
      diagnostics = [] of String
      worklist = [] of Tuple(BlockId, Array(ValueId))
      visited_states = {} of String => Bool
      worklist << {function.entry_block_id, [] of ValueId}

      until worklist.empty?
        block_id, state = worklist.shift
        state.sort!
        state_key = "#{block_id}:#{state.join(",")}"
        next if visited_states.has_key?(state_key)
        visited_states[state_key] = true

        instructions = block_instructions[block_id]?
        next unless instructions
        instructions.each do |instruction|
          case instruction
          when IrPhiInstruction
            next
          when IrExceptionReleaseInstruction
            consume_exception_owner(context, instruction.exception_id, block_id, state, diagnostics)
          when IrSuppressExceptionInstruction
            new_exception_id = instruction.new_exception_id
            old_exception_id = instruction.old_exception_id
            new_owned = consume_exception_owner(context, new_exception_id, block_id, state, diagnostics)
            old_owned = consume_exception_owner(context, old_exception_id, block_id, state, diagnostics)
            if new_owned && old_owned
              result_id = instruction.result_id
              if result_id
                add_exception_owner(context, result_id, block_id, state, diagnostics)
              end
            end
          when IrExceptionDispatchInstruction
            require_exception_owner(context, instruction.exception_id, block_id, state, diagnostics)
          when IrResumeExceptionInstruction
            consume_exception_owner(context, instruction.exception_id, block_id, state, diagnostics)
            report_unconsumed_exception_owners(context, block_id, state, "resume", diagnostics)
          when IrReturnInstruction
            report_unconsumed_exception_owners(context, block_id, state, "return", diagnostics)
          end
        end

        terminator = instructions.last
        case terminator
        when IrInvokeInstruction
          enqueue_exception_ownership_edge(
            context,
            function,
            block_id,
            terminator.normal_successor,
            state,
            block_instructions,
            reachable_blocks,
            worklist,
            diagnostics
          )
          exceptional_state = state.dup
          add_exception_owner(
            context,
            terminator.exception_result_id,
            terminator.exception_successor,
            exceptional_state,
            diagnostics
          )
          enqueue_exception_ownership_edge(
            context,
            function,
            block_id,
            terminator.exception_successor,
            exceptional_state,
            block_instructions,
            reachable_blocks,
            worklist,
            diagnostics
          )
        else
          terminator.successor_block_ids.each do |successor_id|
            enqueue_exception_ownership_edge(
              context,
              function,
              block_id,
              successor_id,
              state,
              block_instructions,
              reachable_blocks,
              worklist,
              diagnostics
            )
          end
        end
      end

      diagnostics.uniq
    end

    private def enqueue_exception_ownership_edge(
      context : IrVerificationContext,
      function : IrFunction,
      predecessor_id : BlockId,
      successor_id : BlockId,
      state : Array(ValueId),
      block_instructions : Hash(BlockId, Array(IrInstruction)),
      reachable_blocks : Array(BlockId),
      worklist : Array(Tuple(BlockId, Array(ValueId))),
      diagnostics : Array(String),
    ) : Nil
      return unless reachable_blocks.includes?(successor_id)
      edge_state = state.dup
      instructions = block_instructions[successor_id]?
      return unless instructions

      instructions.each do |instruction|
        phi = instruction.as?(IrPhiInstruction)
        break unless phi
        next unless phi.result_type == IrType::Exception

        incoming = phi.incoming.find { |candidate| candidate.predecessor_block_id == predecessor_id }
        next unless incoming
        if edge_state.includes?(incoming.value_id)
          edge_state.delete(incoming.value_id)
          result_id = phi.result_id
          add_exception_owner(context, result_id, successor_id, edge_state, diagnostics) if result_id
        else
          diagnostics << context.error("exception %v#{incoming.value_id} is not owned on edge from #{function.block_name(predecessor_id)} to #{function.block_name(successor_id)}")
        end
      end

      worklist << {successor_id, edge_state}
    end

    private def add_exception_owner(
      context : IrVerificationContext,
      exception_id : ValueId,
      block_id : BlockId,
      state : Array(ValueId),
      diagnostics : Array(String),
    ) : Nil
      if state.includes?(exception_id)
        diagnostics << context.error("exception %v#{exception_id} is already owned in block #{context.function.block_name(block_id)}")
      else
        state << exception_id
      end
    end

    private def require_exception_owner(
      context : IrVerificationContext,
      exception_id : ValueId,
      block_id : BlockId,
      state : Array(ValueId),
      diagnostics : Array(String),
    ) : Bool
      return true if state.includes?(exception_id)
      diagnostics << context.error("exception %v#{exception_id} is not owned in block #{context.function.block_name(block_id)}")
      false
    end

    private def consume_exception_owner(
      context : IrVerificationContext,
      exception_id : ValueId,
      block_id : BlockId,
      state : Array(ValueId),
      diagnostics : Array(String),
    ) : Bool
      return false unless require_exception_owner(context, exception_id, block_id, state, diagnostics)
      state.delete(exception_id)
      true
    end

    private def report_unconsumed_exception_owners(
      context : IrVerificationContext,
      block_id : BlockId,
      state : Array(ValueId),
      terminator : String,
      diagnostics : Array(String),
    ) : Nil
      state.each do |exception_id|
        diagnostics << context.error("exception %v#{exception_id} remains owned at #{terminator} in block #{context.function.block_name(block_id)}")
      end
    end

    private def find_reachable_blocks(function : IrFunction, block_instructions : Hash(BlockId, Array(IrInstruction))) : Array(BlockId)
      reachable = [function.entry_block_id]
      index = 0
      while index < reachable.size
        block_id = reachable[index]
        index += 1
        instructions = block_instructions[block_id]?
        next unless instructions && !instructions.empty?
        instructions.last.successor_block_ids.each do |successor_id|
          reachable << successor_id if function.block(successor_id) && !reachable.includes?(successor_id)
        end
      end
      reachable
    end

    private def compute_dominators(
      function : IrFunction,
      predecessor_blocks : Hash(BlockId, Array(BlockId)),
      reachable_blocks : Array(BlockId),
    ) : Hash(BlockId, Array(BlockId))
      dominators = {} of BlockId => Array(BlockId)
      function.block_count.times do |block_id|
        dominators[block_id] = if block_id == function.entry_block_id
                                 [block_id]
                               elsif reachable_blocks.includes?(block_id)
                                 reachable_blocks.dup
                               else
                                 [block_id]
                               end
      end

      changed = true
      while changed
        changed = false
        reachable_blocks.each do |block_id|
          next if block_id == function.entry_block_id
          predecessors = predecessor_blocks[block_id]?.try(&.select { |predecessor| reachable_blocks.includes?(predecessor) }) || [] of BlockId
          next if predecessors.empty?

          new_dominators = dominators[predecessors.first].dup
          predecessors.skip(1).each do |predecessor|
            new_dominators.select! { |candidate| dominators[predecessor].includes?(candidate) }
          end
          new_dominators << block_id unless new_dominators.includes?(block_id)
          if dominators[block_id] != new_dominators
            dominators[block_id] = new_dominators
            changed = true
          end
        end
      end
      dominators
    end

    private def verify_phi_inputs(
      context : IrVerificationContext,
      phi : IrPhiInstruction,
      block_id : BlockId,
      predecessor_blocks : Hash(BlockId, Array(BlockId)),
      definition_sites : Hash(ValueId, IrValueDefinition),
      value_types : Hash(ValueId, IrType),
      dominators : Hash(BlockId, Array(BlockId)),
      block_instructions : Hash(BlockId, Array(IrInstruction)),
      diagnostics : Array(String),
    ) : Nil
      expected_predecessors = predecessor_blocks[block_id]? || [] of BlockId
      actual_predecessors = [] of BlockId
      phi.incoming.each do |incoming|
        if actual_predecessors.includes?(incoming.predecessor_block_id)
          diagnostics << context.error("phi repeats predecessor block #{function_block_name(context.function, incoming.predecessor_block_id)}")
          next
        end
        actual_predecessors << incoming.predecessor_block_id
        unless expected_predecessors.includes?(incoming.predecessor_block_id)
          diagnostics << context.error("phi input block #{function_block_name(context.function, incoming.predecessor_block_id)} is not a predecessor")
          next
        end

        site = definition_sites[incoming.value_id]?
        unless site
          diagnostics << context.error("phi input %v#{incoming.value_id} is not defined")
          next
        end
        if type = value_types[incoming.value_id]?
          phi_type = phi.result_type.not_nil!
          if type != phi_type
            diagnostics << context.error("phi input %v#{incoming.value_id} has type #{type.label}, expected #{phi_type.label}")
          end
        end
        unless phi_value_available?(incoming.value_id, block_id, incoming.predecessor_block_id, predecessor_blocks, definition_sites, dominators, block_instructions)
          diagnostics << context.error("phi input %v#{incoming.value_id} is not available on predecessor edge from #{function_block_name(context.function, incoming.predecessor_block_id)}")
        end
      end

      unless actual_predecessors.sort == expected_predecessors.sort
        diagnostics << context.error("phi inputs do not match the block predecessors")
      end
    end

    private def phi_value_available?(
      value_id : ValueId,
      phi_block_id : BlockId,
      predecessor_id : BlockId,
      predecessor_blocks : Hash(BlockId, Array(BlockId)),
      definition_sites : Hash(ValueId, IrValueDefinition),
      dominators : Hash(BlockId, Array(BlockId)),
      block_instructions : Hash(BlockId, Array(IrInstruction)),
    ) : Bool
      definition = definition_sites[value_id]?
      return false unless definition
      if definition.edge_defined? && definition.defining_block_id == phi_block_id && definition.edge_source_block_id == predecessor_id
        return true
      end

      predecessor_instruction_count = block_instructions[predecessor_id]?.try(&.size) || 0
      value_available_at?(value_id, predecessor_id, predecessor_instruction_count, nil, predecessor_blocks, definition_sites, dominators)
    end

    private def value_available_at?(
      value_id : ValueId,
      use_block_id : BlockId,
      use_instruction_index : Int32,
      phi_predecessor_id : BlockId?,
      predecessor_blocks : Hash(BlockId, Array(BlockId)),
      definition_sites : Hash(ValueId, IrValueDefinition),
      dominators : Hash(BlockId, Array(BlockId)),
    ) : Bool
      definition = definition_sites[value_id]?
      return false unless definition

      if definition.edge_defined?
        edge_source = definition.edge_source_block_id.not_nil!
        if phi_predecessor_id == edge_source && definition.defining_block_id == use_block_id
          return true
        end

        defining_predecessors = predecessor_blocks[definition.defining_block_id]?
        return false unless defining_predecessors && defining_predecessors.size == 1 && defining_predecessors.first == edge_source
      end

      if definition.defining_block_id == use_block_id
        return definition.instruction_index < use_instruction_index
      end

      dominators[use_block_id]?.try(&.includes?(definition.defining_block_id)) || false
    end

    private def function_block_name(function : IrFunction, block_id : BlockId) : String
      function.block(block_id).try(&.name) || block_id.to_s
    end
  end

  class IrSExpressionDumper
    def dump(ir_module : IrModule) : String
      lines = ["(module"]
      ir_module.each_function do |function|
        append_function(lines, function)
      end
      lines << ")"
      lines.join("\n")
    end

    private def append_function(lines : Array(String), function : IrFunction) : Nil
      signature_items = function.parameters.map do |parameter|
        "(param %v#{parameter.value_id} #{parameter.type.label})"
      end
      signature_items << "(result #{function.signature.result_type.label})"
      lines << "  (func @#{function.name} #{signature_items.join(" ")}"

      function.each_block do |block|
        lines << "    (block @#{block.name}"
        block.instruction_ids.each do |instruction_id|
          instruction = function.instruction(instruction_id)
          raise IrBuildFailure.new("unknown instruction #{instruction_id} in function #{function.name}") unless instruction
          lines << "      #{instruction.dump(function)}"
        end
        lines << "    )"
      end

      lines << "  )"
    end
  end
end
