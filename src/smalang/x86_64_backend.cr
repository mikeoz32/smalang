module Smalang
  class X86_64BackendFailure < Exception
  end

  enum X86_64Register : UInt8
    Rax =  0
    Rcx =  1
    Rdx =  2
    Rbx =  3
    Rsp =  4
    Rbp =  5
    Rsi =  6
    Rdi =  7
    R8  =  8
    R9  =  9
    R10 = 10
    R11 = 11
    R12 = 12
    R13 = 13
    R14 = 14
    R15 = 15

    def code : UInt8
      to_i.to_u8 & 0x07_u8
    end

    def extended? : Bool
      to_i >= 8
    end
  end

  class ByteBuffer
    getter bytes : Array(UInt8)

    def initialize
      @bytes = [] of UInt8
    end

    def size : Int32
      @bytes.size
    end

    def write_u8(value : UInt8) : Nil
      @bytes << value
    end

    def write_u16(value : UInt16) : Nil
      write_u8((value & 0xff_u16).to_u8)
      write_u8(((value >> 8) & 0xff_u16).to_u8)
    end

    def write_u32(value : UInt32) : Nil
      4.times do |index|
        write_u8(((value >> (index * 8)) & 0xff_u32).to_u8)
      end
    end

    def write_i32(value : Int32) : Nil
      write_u32((value.to_i64 & 0xffff_ffff_i64).to_u32)
    end

    def write_u64(value : UInt64) : Nil
      8.times do |index|
        write_u8(((value >> (index * 8)) & 0xff_u64).to_u8)
      end
    end

    def write_i64(value : Int64) : Nil
      write_u64((value.to_i128 & 0xffff_ffff_ffff_ffff_i128).to_u64)
    end

    def write_bytes(values : Array(UInt8)) : Nil
      @bytes.concat(values)
    end

    def write_zeroes(count : Int32) : Nil
      count.times { write_u8(0_u8) }
    end

    def align(alignment : Int32) : Nil
      padding = (alignment - @bytes.size % alignment) % alignment
      write_zeroes(padding)
    end
  end

  abstract class ValueLocation
    abstract def load_to(code : X86_64CodeBuffer, destination : X86_64Register, frame : X86_64FrameLayout) : Nil
    abstract def store_from(code : X86_64CodeBuffer, source : X86_64Register, frame : X86_64FrameLayout) : Nil
    abstract def assigned_register : X86_64Register?
    abstract def spill_slot : Int32?
  end

  class RegisterValueLocation < ValueLocation
    getter register : X86_64Register

    def initialize(@register : X86_64Register)
    end

    def load_to(code : X86_64CodeBuffer, destination : X86_64Register, frame : X86_64FrameLayout) : Nil
      code.move_register(destination, @register) unless destination == @register
    end

    def store_from(code : X86_64CodeBuffer, source : X86_64Register, frame : X86_64FrameLayout) : Nil
      code.move_register(@register, source) unless @register == source
    end

    def assigned_register : X86_64Register?
      @register
    end

    def spill_slot : Int32?
      nil
    end
  end

  class SpillValueLocation < ValueLocation
    getter slot : Int32

    def initialize(@slot : Int32)
    end

    def load_to(code : X86_64CodeBuffer, destination : X86_64Register, frame : X86_64FrameLayout) : Nil
      code.move_register_from_rbp(destination, frame.spill_offset(@slot))
    end

    def store_from(code : X86_64CodeBuffer, source : X86_64Register, frame : X86_64FrameLayout) : Nil
      code.move_rbp_from_register(frame.spill_offset(@slot), source)
    end

    def assigned_register : X86_64Register?
      nil
    end

    def spill_slot : Int32?
      @slot
    end
  end

  abstract class MachineInstruction
    getter position : Int32

    def initialize(@position : Int32)
    end

    abstract def used_values : Array(ValueId)
    abstract def result_value_id : ValueId?
    abstract def emit(context : X86_64EmissionContext) : Nil

    def call_boundary? : Bool
      false
    end

    def outgoing_argument_count : Int32
      0
    end
  end

  class MachineConstant < MachineInstruction
    getter result_id : ValueId
    getter type : IrType
    getter value : Int128

    def initialize(position : Int32, @result_id : ValueId, @type : IrType, @value : Int128)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      immediate = context.constant_bits(@type, @value)
      context.code.move_immediate(X86_64Register::Rax, immediate)
      context.location(@result_id).store_from(context.code, X86_64Register::Rax, context.frame)
    end
  end

  abstract class MachineBinaryOperation
    abstract def apply_to_register(code : X86_64CodeBuffer, destination : X86_64Register, source : X86_64Register) : Nil
    abstract def apply_to_spill(code : X86_64CodeBuffer, destination : X86_64Register, offset : Int32) : Nil
  end

  class MachineAddOperation < MachineBinaryOperation
    def apply_to_register(code : X86_64CodeBuffer, destination : X86_64Register, source : X86_64Register) : Nil
      code.add_register(destination, source)
    end

    def apply_to_spill(code : X86_64CodeBuffer, destination : X86_64Register, offset : Int32) : Nil
      code.add_rbp_memory(destination, offset)
    end
  end

  class MachineSubtractOperation < MachineBinaryOperation
    def apply_to_register(code : X86_64CodeBuffer, destination : X86_64Register, source : X86_64Register) : Nil
      code.subtract_register(destination, source)
    end

    def apply_to_spill(code : X86_64CodeBuffer, destination : X86_64Register, offset : Int32) : Nil
      code.subtract_rbp_memory(destination, offset)
    end
  end

  class MachineBinary < MachineInstruction
    getter result_id : ValueId
    getter left_id : ValueId
    getter right_id : ValueId

    def initialize(position : Int32, @result_id : ValueId, @left_id : ValueId, @right_id : ValueId, @operation : MachineBinaryOperation)
      super(position)
    end

    def used_values : Array(ValueId)
      [@left_id, @right_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      left = context.location(@left_id)
      right = context.location(@right_id)
      result = context.location(@result_id)
      left.load_to(context.code, X86_64Register::Rax, context.frame)

      if register = right.assigned_register
        @operation.apply_to_register(context.code, X86_64Register::Rax, register)
      elsif slot = right.spill_slot
        @operation.apply_to_spill(context.code, X86_64Register::Rax, context.frame.spill_offset(slot))
      else
        raise X86_64BackendFailure.new("unsupported operand location")
      end

      result.store_from(context.code, X86_64Register::Rax, context.frame)
    end
  end

  class MachineCall < MachineInstruction
    getter result_id : ValueId
    getter function_id : FunctionId
    getter arguments : Array(ValueId)

    def initialize(position : Int32, @result_id : ValueId, @function_id : FunctionId, arguments : Array(ValueId))
      super(position)
      @arguments = arguments.dup
    end

    def used_values : Array(ValueId)
      @arguments.dup
    end

    def result_value_id : ValueId?
      @result_id
    end

    def call_boundary? : Bool
      true
    end

    def outgoing_argument_count : Int32
      @arguments.size
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_call(self)
    end
  end

  class MachineReturn < MachineInstruction
    getter value_id : ValueId

    def initialize(position : Int32, @value_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [@value_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.location(@value_id).load_to(context.code, X86_64Register::Rax, context.frame)
      context.code.emit_epilogue
    end
  end

  class X86_64InstructionSelector < IrInstructionVisitor
    @instructions : Array(MachineInstruction)

    def initialize
      @instructions = [] of MachineInstruction
    end

    def lower(function : IrFunction) : Array(MachineInstruction)
      @instructions.clear
      function.each_block do |block|
        block.instruction_ids.each do |instruction_id|
          instruction = function.instruction(instruction_id)
          raise X86_64BackendFailure.new("unknown IR instruction #{instruction_id}") unless instruction
          instruction.accept(self)
        end
      end
      @instructions.dup
    end

    def visit(instruction : IrConstantInstruction) : Nil
      result_id = instruction.result_id
      result_type = instruction.result_type
      raise X86_64BackendFailure.new("constant is missing its result") unless result_id && result_type
      @instructions << MachineConstant.new(@instructions.size, result_id, result_type, instruction.value)
    end

    def visit(instruction : IrAddInstruction) : Nil
      append_binary(instruction, MachineAddOperation.new)
    end

    def visit(instruction : IrSubtractInstruction) : Nil
      append_binary(instruction, MachineSubtractOperation.new)
    end

    def visit(instruction : IrCallInstruction) : Nil
      result_id = instruction.result_id
      function_id = instruction.target.module_function_id
      raise X86_64BackendFailure.new("call target is not an internal function") unless function_id
      raise X86_64BackendFailure.new("call is missing its result") unless result_id
      @instructions << MachineCall.new(@instructions.size, result_id, function_id, instruction.arguments)
    end

    def visit(instruction : IrReturnInstruction) : Nil
      @instructions << MachineReturn.new(@instructions.size, instruction.value_id)
    end

    private def append_binary(instruction : IrBinaryInstruction, operation : MachineBinaryOperation) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("binary operation is missing its result") unless result_id
      @instructions << MachineBinary.new(@instructions.size, result_id, instruction.left, instruction.right, operation)
    end
  end

  class LiveInterval
    getter value_id : ValueId
    getter start_position : Int32
    property last_use_position : Int32

    def initialize(@value_id : ValueId, @start_position : Int32, @last_use_position : Int32)
    end
  end

  struct ActiveInterval
    getter interval : LiveInterval
    getter register : X86_64Register

    def initialize(@interval : LiveInterval, @register : X86_64Register)
    end
  end

  struct CallSpill
    getter register : X86_64Register
    getter slot : Int32

    def initialize(@register : X86_64Register, @slot : Int32)
    end
  end

  class RegisterAllocation
    getter locations : Hash(ValueId, ValueLocation)
    getter call_spills : Hash(Int32, Array(CallSpill))
    getter spill_slot_count : Int32

    def initialize(@locations : Hash(ValueId, ValueLocation), @call_spills : Hash(Int32, Array(CallSpill)), @spill_slot_count : Int32)
    end

    def location(value_id : ValueId) : ValueLocation
      @locations[value_id]? || raise X86_64BackendFailure.new("no allocation for SSA value %v#{value_id}")
    end

    def call_spills_at(position : Int32) : Array(CallSpill)
      @call_spills[position]? || [] of CallSpill
    end
  end

  class LinearScanRegisterAllocator
    ALLOCATABLE_REGISTERS = [
      X86_64Register::Rcx,
      X86_64Register::Rdx,
      X86_64Register::Rsi,
      X86_64Register::Rdi,
      X86_64Register::R8,
      X86_64Register::R9,
      X86_64Register::R10,
      X86_64Register::R11,
    ]

    def allocate(function : IrFunction, instructions : Array(MachineInstruction)) : RegisterAllocation
      intervals = build_intervals(function, instructions)
      locations = {} of ValueId => ValueLocation
      active = [] of ActiveInterval
      spill_slot_count = 0

      intervals.sort_by(&.start_position).each do |interval|
        active = active.select { |entry| entry.interval.last_use_position >= interval.start_position }
        used_registers = active.map(&.register)
        available_register = ALLOCATABLE_REGISTERS.find { |register| !used_registers.includes?(register) }

        if register = available_register
          locations[interval.value_id] = RegisterValueLocation.new(register)
          active << ActiveInterval.new(interval, register)
          next
        end

        farthest_active = active.max_by(&.interval.last_use_position)
        unless farthest_active
          raise X86_64BackendFailure.new("no register available for SSA value %v#{interval.value_id}")
        end

        if farthest_active.interval.last_use_position > interval.last_use_position
          slot = spill_slot_count
          spill_slot_count += 1
          locations[farthest_active.interval.value_id] = SpillValueLocation.new(slot)
          locations[interval.value_id] = RegisterValueLocation.new(farthest_active.register)
          active.delete(farthest_active)
          active << ActiveInterval.new(interval, farthest_active.register)
        else
          locations[interval.value_id] = SpillValueLocation.new(spill_slot_count)
          spill_slot_count += 1
        end
      end

      call_spills = allocate_call_spills(intervals, instructions, locations, spill_slot_count)
      RegisterAllocation.new(locations, call_spills[:spills], call_spills[:slot_count])
    end

    private def build_intervals(function : IrFunction, instructions : Array(MachineInstruction)) : Array(LiveInterval)
      intervals = {} of ValueId => LiveInterval
      function.parameters.each do |parameter|
        intervals[parameter.value_id] = LiveInterval.new(parameter.value_id, -1, 0)
      end

      instructions.each do |instruction|
        if result_id = instruction.result_value_id
          intervals[result_id] = LiveInterval.new(result_id, instruction.position, instruction.position)
        end
      end

      instructions.each do |instruction|
        instruction.used_values.each do |value_id|
          interval = intervals[value_id]?
          raise X86_64BackendFailure.new("use of undefined SSA value %v#{value_id}") unless interval
          if interval.last_use_position < instruction.position
            interval.last_use_position = instruction.position
          end
        end
      end
      intervals.values.sort_by { |interval| {interval.start_position, interval.value_id} }
    end

    private def allocate_call_spills(
      intervals : Array(LiveInterval),
      instructions : Array(MachineInstruction),
      locations : Hash(ValueId, ValueLocation),
      next_spill_slot : Int32,
    ) : NamedTuple(spills: Hash(Int32, Array(CallSpill)), slot_count: Int32)
      call_spills = {} of Int32 => Array(CallSpill)
      spill_slots_by_value = {} of ValueId => Int32
      slot_count = next_spill_slot

      instructions.each do |instruction|
        next unless instruction.call_boundary?
        live_values = intervals.select do |interval|
          interval.start_position < instruction.position && interval.last_use_position > instruction.position
        end

        live_values.each do |interval|
          location = locations[interval.value_id]
          next unless register = location.assigned_register

          slot = spill_slots_by_value[interval.value_id]?
          unless slot
            slot = slot_count
            slot_count += 1
            spill_slots_by_value[interval.value_id] = slot
          end

          values = call_spills[instruction.position]? || [] of CallSpill
          values << CallSpill.new(register, slot)
          call_spills[instruction.position] = values
        end
      end

      {spills: call_spills, slot_count: slot_count}
    end
  end

  class X86_64FrameLayout
    getter frame_size : Int32

    @spill_offsets : Array(Int32)
    @argument_stage_offsets : Array(Int32)
    @outgoing_stack_argument_count : Int32

    def initialize(spill_slot_count : Int32, argument_stage_count : Int32, @outgoing_stack_argument_count : Int32)
      @spill_offsets = [] of Int32
      spill_slot_count.times do |slot|
        @spill_offsets << -((slot + 1) * 8)
      end

      @argument_stage_offsets = [] of Int32
      argument_stage_count.times do |index|
        @argument_stage_offsets << -((spill_slot_count + index + 1) * 8)
      end

      local_bytes = (spill_slot_count + argument_stage_count + @outgoing_stack_argument_count) * 8
      @frame_size = align_to(local_bytes, 16)
    end

    def spill_offset(slot : Int32) : Int32
      @spill_offsets[slot]? || raise X86_64BackendFailure.new("invalid spill slot #{slot}")
    end

    def argument_stage_offset(index : Int32) : Int32
      @argument_stage_offsets[index]? || raise X86_64BackendFailure.new("invalid staged argument #{index}")
    end

    def outgoing_stack_argument_offset(index : Int32) : Int32
      raise X86_64BackendFailure.new("invalid outgoing stack argument #{index}") if index < 0 || index >= @outgoing_stack_argument_count
      index * 8
    end

    private def align_to(value : Int32, alignment : Int32) : Int32
      ((value + alignment - 1) // alignment) * alignment
    end
  end

  class X86_64CodeBuffer
    getter bytes : Array(UInt8)

    def initialize
      @buffer = ByteBuffer.new
      @bytes = @buffer.bytes
    end

    def size : Int32
      @buffer.size
    end

    def move_register(destination : X86_64Register, source : X86_64Register) : Nil
      return if destination == source
      write_rex(true, source, destination)
      @buffer.write_u8(0x89_u8)
      write_modrm(0b11_u8, source, destination)
    end

    def move_immediate(destination : X86_64Register, value : UInt64) : Nil
      write_rex(true, X86_64Register::Rax, destination)
      @buffer.write_u8(0xb8_u8 + destination.code)
      @buffer.write_u64(value)
    end

    def move_register_from_rbp(destination : X86_64Register, offset : Int32) : Nil
      write_memory_move(destination, X86_64Register::Rbp, offset)
    end

    def move_rbp_from_register(offset : Int32, source : X86_64Register) : Nil
      write_memory_store(X86_64Register::Rbp, offset, source)
    end

    def move_rsp_from_register(offset : Int32, source : X86_64Register) : Nil
      write_memory_store(X86_64Register::Rsp, offset, source)
    end

    def add_register(destination : X86_64Register, source : X86_64Register) : Nil
      write_rex(true, source, destination)
      @buffer.write_u8(0x01_u8)
      write_modrm(0b11_u8, source, destination)
    end

    def add_rbp_memory(destination : X86_64Register, offset : Int32) : Nil
      write_rex(true, destination, X86_64Register::Rbp)
      @buffer.write_u8(0x03_u8)
      write_memory_operand(destination, X86_64Register::Rbp, offset)
    end

    def subtract_register(destination : X86_64Register, source : X86_64Register) : Nil
      write_rex(true, source, destination)
      @buffer.write_u8(0x29_u8)
      write_modrm(0b11_u8, source, destination)
    end

    def subtract_rbp_memory(destination : X86_64Register, offset : Int32) : Nil
      write_rex(true, destination, X86_64Register::Rbp)
      @buffer.write_u8(0x2b_u8)
      write_memory_operand(destination, X86_64Register::Rbp, offset)
    end

    def emit_prologue(frame_size : Int32) : Nil
      @buffer.write_u8(0x55_u8)
      @buffer.write_bytes([0x48_u8, 0x89_u8, 0xe5_u8])
      return if frame_size == 0
      @buffer.write_bytes([0x48_u8, 0x81_u8, 0xec_u8])
      @buffer.write_u32(frame_size.to_u32)
    end

    def emit_epilogue : Nil
      @buffer.write_bytes([0x48_u8, 0x89_u8, 0xec_u8])
      @buffer.write_bytes([0x5d_u8, 0xc3_u8])
    end

    def emit_call : Int32
      @buffer.write_u8(0xe8_u8)
      displacement_offset = @buffer.size
      @buffer.write_u32(0_u32)
      displacement_offset
    end

    def align(alignment : Int32) : Nil
      padding = (alignment - @buffer.size % alignment) % alignment
      padding.times { @buffer.write_u8(0x90_u8) }
    end

    private def write_memory_move(destination : X86_64Register, base : X86_64Register, offset : Int32) : Nil
      write_rex(true, destination, base)
      @buffer.write_u8(0x8b_u8)
      write_memory_operand(destination, base, offset)
    end

    private def write_memory_store(base : X86_64Register, offset : Int32, source : X86_64Register) : Nil
      write_rex(true, source, base)
      @buffer.write_u8(0x89_u8)
      write_memory_operand(source, base, offset)
    end

    private def write_memory_operand(reg_field : X86_64Register, base : X86_64Register, offset : Int32) : Nil
      write_modrm(0b10_u8, reg_field, base)
      @buffer.write_i32(offset)
    end

    private def write_modrm(mode : UInt8, reg_field : X86_64Register, rm_field : X86_64Register) : Nil
      value = (mode << 6) | (reg_field.code << 3) | rm_field.code
      @buffer.write_u8(value)
      @buffer.write_u8(0x24_u8) if mode != 0b11_u8 && rm_field == X86_64Register::Rsp
    end

    private def write_rex(wide : Bool, reg_field : X86_64Register, rm_field : X86_64Register) : Nil
      prefix = 0x40_u8
      prefix |= 0x08_u8 if wide
      prefix |= 0x04_u8 if reg_field.extended?
      prefix |= 0x01_u8 if rm_field.extended?
      @buffer.write_u8(prefix)
    end
  end

  struct X86_64Relocation
    getter offset : Int32
    getter function_id : FunctionId

    def initialize(@offset : Int32, @function_id : FunctionId)
    end
  end

  class X86_64EmissionContext
    ARGUMENT_REGISTERS = [
      X86_64Register::Rdi,
      X86_64Register::Rsi,
      X86_64Register::Rdx,
      X86_64Register::Rcx,
      X86_64Register::R8,
      X86_64Register::R9,
    ]

    getter code : X86_64CodeBuffer
    getter frame : X86_64FrameLayout
    getter relocations : Array(X86_64Relocation)

    @allocation : RegisterAllocation

    def initialize(@code : X86_64CodeBuffer, @frame : X86_64FrameLayout, @allocation : RegisterAllocation)
      @relocations = [] of X86_64Relocation
    end

    def location(value_id : ValueId) : ValueLocation
      @allocation.location(value_id)
    end

    def constant_bits(type : IrType, value : Int128) : UInt64
      case type
      when IrType::Isize
        if value < Int64::MIN.to_i128 || value > Int64::MAX.to_i128
          raise X86_64BackendFailure.new("constant #{value} does not fit isize on x86_64")
        end
        (value.to_i128 & 0xffff_ffff_ffff_ffff_i128).to_u64
      when IrType::Usize
        if value < 0 || value > UInt64::MAX.to_i128
          raise X86_64BackendFailure.new("constant #{value} does not fit usize on x86_64")
        end
        value.to_u64
      else
        raise X86_64BackendFailure.new("unsupported integer type #{type}")
      end
    end

    def initialize_parameters(function : IrFunction) : Nil
      parameters = function.parameters
      staged_count = {parameters.size, ARGUMENT_REGISTERS.size}.min

      staged_count.times do |index|
        @code.move_rbp_from_register(@frame.argument_stage_offset(index), ARGUMENT_REGISTERS[index])
      end

      parameters.each_with_index do |parameter, index|
        if index < staged_count
          @code.move_register_from_rbp(X86_64Register::Rax, @frame.argument_stage_offset(index))
        else
          stack_offset = 16 + (index - ARGUMENT_REGISTERS.size) * 8
          @code.move_register_from_rbp(X86_64Register::Rax, stack_offset)
        end
        location(parameter.value_id).store_from(@code, X86_64Register::Rax, @frame)
      end
    end

    def emit_call(call : MachineCall) : Nil
      @allocation.call_spills_at(call.position).each do |spill|
        @code.move_rbp_from_register(@frame.spill_offset(spill.slot), spill.register)
      end

      call.arguments.each_with_index do |value_id, index|
        location(value_id).load_to(@code, X86_64Register::Rax, @frame)
        if index < ARGUMENT_REGISTERS.size
          @code.move_rbp_from_register(@frame.argument_stage_offset(index), X86_64Register::Rax)
        else
          stack_index = index - ARGUMENT_REGISTERS.size
          @code.move_rsp_from_register(@frame.outgoing_stack_argument_offset(stack_index), X86_64Register::Rax)
        end
      end

      call.arguments.each_with_index do |_, index|
        break if index >= ARGUMENT_REGISTERS.size
        @code.move_register_from_rbp(ARGUMENT_REGISTERS[index], @frame.argument_stage_offset(index))
      end

      relocation_offset = @code.emit_call
      @relocations << X86_64Relocation.new(relocation_offset, call.function_id)

      @allocation.call_spills_at(call.position).each do |spill|
        @code.move_register_from_rbp(spill.register, @frame.spill_offset(spill.slot))
      end
      location(call.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end
  end

  struct EmittedFunction
    getter function : IrFunction
    getter bytes : Array(UInt8)
    getter relocations : Array(X86_64Relocation)

    def initialize(@function : IrFunction, @bytes : Array(UInt8), @relocations : Array(X86_64Relocation))
    end
  end

  class X86_64FunctionEmitter
    def emit(function : IrFunction) : EmittedFunction
      instructions = X86_64InstructionSelector.new.lower(function)
      allocation = LinearScanRegisterAllocator.new.allocate(function, instructions)
      max_outgoing_arguments = instructions.map(&.outgoing_argument_count).max? || 0
      argument_register_count = X86_64EmissionContext::ARGUMENT_REGISTERS.size
      parameter_stage_count = {function.parameters.size, argument_register_count}.min
      call_stage_count = {max_outgoing_arguments, argument_register_count}.min
      staged_argument_count = parameter_stage_count > call_stage_count ? parameter_stage_count : call_stage_count
      outgoing_stack_argument_count = max_outgoing_arguments > argument_register_count ? max_outgoing_arguments - argument_register_count : 0
      frame = X86_64FrameLayout.new(allocation.spill_slot_count, staged_argument_count, outgoing_stack_argument_count)
      code = X86_64CodeBuffer.new
      code.emit_prologue(frame.frame_size)
      context = X86_64EmissionContext.new(code, frame, allocation)
      context.initialize_parameters(function)
      instructions.each(&.emit(context))

      EmittedFunction.new(function, code.bytes.dup, context.relocations.dup)
    end
  end

  struct ElfFunctionSymbol
    getter function : IrFunction
    getter offset : Int32
    getter size : Int32

    def initialize(@function : IrFunction, @offset : Int32, @size : Int32)
    end

    def global? : Bool
      @function.name == "main"
    end

    def elf_name : String
      global? ? "main" : ".Lsmalang_fn_#{@function.id}"
    end
  end

  class ElfStringTable
    getter bytes : Array(UInt8)

    @offsets : Hash(String, UInt32)

    def initialize
      @bytes = [0_u8]
      @offsets = {} of String => UInt32
    end

    def add(value : String) : UInt32
      return 0_u32 if value.empty?
      if offset = @offsets[value]?
        return offset
      end

      offset = @bytes.size.to_u32
      value.to_slice.each { |byte| @bytes << byte }
      @bytes << 0_u8
      @offsets[value] = offset
      offset
    end
  end

  struct ElfSymbolEntry
    getter name_offset : UInt32
    getter info : UInt8
    getter section_index : UInt16
    getter value : UInt64
    getter size : UInt64

    def initialize(@name_offset : UInt32, @info : UInt8, @section_index : UInt16, @value : UInt64, @size : UInt64)
    end

    def write_to(buffer : ByteBuffer) : Nil
      buffer.write_u32(@name_offset)
      buffer.write_u8(@info)
      buffer.write_u8(0_u8)
      buffer.write_u16(@section_index)
      buffer.write_u64(@value)
      buffer.write_u64(@size)
    end
  end

  struct ElfSectionHeader
    getter name_offset : UInt32
    getter type : UInt32
    getter flags : UInt64
    getter offset : UInt64
    getter size : UInt64
    getter link : UInt32
    getter info : UInt32
    getter alignment : UInt64
    getter entry_size : UInt64

    def initialize(
      @name_offset : UInt32,
      @type : UInt32,
      @flags : UInt64,
      @offset : UInt64,
      @size : UInt64,
      @link : UInt32,
      @info : UInt32,
      @alignment : UInt64,
      @entry_size : UInt64,
    )
    end

    def write_to(buffer : ByteBuffer) : Nil
      buffer.write_u32(@name_offset)
      buffer.write_u32(@type)
      buffer.write_u64(@flags)
      buffer.write_u64(0_u64)
      buffer.write_u64(@offset)
      buffer.write_u64(@size)
      buffer.write_u32(@link)
      buffer.write_u32(@info)
      buffer.write_u64(@alignment)
      buffer.write_u64(@entry_size)
    end
  end

  class X86_64ElfObjectWriter
    ET_REL         =   1_u16
    EM_X86_64      =  62_u16
    SHT_NULL       =   0_u32
    SHT_PROGBITS   =   1_u32
    SHT_SYMTAB     =   2_u32
    SHT_STRTAB     =   3_u32
    SHT_RELA       =   4_u32
    SHF_ALLOC      = 0x2_u64
    SHF_EXECINSTR  = 0x4_u64
    STB_LOCAL      =    0_u8
    STB_GLOBAL     =    1_u8
    STT_FUNC       =    2_u8
    STT_SECTION    =    3_u8
    R_X86_64_PLT32 =   4_u32

    def write(text : Array(UInt8), functions : Array(ElfFunctionSymbol), relocations : Array(X86_64Relocation)) : Array(UInt8)
      ensure_unique_main(functions)

      string_table = ElfStringTable.new
      symbols, symbol_indices, first_global_symbol = build_symbols(functions, string_table)
      rela_bytes = encode_relocations(relocations, symbol_indices)
      symbol_bytes = encode_symbols(symbols)
      section_names = ElfStringTable.new
      section_headers, section_data = build_sections(text, rela_bytes, symbol_bytes, string_table.bytes, section_names)
      write_object(section_headers, section_data, first_global_symbol)
    end

    private def ensure_unique_main(functions : Array(ElfFunctionSymbol)) : Nil
      main_count = functions.count(&.global?)
      raise X86_64BackendFailure.new("module contains more than one main function") if main_count > 1
    end

    private def build_symbols(
      functions : Array(ElfFunctionSymbol),
      strings : ElfStringTable,
    ) : Tuple(Array(ElfSymbolEntry), Hash(FunctionId, UInt32), UInt32)
      symbols = [ElfSymbolEntry.new(0_u32, 0_u8, 0_u16, 0_u64, 0_u64)]
      symbols << ElfSymbolEntry.new(0_u32, (STB_LOCAL << 4) | STT_SECTION, 1_u16, 0_u64, 0_u64)
      function_indices = {} of FunctionId => UInt32
      local_functions = functions.reject(&.global?)
      global_functions = functions.select(&.global?)

      local_functions.each do |function_symbol|
        name_offset = strings.add(function_symbol.elf_name)
        symbols << build_function_symbol(function_symbol, name_offset, STB_LOCAL)
        function_indices[function_symbol.function.id] = (symbols.size - 1).to_u32
      end

      first_global_symbol = symbols.size.to_u32
      global_functions.each do |function_symbol|
        name_offset = strings.add(function_symbol.elf_name)
        symbols << build_function_symbol(function_symbol, name_offset, STB_GLOBAL)
        function_indices[function_symbol.function.id] = (symbols.size - 1).to_u32
      end

      {symbols, function_indices, first_global_symbol}
    end

    private def build_function_symbol(function_symbol : ElfFunctionSymbol, name_offset : UInt32, binding : UInt8) : ElfSymbolEntry
      info = (binding << 4) | STT_FUNC
      ElfSymbolEntry.new(name_offset, info, 1_u16, function_symbol.offset.to_u64, function_symbol.size.to_u64)
    end

    private def encode_symbols(symbols : Array(ElfSymbolEntry)) : Array(UInt8)
      buffer = ByteBuffer.new
      symbols.each(&.write_to(buffer))
      buffer.bytes
    end

    private def encode_relocations(
      relocations : Array(X86_64Relocation),
      symbol_indices : Hash(FunctionId, UInt32),
    ) : Array(UInt8)
      buffer = ByteBuffer.new
      relocations.each do |relocation|
        symbol_index = symbol_indices[relocation.function_id]?
        raise X86_64BackendFailure.new("missing ELF symbol for function #{relocation.function_id}") unless symbol_index
        info = (symbol_index.to_u64 << 32) | R_X86_64_PLT32.to_u64
        buffer.write_u64(relocation.offset.to_u64)
        buffer.write_u64(info)
        buffer.write_i64(-4_i64)
      end
      buffer.bytes
    end

    private def build_sections(
      text : Array(UInt8),
      rela : Array(UInt8),
      symbols : Array(UInt8),
      strings : Array(UInt8),
      section_names : ElfStringTable,
    ) : Tuple(Array(ElfSectionHeader), Array(NamedTuple(name: String, bytes: Array(UInt8), alignment: Int32)))
      text_name = section_names.add(".text")
      rela_name = section_names.add(".rela.text")
      symtab_name = section_names.add(".symtab")
      strtab_name = section_names.add(".strtab")
      shstrtab_name = section_names.add(".shstrtab")
      stack_name = section_names.add(".note.GNU-stack")

      data = [
        {name: ".text", bytes: text, alignment: 16},
        {name: ".rela.text", bytes: rela, alignment: 8},
        {name: ".symtab", bytes: symbols, alignment: 8},
        {name: ".strtab", bytes: strings, alignment: 1},
        {name: ".shstrtab", bytes: section_names.bytes, alignment: 1},
        {name: ".note.GNU-stack", bytes: [] of UInt8, alignment: 1},
      ]

      headers = [ElfSectionHeader.new(0_u32, SHT_NULL, 0_u64, 0_u64, 0_u64, 0_u32, 0_u32, 0_u64, 0_u64)]
      offsets = {} of String => UInt64
      cursor = 64
      data.each do |section|
        cursor = align_to(cursor, section[:alignment])
        offsets[section[:name]] = cursor.to_u64
        cursor += section[:bytes].size
      end

      headers << ElfSectionHeader.new(text_name, SHT_PROGBITS, SHF_ALLOC | SHF_EXECINSTR, offsets[".text"], text.size.to_u64, 0_u32, 0_u32, 16_u64, 0_u64)
      headers << ElfSectionHeader.new(rela_name, SHT_RELA, 0_u64, offsets[".rela.text"], rela.size.to_u64, 3_u32, 1_u32, 8_u64, 24_u64)
      headers << ElfSectionHeader.new(symtab_name, SHT_SYMTAB, 0_u64, offsets[".symtab"], symbols.size.to_u64, 4_u32, 0_u32, 8_u64, 24_u64)
      headers << ElfSectionHeader.new(strtab_name, SHT_STRTAB, 0_u64, offsets[".strtab"], strings.size.to_u64, 0_u32, 0_u32, 1_u64, 0_u64)
      headers << ElfSectionHeader.new(shstrtab_name, SHT_STRTAB, 0_u64, offsets[".shstrtab"], section_names.bytes.size.to_u64, 0_u32, 0_u32, 1_u64, 0_u64)
      headers << ElfSectionHeader.new(stack_name, SHT_PROGBITS, 0_u64, offsets[".note.GNU-stack"], 0_u64, 0_u32, 0_u32, 1_u64, 0_u64)

      {headers, data}
    end

    private def write_object(
      headers : Array(ElfSectionHeader),
      sections : Array(NamedTuple(name: String, bytes: Array(UInt8), alignment: Int32)),
      first_global_symbol : UInt32,
    ) : Array(UInt8)
      buffer = ByteBuffer.new
      buffer.write_zeroes(64)
      sections.each do |section|
        buffer.align(section[:alignment])
        buffer.write_bytes(section[:bytes])
      end
      buffer.align(8)
      section_header_offset = buffer.size
      headers.each_with_index do |header, index|
        if index == 3
          header = ElfSectionHeader.new(header.name_offset, header.type, header.flags, header.offset, header.size, header.link, first_global_symbol, header.alignment, header.entry_size)
        end
        header.write_to(buffer)
      end
      write_elf_header(buffer.bytes, section_header_offset.to_u64, headers.size.to_u16, 5_u16)
    end

    private def write_elf_header(file_bytes : Array(UInt8), section_header_offset : UInt64, section_count : UInt16, section_name_index : UInt16) : Array(UInt8)
      header = ByteBuffer.new
      header.write_bytes([0x7f_u8, 0x45_u8, 0x4c_u8, 0x46_u8, 2_u8, 1_u8, 1_u8, 0_u8, 0_u8])
      header.write_zeroes(7)
      header.write_u16(ET_REL)
      header.write_u16(EM_X86_64)
      header.write_u32(1_u32)
      header.write_u64(0_u64)
      header.write_u64(0_u64)
      header.write_u64(section_header_offset)
      header.write_u32(0_u32)
      header.write_u16(64_u16)
      header.write_u16(0_u16)
      header.write_u16(0_u16)
      header.write_u16(64_u16)
      header.write_u16(section_count)
      header.write_u16(section_name_index)

      result = file_bytes.dup
      header.bytes.each_with_index { |byte, index| result[index] = byte }
      result
    end

    private def align_to(value : Int32, alignment : Int32) : Int32
      ((value + alignment - 1) // alignment) * alignment
    end
  end

  class X86_64Backend
    def emit(ir_module : IrModule) : Array(UInt8)
      diagnostics = ir_module.verify
      unless diagnostics.empty?
        raise X86_64BackendFailure.new("cannot emit invalid IR:\n#{diagnostics.join("\n")}")
      end

      text = ByteBuffer.new
      function_symbols = [] of ElfFunctionSymbol
      relocations = [] of X86_64Relocation
      ir_module.each_function do |function|
        text.align(16)
        text_offset = text.size
        emitted = X86_64FunctionEmitter.new.emit(function)
        text.write_bytes(emitted.bytes)
        function_symbols << ElfFunctionSymbol.new(function, text_offset, emitted.bytes.size)
        emitted.relocations.each do |relocation|
          relocations << X86_64Relocation.new(text_offset + relocation.offset, relocation.function_id)
        end
      end

      X86_64ElfObjectWriter.new.write(text.bytes, function_symbols, relocations)
    end
  end
end
