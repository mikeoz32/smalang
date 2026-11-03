module Smalang
  alias FunctionId = Int32
  alias ValueId = Int32
  alias InstructionId = Int32
  alias BlockId = Int32

  enum IrType : UInt8
    Isize
    Usize

    def label : String
      to_s.downcase
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

    def initialize(@type : IrType, @defining_instruction_id : InstructionId?)
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

  abstract class IrInstructionVisitor
    abstract def visit(instruction : IrConstantInstruction) : Nil
    abstract def visit(instruction : IrAddInstruction) : Nil
    abstract def visit(instruction : IrSubtractInstruction) : Nil
    abstract def visit(instruction : IrCallInstruction) : Nil
    abstract def visit(instruction : IrReturnInstruction) : Nil
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
      [] of String
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

  class IrCallInstruction < IrInstruction
    getter target : IrCallTarget

    @arguments : Array(ValueId)

    def initialize(id : InstructionId, block_id : BlockId, result_id : ValueId, result_type : IrType, @target : IrCallTarget, arguments : Array(ValueId))
      super(id, block_id, result_id, result_type)
      @arguments = arguments.dup
    end

    def arguments : Array(ValueId)
      @arguments.dup
    end

    def used_values : Array(ValueId)
      @arguments.dup
    end

    def terminator? : Bool
      false
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

      result_type = @result_type
      if result_type && result_type != signature.result_type
        errors << context.error("call result has type #{result_type.label}, expected #{signature.result_type.label}")
      end
      errors
    end

    def expression : String
      operands = @arguments.map { |value_id| "%v#{value_id}" }
      call = (["call", @target.symbol] + operands).join(" ")
      "(%v#{@result_id.not_nil!} #{@result_type.not_nil!.label} (#{call}))"
    end

    def accept(visitor : IrInstructionVisitor) : Nil
      visitor.visit(self)
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
        @values << IrValueInfo.new(type, nil)
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

    def emit_call(block_id : BlockId, target : IrCallTarget, arguments : Array(ValueId), result_type : IrType) : ValueId
      append_result(block_id, result_type) do |instruction_id, result_id|
        IrCallInstruction.new(instruction_id, block_id, result_id, result_type, target, arguments)
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

    private def append_result(block_id : BlockId, type : IrType, &build : InstructionId, ValueId -> IrInstruction) : ValueId
      block = require_block(block_id)
      instruction_id = @instructions.size
      result_id = @values.size
      instruction = build.call(instruction_id, result_id)

      @instructions << instruction
      @values << IrValueInfo.new(type, instruction_id)
      block.append_instruction(instruction_id)
      result_id
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
      available_types = {} of ValueId => IrType

      function.parameters.each_with_index do |parameter, index|
        if available_types.has_key?(parameter.value_id)
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
        else
          diagnostics << context.error("parameter %v#{parameter.value_id} has no value metadata")
        end

        if parameter.value_id != index
          diagnostics << context.error("parameter #{index} has unexpected value id %v#{parameter.value_id}")
        end
        available_types[parameter.value_id] = parameter.type
      end

      if function.block_count != 1
        diagnostics << context.error("must contain exactly one entry block in this IR subset")
      end

      unless function.block(function.entry_block_id)
        diagnostics << context.error("entry block #{function.entry_block_id} does not exist")
      end

      seen_instruction_ids = {} of InstructionId => Bool
      saw_terminator = false
      function.each_block do |basic_block|
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

          if instruction.block_id != basic_block.id
            diagnostics << context.error("instruction #{instruction_id} belongs to block #{instruction.block_id}, not #{basic_block.id}")
          end
          if saw_terminator
            diagnostics << context.error("instruction #{instruction_id} appears after a terminator")
          end

          operand_types = instruction.used_values.map do |value_id|
            value_type = available_types[value_id]?
            unless value_type
              diagnostics << context.error("%v#{value_id} is not defined before use")
            end
            value_type
          end
          diagnostics.concat(instruction.validate(context, operand_types))

          if result_id = instruction.result_id
            if result_type = instruction.result_type
              if available_types.has_key?(result_id)
                diagnostics << context.error("duplicate definition of %v#{result_id}")
              else
                if info = function.value_info(result_id)
                  if info.type != result_type
                    diagnostics << context.error("%v#{result_id} metadata has type #{info.type.label}, instruction defines #{result_type.label}")
                  end
                  if info.defining_instruction_id != instruction.id
                    diagnostics << context.error("%v#{result_id} points to the wrong defining instruction")
                  end
                else
                  diagnostics << context.error("%v#{result_id} has no value metadata")
                end
                available_types[result_id] = result_type
              end
            else
              diagnostics << context.error("instruction #{instruction_id} defines %v#{result_id} without a result type")
            end
          elsif instruction.result_type
            diagnostics << context.error("instruction #{instruction_id} has a result type without a result value")
          end

          if instruction.terminator?
            if index != basic_block.instruction_ids.size - 1
              diagnostics << context.error("terminator must be the final instruction in its block")
            end
            saw_terminator = true
          end
        end
      end

      if seen_instruction_ids.size != function.instruction_count
        diagnostics << context.error("some instructions are not attached to a block")
      end
      unless saw_terminator
        diagnostics << context.error("must end with return")
      end
      if available_types.size != function.value_count
        diagnostics << context.error("contains unreferenced SSA value definitions")
      end

      diagnostics
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
          lines << "      #{instruction.expression}"
        end
        lines << "    )"
      end

      lines << "  )"
    end
  end
end
