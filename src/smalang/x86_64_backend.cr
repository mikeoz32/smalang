module Smalang
  module X86_64RuntimeSymbols
    ENTRY               = -1
    DIVISION_BY_ZERO    = -2
    EXCEPTION_RELEASE   = -3
    REPORT_UNCAUGHT     = -4
    INDEX_OUT_OF_BOUNDS = -5
    OUT_OF_MEMORY       = -6
  end

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

    def overwrite_u32(offset : Int32, value : UInt32) : Nil
      4.times do |index|
        @bytes[offset + index] = ((value >> (index * 8)) & 0xff_u32).to_u8
      end
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

  class ArrayValueLocation < ValueLocation
    getter value_id : ValueId

    def initialize(@value_id : ValueId)
    end

    def load_to(code : X86_64CodeBuffer, destination : X86_64Register, frame : X86_64FrameLayout) : Nil
      code.lea_rbp_relative(destination, frame.array_offset(@value_id))
    end

    def store_from(code : X86_64CodeBuffer, source : X86_64Register, frame : X86_64FrameLayout) : Nil
      frame.copy_address_to_array(code, source, @value_id)
    end

    def assigned_register : X86_64Register?
      nil
    end

    def spill_slot : Int32?
      nil
    end
  end

  class UnitValueLocation < ValueLocation
    def load_to(code : X86_64CodeBuffer, destination : X86_64Register, frame : X86_64FrameLayout) : Nil
    end

    def store_from(code : X86_64CodeBuffer, source : X86_64Register, frame : X86_64FrameLayout) : Nil
    end

    def assigned_register : X86_64Register?
      nil
    end

    def spill_slot : Int32?
      nil
    end
  end

  abstract class MachineInstruction
    getter position : Int32

    def initialize(@position : Int32)
    end

    abstract def used_values : Array(ValueId)
    abstract def result_value_id : ValueId?
    abstract def emit(context : X86_64EmissionContext) : Nil

    def defined_value_ids : Array(ValueId)
      result = result_value_id
      result ? [result] : Array(ValueId).new
    end

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

  class MachineUnitConstant < MachineInstruction
    getter result_id : ValueId

    def initialize(position : Int32, @result_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
    end
  end

  class MachineArrayLiteral < MachineInstruction
    getter result_id : ValueId
    getter array_type : IrArrayType
    getter elements : Array(ValueId)

    def initialize(position : Int32, @result_id : ValueId, @array_type : IrArrayType, elements : Array(ValueId))
      super(position)
      @elements = elements.dup
    end

    def used_values : Array(ValueId)
      @elements.dup
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_array_literal(self)
    end
  end

  class MachineStackAllocate < MachineInstruction
    getter instruction_id : InstructionId
    getter result_id : ValueId
    getter initial_value_id : ValueId
    getter pointer_type : IrPointerType

    def initialize(position : Int32, @instruction_id : InstructionId, @result_id : ValueId, @initial_value_id : ValueId, @pointer_type : IrPointerType)
      super(position)
    end

    def used_values : Array(ValueId)
      [@initial_value_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_stack_allocate(self)
    end
  end

  class MachineStackStorage < MachineInstruction
    getter instruction_id : InstructionId
    getter result_id : ValueId
    getter byte_size : UInt64
    getter alignment : UInt64

    def initialize(position : Int32, @instruction_id : InstructionId, @result_id : ValueId, @byte_size : UInt64, @alignment : UInt64)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_stack_storage(self)
    end
  end

  class MachinePointerOffset < MachineInstruction
    getter result_id : ValueId
    getter address_id : ValueId
    getter index_id : ValueId
    getter pointer_type : IrPointerType

    def initialize(position : Int32, @result_id : ValueId, @address_id : ValueId, @index_id : ValueId, @pointer_type : IrPointerType)
      super(position)
    end

    def used_values : Array(ValueId)
      [@address_id, @index_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_pointer_offset(self)
    end
  end

  class MachinePointerCast < MachineInstruction
    getter result_id : ValueId
    getter address_id : ValueId

    def initialize(position : Int32, @result_id : ValueId, @address_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [@address_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_pointer_cast(self)
    end
  end

  class MachinePointerLoad < MachineInstruction
    getter result_id : ValueId
    getter address_id : ValueId
    getter pointer_type : IrPointerType

    def initialize(position : Int32, @result_id : ValueId, @address_id : ValueId, @pointer_type : IrPointerType)
      super(position)
    end

    def used_values : Array(ValueId)
      [@address_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_pointer_load(self)
    end
  end

  class MachinePointerStore < MachineInstruction
    getter address_id : ValueId
    getter value_id : ValueId
    getter pointer_type : IrPointerType

    def initialize(position : Int32, @address_id : ValueId, @value_id : ValueId, @pointer_type : IrPointerType)
      super(position)
    end

    def used_values : Array(ValueId)
      [@address_id, @value_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_pointer_store(self)
    end
  end

  class MachinePointerFree < MachineInstruction
    getter address_id : ValueId
    getter pointer_type : IrPointerType

    def initialize(position : Int32, @address_id : ValueId, @pointer_type : IrPointerType)
      super(position)
    end

    def used_values : Array(ValueId)
      [@address_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def call_boundary? : Bool
      true
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_pointer_free(self)
    end
  end

  class MachineAllocate < MachineInstruction
    getter result_id : ValueId
    getter exception_id : ValueId
    getter initial_value_id : ValueId
    getter pointer_type : IrPointerType
    getter normal_successor_label : Int32
    getter exception_successor_label : Int32

    def initialize(
      position : Int32,
      @result_id : ValueId,
      @exception_id : ValueId,
      @initial_value_id : ValueId,
      @pointer_type : IrPointerType,
      @normal_successor_label : Int32,
      @exception_successor_label : Int32,
    )
      super(position)
    end

    def used_values : Array(ValueId)
      [@initial_value_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def defined_value_ids : Array(ValueId)
      [@result_id, @exception_id]
    end

    def call_boundary? : Bool
      true
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_allocate(self)
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

  class MachineMultiplyOperation < MachineBinaryOperation
    def apply_to_register(code : X86_64CodeBuffer, destination : X86_64Register, source : X86_64Register) : Nil
      code.multiply_register(destination, source)
    end

    def apply_to_spill(code : X86_64CodeBuffer, destination : X86_64Register, offset : Int32) : Nil
      code.multiply_rbp_memory(destination, offset)
    end
  end

  class MachineBinary < MachineInstruction
    getter result_id : ValueId
    getter left_id : ValueId
    getter right_id : ValueId
    getter type : IrType

    def initialize(
      position : Int32,
      @result_id : ValueId,
      @left_id : ValueId,
      @right_id : ValueId,
      @type : IrType,
      @operation : MachineBinaryOperation,
    )
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

      context.normalize_integer_register(X86_64Register::Rax, @type)
      result.store_from(context.code, X86_64Register::Rax, context.frame)
    end
  end

  class MachineCall < MachineInstruction
    getter result_id : ValueId
    getter exception_id : ValueId
    getter function_id : FunctionId
    getter arguments : Array(ValueId)
    getter result_type : IrType
    getter normal_successor_label : Int32
    getter exception_successor_label : Int32

    @argument_types : Array(IrType)

    def initialize(
      position : Int32,
      @result_id : ValueId,
      @exception_id : ValueId,
      @function_id : FunctionId,
      @result_type : IrType,
      arguments : Array(ValueId),
      argument_types : Array(IrType),
      @normal_successor_label : Int32,
      @exception_successor_label : Int32,
    )
      super(position)
      @arguments = arguments.dup
      @argument_types = argument_types.dup
    end

    def argument_types : Array(IrType)
      @argument_types.dup
    end

    def used_values : Array(ValueId)
      @arguments.dup
    end

    def result_value_id : ValueId?
      @result_id
    end

    def defined_value_ids : Array(ValueId)
      [@result_id, @exception_id]
    end

    def call_boundary? : Bool
      true
    end

    def outgoing_argument_count : Int32
      @argument_types.count { |type| !type.zero_sized? } + (@result_type.is_a?(IrArrayType) && !@result_type.zero_sized? ? 1 : 0)
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_invoke(self)
    end
  end

  class MachineArrayAccess < MachineInstruction
    getter result_id : ValueId
    getter exception_id : ValueId
    getter array_id : ValueId
    getter index_id : ValueId
    getter array_type : IrArrayType
    getter normal_successor_label : Int32
    getter exception_successor_label : Int32

    def initialize(
      position : Int32,
      @result_id : ValueId,
      @exception_id : ValueId,
      @array_id : ValueId,
      @index_id : ValueId,
      @array_type : IrArrayType,
      @normal_successor_label : Int32,
      @exception_successor_label : Int32,
    )
      super(position)
    end

    def used_values : Array(ValueId)
      [@array_id, @index_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def defined_value_ids : Array(ValueId)
      [@result_id, @exception_id]
    end

    def call_boundary? : Bool
      true
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_array_get(self)
    end
  end

  class MachineArrayUpdate < MachineArrayAccess
    getter value_id : ValueId

    def initialize(
      position : Int32,
      result_id : ValueId,
      exception_id : ValueId,
      array_id : ValueId,
      index_id : ValueId,
      @value_id : ValueId,
      array_type : IrArrayType,
      normal_successor_label : Int32,
      exception_successor_label : Int32,
    )
      super(position, result_id, exception_id, array_id, index_id, array_type, normal_successor_label, exception_successor_label)
    end

    def used_values : Array(ValueId)
      super + [@value_id]
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_array_set(self)
    end
  end

  class MachineIntegerDivision < MachineInstruction
    getter result_id : ValueId
    getter exception_id : ValueId
    getter left_id : ValueId
    getter right_id : ValueId
    getter type : IrType
    getter normal_successor_label : Int32
    getter exception_successor_label : Int32

    @remainder : Bool

    def remainder? : Bool
      @remainder
    end

    def initialize(
      position : Int32,
      @result_id : ValueId,
      @exception_id : ValueId,
      @left_id : ValueId,
      @right_id : ValueId,
      @type : IrType,
      remainder : Bool,
      @normal_successor_label : Int32,
      @exception_successor_label : Int32,
    )
      @remainder = remainder
      super(position)
    end

    def used_values : Array(ValueId)
      [@left_id, @right_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def defined_value_ids : Array(ValueId)
      [@result_id, @exception_id]
    end

    def call_boundary? : Bool
      true
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_integer_division(self)
    end
  end

  class MachineExceptionDispatch < MachineInstruction
    getter exception_id : ValueId
    getter cases : Array(Tuple(IrExceptionKind?, Int32))
    getter default_label : Int32?

    def initialize(position : Int32, @exception_id : ValueId, cases : Array(Tuple(IrExceptionKind?, Int32)), @default_label : Int32?)
      super(position)
      @cases = cases.dup
    end

    def used_values : Array(ValueId)
      [@exception_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_exception_dispatch(self)
    end
  end

  class MachineSuppressException < MachineInstruction
    getter result_id : ValueId
    getter new_exception_id : ValueId
    getter old_exception_id : ValueId

    def initialize(position : Int32, @result_id : ValueId, @new_exception_id : ValueId, @old_exception_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [@new_exception_id, @old_exception_id]
    end

    def result_value_id : ValueId?
      @result_id
    end

    def call_boundary? : Bool
      true
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_suppress_exception(self)
    end
  end

  class MachineExceptionRelease < MachineInstruction
    getter exception_id : ValueId

    def initialize(position : Int32, @exception_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [@exception_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def call_boundary? : Bool
      true
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_exception_release(self)
    end
  end

  class MachineLabel < MachineInstruction
    getter label : Int32

    def initialize(position : Int32, @label : Int32)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.code.mark_label(@label)
    end
  end

  class MachineSetSourceLocation < MachineInstruction
    getter source_location : IrSourceLocation

    def initialize(position : Int32, @source_location : IrSourceLocation)
      super(position)
    end

    def used_values : Array(ValueId)
      Array(ValueId).new
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.set_source_location(@source_location)
    end
  end

  class MachinePhi < MachineInstruction
    getter result_id : ValueId

    def initialize(position : Int32, @result_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      @result_id
    end

    def emit(context : X86_64EmissionContext) : Nil
    end
  end

  class MachineEdgeCopy < MachineInstruction
    getter source_id : ValueId
    getter destination_id : ValueId

    def initialize(position : Int32, @source_id : ValueId, @destination_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [@source_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.location(@source_id).load_to(context.code, X86_64Register::Rax, context.frame)
      context.location(@destination_id).store_from(context.code, X86_64Register::Rax, context.frame)
    end
  end

  class MachineJump < MachineInstruction
    getter target_label : Int32

    def initialize(position : Int32, @target_label : Int32)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.code.jump_to(@target_label)
    end
  end

  class MachineBranch < MachineInstruction
    getter condition_id : ValueId
    getter true_label : Int32
    getter false_label : Int32

    def initialize(position : Int32, @condition_id : ValueId, @true_label : Int32, @false_label : Int32)
      super(position)
    end

    def used_values : Array(ValueId)
      [@condition_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.location(@condition_id).load_to(context.code, X86_64Register::Rax, context.frame)
      context.code.test_register(X86_64Register::Rax)
      context.code.jump_if_not_zero_to(@true_label)
      context.code.jump_to(@false_label)
    end
  end

  class MachineTrap < MachineInstruction
    def initialize(position : Int32)
      super(position)
    end

    def used_values : Array(ValueId)
      [] of ValueId
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.code.emit_trap
    end
  end

  struct MachinePhiEdge
    getter source_block_id : BlockId
    getter target_block_id : BlockId
    getter label : Int32
    getter copies : Array(Tuple(ValueId, ValueId))

    def initialize(@source_block_id : BlockId, @target_block_id : BlockId, @label : Int32, @copies : Array(Tuple(ValueId, ValueId)))
    end
  end

  class MachineReturn < MachineInstruction
    getter value_id : ValueId
    getter result_type : IrType

    def initialize(position : Int32, @value_id : ValueId, @result_type : IrType)
      super(position)
    end

    def used_values : Array(ValueId)
      [@value_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.emit_return(@value_id, @result_type)
    end
  end

  class MachineResumeException < MachineInstruction
    getter exception_id : ValueId

    def initialize(position : Int32, @exception_id : ValueId)
      super(position)
    end

    def used_values : Array(ValueId)
      [@exception_id]
    end

    def result_value_id : ValueId?
      nil
    end

    def emit(context : X86_64EmissionContext) : Nil
      context.location(@exception_id).load_to(context.code, X86_64Register::Rdx, context.frame)
      context.code.emit_epilogue
    end
  end

  class X86_64InstructionSelector < IrInstructionVisitor
    @instructions : Array(MachineInstruction)
    @block_labels : Hash(BlockId, Int32)
    @phi_edges : Hash(Tuple(BlockId, BlockId), MachinePhiEdge)
    @phi_edge_order : Array(MachinePhiEdge)
    @current_result_type : IrType?

    def initialize
      @instructions = [] of MachineInstruction
      @block_labels = {} of BlockId => Int32
      @phi_edges = {} of Tuple(BlockId, BlockId) => MachinePhiEdge
      @phi_edge_order = [] of MachinePhiEdge
      @current_result_type = nil
    end

    def lower(function : IrFunction) : Array(MachineInstruction)
      @instructions.clear
      @block_labels.clear
      @phi_edges.clear
      @phi_edge_order.clear
      @current_result_type = function.signature.result_type
      function.each_block { |block| @block_labels[block.id] = block.id }
      prepare_phi_edges(function)

      function.each_block do |block|
        @instructions << MachineLabel.new(@instructions.size, @block_labels[block.id])
        block.instruction_ids.each do |instruction_id|
          instruction = function.instruction(instruction_id)
          raise X86_64BackendFailure.new("unknown IR instruction #{instruction_id}") unless instruction
          instruction.accept(self)
        end
      end

      @phi_edge_order.each do |edge|
        @instructions << MachineLabel.new(@instructions.size, edge.label)
        edge.copies.each do |source_id, destination_id|
          @instructions << MachineEdgeCopy.new(@instructions.size, source_id, destination_id)
        end
        @instructions << MachineJump.new(@instructions.size, @block_labels[edge.target_block_id])
      end
      @instructions.dup
    end

    def visit(instruction : IrConstantInstruction) : Nil
      result_id = instruction.result_id
      result_type = instruction.result_type
      raise X86_64BackendFailure.new("constant is missing its result") unless result_id && result_type
      @instructions << MachineConstant.new(@instructions.size, result_id, result_type, instruction.value)
    end

    def visit(instruction : IrUnitConstantInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("unit constant is missing its result") unless result_id
      @instructions << MachineUnitConstant.new(@instructions.size, result_id)
    end

    def visit(instruction : IrArrayLiteralInstruction) : Nil
      result_id = instruction.result_id
      array_type = instruction.result_type.as?(IrArrayType)
      raise X86_64BackendFailure.new("array literal is missing its result type") unless result_id && array_type
      @instructions << MachineArrayLiteral.new(@instructions.size, result_id, array_type, instruction.elements)
    end

    def visit(instruction : IrStackAllocateInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("stack allocation is missing its result") unless result_id
      @instructions << MachineStackAllocate.new(
        @instructions.size,
        instruction.id,
        result_id,
        instruction.initial_value_id,
        instruction.pointer_type
      )
    end

    def visit(instruction : IrStackStorageInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("stack storage is missing its result") unless result_id
      @instructions << MachineStackStorage.new(
        @instructions.size,
        instruction.id,
        result_id,
        instruction.byte_size,
        instruction.alignment
      )
    end

    def visit(instruction : IrPointerOffsetInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("pointer offset is missing its result") unless result_id
      @instructions << MachinePointerOffset.new(
        @instructions.size,
        result_id,
        instruction.address_id,
        instruction.index_id,
        instruction.pointer_type
      )
    end

    def visit(instruction : IrPointerCastInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("pointer cast is missing its result") unless result_id
      @instructions << MachinePointerCast.new(@instructions.size, result_id, instruction.address_id)
    end

    def visit(instruction : IrLoadInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("pointer load is missing its result") unless result_id
      @instructions << MachinePointerLoad.new(@instructions.size, result_id, instruction.address_id, instruction.pointer_type)
    end

    def visit(instruction : IrStoreInstruction) : Nil
      @instructions << MachinePointerStore.new(
        @instructions.size,
        instruction.address_id,
        instruction.value_id,
        instruction.pointer_type
      )
    end

    def visit(instruction : IrFreeInstruction) : Nil
      @instructions << MachinePointerFree.new(@instructions.size, instruction.address_id, instruction.pointer_type)
    end

    def visit(instruction : IrAddInstruction) : Nil
      append_binary(instruction, MachineAddOperation.new)
    end

    def visit(instruction : IrSubtractInstruction) : Nil
      append_binary(instruction, MachineSubtractOperation.new)
    end

    def visit(instruction : IrMultiplyInstruction) : Nil
      append_binary(instruction, MachineMultiplyOperation.new)
    end

    def visit(instruction : IrReturnInstruction) : Nil
      result_type = @current_result_type
      raise X86_64BackendFailure.new("return is missing the function result type") unless result_type
      @instructions << MachineReturn.new(@instructions.size, instruction.value_id, result_type)
    end

    def visit(instruction : IrPhiInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("phi is missing its result") unless result_id
      @instructions << MachinePhi.new(@instructions.size, result_id)
    end

    def visit(instruction : IrJumpInstruction) : Nil
      @instructions << MachineJump.new(@instructions.size, target_label(instruction.block_id, instruction.target_block_id))
    end

    def visit(instruction : IrBranchInstruction) : Nil
      true_label = target_label(instruction.block_id, instruction.true_block_id)
      false_label = target_label(instruction.block_id, instruction.false_block_id)
      @instructions << MachineBranch.new(@instructions.size, instruction.condition_id, true_label, false_label)
    end

    def visit(instruction : IrInvokeInstruction) : Nil
      source_location = instruction.source_location || IrSourceLocation.new("<ir>", 0)
      @instructions << MachineSetSourceLocation.new(@instructions.size, source_location)
      instruction.operation.accept(self, instruction)
    end

    def visit(operation : IrCallOperation, instruction : IrInvokeInstruction) : Nil
      function_id = operation.target.module_function_id
      raise X86_64BackendFailure.new("call target is not an internal function") unless function_id
      normal_label = target_label(instruction.block_id, instruction.normal_successor)
      exception_label = target_label(instruction.block_id, instruction.exception_successor)
      @instructions << MachineCall.new(
        @instructions.size,
        instruction.normal_result_id,
        instruction.exception_result_id,
        function_id,
        operation.result_type,
        operation.arguments,
        operation.target.signature.parameter_types,
        normal_label,
        exception_label
      )
    end

    def visit(operation : IrAllocateOperation, instruction : IrInvokeInstruction) : Nil
      @instructions << MachineAllocate.new(
        @instructions.size,
        instruction.normal_result_id,
        instruction.exception_result_id,
        operation.initial_value_id,
        operation.pointer_type,
        target_label(instruction.block_id, instruction.normal_successor),
        target_label(instruction.block_id, instruction.exception_successor)
      )
    end

    def visit(operation : IrDivideOperation, instruction : IrInvokeInstruction) : Nil
      append_integer_division(instruction, operation, false)
    end

    def visit(operation : IrRemainderOperation, instruction : IrInvokeInstruction) : Nil
      append_integer_division(instruction, operation, true)
    end

    def visit(operation : IrArrayGetOperation, instruction : IrInvokeInstruction) : Nil
      append_array_access(instruction, operation.array_id, operation.index_id, operation.array_type)
    end

    def visit(operation : IrArraySetOperation, instruction : IrInvokeInstruction) : Nil
      @instructions << MachineArrayUpdate.new(
        @instructions.size,
        instruction.normal_result_id,
        instruction.exception_result_id,
        operation.array_id,
        operation.index_id,
        operation.value_id,
        operation.array_type,
        target_label(instruction.block_id, instruction.normal_successor),
        target_label(instruction.block_id, instruction.exception_successor)
      )
    end

    def visit(instruction : IrResumeExceptionInstruction) : Nil
      @instructions << MachineResumeException.new(@instructions.size, instruction.exception_id)
    end

    def visit(instruction : IrExceptionDispatchInstruction) : Nil
      cases = instruction.cases.map do |exception_case|
        {exception_case.kind, target_label(instruction.block_id, exception_case.target_block_id)}
      end
      default_label = instruction.default_block_id.try { |block_id| target_label(instruction.block_id, block_id) }
      @instructions << MachineExceptionDispatch.new(@instructions.size, instruction.exception_id, cases, default_label)
    end

    def visit(instruction : IrSuppressExceptionInstruction) : Nil
      result_id = instruction.result_id
      raise X86_64BackendFailure.new("exception suppression is missing its result") unless result_id
      @instructions << MachineSuppressException.new(@instructions.size, result_id, instruction.new_exception_id, instruction.old_exception_id)
    end

    def visit(instruction : IrExceptionReleaseInstruction) : Nil
      @instructions << MachineExceptionRelease.new(@instructions.size, instruction.exception_id)
    end

    private def append_binary(instruction : IrBinaryInstruction, operation : MachineBinaryOperation) : Nil
      result_id = instruction.result_id
      result_type = instruction.result_type
      raise X86_64BackendFailure.new("binary operation is missing its result") unless result_id && result_type
      @instructions << MachineBinary.new(
        @instructions.size,
        result_id,
        instruction.left,
        instruction.right,
        result_type,
        operation
      )
    end

    private def append_integer_division(
      instruction : IrInvokeInstruction,
      operation : IrIntegerBinaryInvokeOperation,
      remainder : Bool,
    ) : Nil
      @instructions << MachineIntegerDivision.new(
        @instructions.size,
        instruction.normal_result_id,
        instruction.exception_result_id,
        operation.left,
        operation.right,
        operation.type,
        remainder,
        target_label(instruction.block_id, instruction.normal_successor),
        target_label(instruction.block_id, instruction.exception_successor)
      )
    end

    private def append_array_access(
      instruction : IrInvokeInstruction,
      array_id : ValueId,
      index_id : ValueId,
      array_type : IrArrayType,
    ) : Nil
      @instructions << MachineArrayAccess.new(
        @instructions.size,
        instruction.normal_result_id,
        instruction.exception_result_id,
        array_id,
        index_id,
        array_type,
        target_label(instruction.block_id, instruction.normal_successor),
        target_label(instruction.block_id, instruction.exception_successor)
      )
    end

    private def prepare_phi_edges(function : IrFunction) : Nil
      next_label = function.block_count
      function.each_block do |block|
        phi_instructions = block.instruction_ids.compact_map do |instruction_id|
          function.instruction(instruction_id).as?(IrPhiInstruction)
        end
        next if phi_instructions.empty?

        predecessors = phi_instructions.first.incoming.map(&.predecessor_block_id)
        predecessors.each do |predecessor_id|
          copies = phi_instructions.map do |phi|
            incoming = phi.incoming.find { |candidate| candidate.predecessor_block_id == predecessor_id }
            raise X86_64BackendFailure.new("phi is missing an incoming edge") unless incoming
            {incoming.value_id, phi.result_id.not_nil!}
          end
          edge = MachinePhiEdge.new(predecessor_id, block.id, next_label, copies)
          @phi_edges[{predecessor_id, block.id}] = edge
          @phi_edge_order << edge
          next_label += 1
        end
      end
    end

    private def target_label(source_block_id : BlockId, target_block_id : BlockId) : Int32
      @phi_edges[{source_block_id, target_block_id}]?.try(&.label) || @block_labels[target_block_id]
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
    ]

    def allocate(function : IrFunction, instructions : Array(MachineInstruction)) : RegisterAllocation
      return allocate_stack_only(function) if function.block_count > 1

      intervals = build_intervals(function, instructions)
      locations = {} of ValueId => ValueLocation
      active = [] of ActiveInterval
      spill_slot_count = 0

      function.value_count.times do |value_id|
        type = function.value_type(value_id)
        if type.is_a?(IrArrayType)
          locations[value_id] = ArrayValueLocation.new(value_id)
        elsif type && type.zero_sized?
          locations[value_id] = UnitValueLocation.new
        end
      end

      intervals.sort_by(&.start_position).each do |interval|
        next if function.value_type(interval.value_id).try { |type| type.zero_sized? || type.is_a?(IrArrayType) }

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

    private def allocate_stack_only(function : IrFunction) : RegisterAllocation
      locations = {} of ValueId => ValueLocation
      spill_slot_count = 0
      function.value_count.times do |value_id|
        type = function.value_type(value_id)
        if type.is_a?(IrArrayType)
          locations[value_id] = ArrayValueLocation.new(value_id)
        elsif type && type.zero_sized?
          locations[value_id] = UnitValueLocation.new
        else
          locations[value_id] = SpillValueLocation.new(spill_slot_count)
          spill_slot_count += 1
        end
      end
      RegisterAllocation.new(locations, {} of Int32 => Array(CallSpill), spill_slot_count)
    end

    private def build_intervals(function : IrFunction, instructions : Array(MachineInstruction)) : Array(LiveInterval)
      intervals = {} of ValueId => LiveInterval
      function.parameters.each do |parameter|
        intervals[parameter.value_id] = LiveInterval.new(parameter.value_id, -1, 0)
      end

      instructions.each do |instruction|
        instruction.defined_value_ids.each do |result_id|
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
    FIXED_FRAME_BYTES = 80

    getter frame_size : Int32

    @spill_offsets : Array(Int32)
    @argument_stage_offsets : Array(Int32)
    @array_offsets : Hash(ValueId, Int32)
    @array_sizes : Hash(ValueId, Int32)
    @stack_allocation_offsets : Hash(InstructionId, Int32)
    @stack_storage_offsets : Hash(InstructionId, Int32)
    @stack_storage_reserved_sizes : Hash(InstructionId, Int32)
    @outgoing_stack_argument_count : Int32

    def initialize(function : IrFunction, spill_slot_count : Int32, argument_stage_count : Int32, @outgoing_stack_argument_count : Int32)
      @spill_offsets = [] of Int32
      spill_slot_count.times do |slot|
        @spill_offsets << -(FIXED_FRAME_BYTES + (slot + 1) * 8)
      end

      @argument_stage_offsets = [] of Int32
      argument_stage_count.times do |index|
        @argument_stage_offsets << -(FIXED_FRAME_BYTES + (spill_slot_count + index + 1) * 8)
      end

      @array_offsets = {} of ValueId => Int32
      @array_sizes = {} of ValueId => Int32
      @stack_allocation_offsets = {} of InstructionId => Int32
      @stack_storage_offsets = {} of InstructionId => Int32
      @stack_storage_reserved_sizes = {} of InstructionId => Int32
      cursor = FIXED_FRAME_BYTES + (spill_slot_count + argument_stage_count + @outgoing_stack_argument_count) * 8
      function.value_count.times do |value_id|
        array_type = function.value_type(value_id).as?(IrArrayType)
        next unless array_type
        size = array_type.storage_size || raise X86_64BackendFailure.new("array %v#{value_id} has an unrepresentable storage size")
        raise X86_64BackendFailure.new("array %v#{value_id} is too large for a stack frame") if size > Int32::MAX
        allocated_size = {size.to_i32, 1}.max
        alignment = array_type.alignment.to_i32
        end_offset_64 = cursor.to_i64 + allocated_size.to_i64
        end_offset_64 = ((end_offset_64 + alignment - 1) // alignment) * alignment
        if end_offset_64 > Int32::MAX
          raise X86_64BackendFailure.new("array stack frame exceeds x86_64 frame limits")
        end
        end_offset = end_offset_64.to_i32
        @array_offsets[value_id] = -end_offset
        @array_sizes[value_id] = size.to_i32
        cursor = end_offset
      end
      function.each_block do |block|
        block.instruction_ids.each do |instruction_id|
          instruction = function.instruction(instruction_id)
          stack_allocation = instruction.as?(IrStackAllocateInstruction)
          next unless stack_allocation
          type = stack_allocation.pointer_type.pointee_type
          size = type.storage_size || raise X86_64BackendFailure.new("stack allocation %i#{instruction_id} has an unrepresentable size")
          raise X86_64BackendFailure.new("stack allocation %i#{instruction_id} is too large for a stack frame") if size > Int32::MAX
          allocated_size = {size.to_i32, 1}.max
          alignment = type.alignment.to_i32
          end_offset_64 = cursor.to_i64 + allocated_size.to_i64
          end_offset_64 = ((end_offset_64 + alignment - 1) // alignment) * alignment
          if end_offset_64 > Int32::MAX
            raise X86_64BackendFailure.new("stack allocations exceed x86_64 frame limits")
          end
          end_offset = end_offset_64.to_i32
          @stack_allocation_offsets[instruction_id] = -end_offset
          cursor = end_offset
        end
      end
      function.each_block do |block|
        block.instruction_ids.each do |instruction_id|
          instruction = function.instruction(instruction_id)
          storage = instruction.as?(IrStackStorageInstruction)
          next unless storage
          unless storage.byte_size > 0 && storage.alignment > 0 && (storage.alignment & (storage.alignment - 1_u64)) == 0
            raise X86_64BackendFailure.new("stack storage %i#{instruction_id} has an invalid size or alignment")
          end
          reserved_size = storage.byte_size.to_u128 + storage.alignment.to_u128 - 1_u128
          if reserved_size > Int32::MAX
            raise X86_64BackendFailure.new("stack storage %i#{instruction_id} exceeds x86_64 frame limits")
          end
          end_offset_64 = cursor.to_i64 + reserved_size.to_i64
          if end_offset_64 > Int32::MAX
            raise X86_64BackendFailure.new("stack storages exceed x86_64 frame limits")
          end
          end_offset = end_offset_64.to_i32
          @stack_storage_offsets[instruction_id] = -end_offset
          @stack_storage_reserved_sizes[instruction_id] = reserved_size.to_i32
          cursor = end_offset
        end
      end
      frame_size_64 = ((cursor.to_i64 + 15) // 16) * 16
      raise X86_64BackendFailure.new("stack frame exceeds x86_64 frame limits") if frame_size_64 > Int32::MAX
      @frame_size = frame_size_64.to_i32
    end

    def frame_link_offset : Int32
      -8
    end

    def function_name_offset : Int32
      -16
    end

    def function_name_length_offset : Int32
      -24
    end

    def source_file_offset : Int32
      -32
    end

    def source_file_length_offset : Int32
      -40
    end

    def source_line_offset : Int32
      -48
    end

    def source_line_length_offset : Int32
      -56
    end

    def invoke_normal_result_offset : Int32
      -64
    end

    def invoke_exception_offset : Int32
      -72
    end

    def spill_offset(slot : Int32) : Int32
      @spill_offsets[slot]? || raise X86_64BackendFailure.new("invalid spill slot #{slot}")
    end

    def argument_stage_offset(index : Int32) : Int32
      @argument_stage_offsets[index]? || raise X86_64BackendFailure.new("invalid staged argument #{index}")
    end

    def array_offset(value_id : ValueId) : Int32
      @array_offsets[value_id]? || raise X86_64BackendFailure.new("missing stack storage for array %v#{value_id}")
    end

    def array_size(value_id : ValueId) : Int32
      @array_sizes[value_id]? || raise X86_64BackendFailure.new("missing stack size for array %v#{value_id}")
    end

    def stack_allocation_offset(instruction_id : InstructionId) : Int32
      @stack_allocation_offsets[instruction_id]? || raise X86_64BackendFailure.new("missing frame slot for stack allocation %i#{instruction_id}")
    end

    def stack_storage_offset(instruction_id : InstructionId) : Int32
      @stack_storage_offsets[instruction_id]? || raise X86_64BackendFailure.new("missing frame storage for stack storage %i#{instruction_id}")
    end

    def stack_storage_reserved_size(instruction_id : InstructionId) : Int32
      @stack_storage_reserved_sizes[instruction_id]? || raise X86_64BackendFailure.new("missing frame size for stack storage %i#{instruction_id}")
    end

    def hidden_return_pointer_offset : Int32
      -80
    end

    def copy_address_to_array(code : X86_64CodeBuffer, source : X86_64Register, value_id : ValueId) : Nil
      size = array_size(value_id)
      copy_address_to_memory(code, source, X86_64Register::Rbp, array_offset(value_id), size)
    end

    def copy_address_to_memory(
      code : X86_64CodeBuffer,
      source : X86_64Register,
      destination : X86_64Register,
      destination_offset : Int32,
      size : Int32,
    ) : Nil
      temporary = source == X86_64Register::R10 ? X86_64Register::R11 : X86_64Register::R10
      size.times do |index|
        code.move_register_from_memory_sized(temporary, source, index, 8, false)
        code.move_memory_from_register_sized(destination, destination_offset + index, temporary, 8)
      end
    end

    def outgoing_stack_argument_offset(index : Int32) : Int32
      raise X86_64BackendFailure.new("invalid outgoing stack argument #{index}") if index < 0 || index >= @outgoing_stack_argument_count
      index * 8
    end

    private def align_to(value : Int32, alignment : Int32) : Int32
      ((value + alignment - 1) // alignment) * alignment
    end
  end

  struct X86_64CfiEvent
    getter code_offset : Int32
    getter instructions : Array(UInt8)

    def initialize(@code_offset : Int32, instructions : Array(UInt8))
      @instructions = instructions.dup
    end
  end

  class X86_64CodeBuffer
    getter bytes : Array(UInt8)
    getter cfi_events : Array(X86_64CfiEvent)

    def initialize
      @buffer = ByteBuffer.new
      @bytes = @buffer.bytes
      @labels = {} of Int32 => Int32
      @branch_fixups = [] of Tuple(Int32, Int32)
      @rip_relative_fixups = [] of Tuple(Int32, Int32)
      @next_private_label = -1
      @cfi_events = [] of X86_64CfiEvent
    end

    def size : Int32
      @buffer.size
    end

    def write_bytes(bytes : Array(UInt8)) : Nil
      @buffer.write_bytes(bytes)
    end

    def new_label : Int32
      label = @next_private_label
      @next_private_label -= 1
      label
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

    def move_register_from_rbp_sized(destination : X86_64Register, offset : Int32, width : Int32, signed : Bool) : Nil
      move_register_from_memory_sized(destination, X86_64Register::Rbp, offset, width, signed)
    end

    def move_rbp_from_register(offset : Int32, source : X86_64Register) : Nil
      write_memory_store(X86_64Register::Rbp, offset, source)
    end

    def move_rbp_from_register_sized(offset : Int32, source : X86_64Register, width : Int32) : Nil
      move_memory_from_register_sized(X86_64Register::Rbp, offset, source, width)
    end

    def move_rsp_from_register(offset : Int32, source : X86_64Register) : Nil
      write_memory_store(X86_64Register::Rsp, offset, source)
    end

    def move_register_from_memory(destination : X86_64Register, base : X86_64Register, offset : Int32) : Nil
      write_memory_move(destination, base, offset)
    end

    def move_register_from_memory_sized(destination : X86_64Register, base : X86_64Register, offset : Int32, width : Int32, signed : Bool) : Nil
      case width
      when 8, 16
        write_rex(true, destination, base)
        @buffer.write_bytes([0x0f_u8, (signed ? 0xbe_u8 : 0xb6_u8) + (width == 16 ? 1_u8 : 0_u8)])
        write_memory_operand(destination, base, offset)
      when 32
        if signed
          write_rex(true, destination, base)
          @buffer.write_u8(0x63_u8)
        else
          write_rex(false, destination, base)
          @buffer.write_u8(0x8b_u8)
        end
        write_memory_operand(destination, base, offset)
      when 64
        write_memory_move(destination, base, offset)
      else
        raise X86_64BackendFailure.new("unsupported memory load width #{width}")
      end
    end

    def move_memory_from_register(base : X86_64Register, offset : Int32, source : X86_64Register) : Nil
      write_memory_store(base, offset, source)
    end

    def move_memory_from_register_sized(base : X86_64Register, offset : Int32, source : X86_64Register, width : Int32) : Nil
      case width
      when 8
        write_rex(false, source, base)
        @buffer.write_u8(0x88_u8)
      when 16
        @buffer.write_u8(0x66_u8)
        write_rex(false, source, base)
        @buffer.write_u8(0x89_u8)
      when 32
        write_rex(false, source, base)
        @buffer.write_u8(0x89_u8)
      when 64
        write_memory_store(base, offset, source)
        return
      else
        raise X86_64BackendFailure.new("unsupported memory store width #{width}")
      end
      write_memory_operand(source, base, offset)
    end

    def lea_rbp_relative(destination : X86_64Register, offset : Int32) : Nil
      write_rex(true, destination, X86_64Register::Rbp)
      @buffer.write_u8(0x8d_u8)
      write_memory_operand(destination, X86_64Register::Rbp, offset)
    end

    def move_immediate_to_memory(base : X86_64Register, offset : Int32, value : UInt32) : Nil
      write_rex(true, X86_64Register::Rax, base)
      @buffer.write_u8(0xc7_u8)
      write_memory_operand(X86_64Register::Rax, base, offset)
      @buffer.write_u32(value)
    end

    def compare_register_immediate(register : X86_64Register, value : Int32) : Nil
      write_rex(true, X86_64Register::Rax, register)
      @buffer.write_u8(0x81_u8)
      @buffer.write_u8(0xc0_u8 | (0x07_u8 << 3) | register.code)
      @buffer.write_i32(value)
    end

    def lea_rip_relative(destination : X86_64Register, label : Int32) : Nil
      write_rex(true, destination, X86_64Register::Rbp)
      @buffer.write_u8(0x8d_u8)
      @buffer.write_u8((destination.code << 3) | X86_64Register::Rbp.code)
      displacement_offset = @buffer.size
      @buffer.write_u32(0_u32)
      @rip_relative_fixups << {displacement_offset, label}
    end

    def add_register(destination : X86_64Register, source : X86_64Register) : Nil
      write_rex(true, source, destination)
      @buffer.write_u8(0x01_u8)
      write_modrm(0b11_u8, source, destination)
    end

    def add_immediate_register(register : X86_64Register, value : Int32) : Nil
      write_rex(true, X86_64Register::Rax, register)
      @buffer.write_u8(0x81_u8)
      @buffer.write_u8(0xc0_u8 | register.code)
      @buffer.write_i32(value)
    end

    def and_immediate_register(register : X86_64Register, value : Int32) : Nil
      write_rex(true, X86_64Register::Rax, register)
      @buffer.write_u8(0x81_u8)
      @buffer.write_u8(0xe0_u8 | register.code)
      @buffer.write_i32(value)
    end

    def compare_registers(left : X86_64Register, right : X86_64Register) : Nil
      write_rex(true, right, left)
      @buffer.write_u8(0x39_u8)
      write_modrm(0b11_u8, right, left)
    end

    def shift_left_register(register : X86_64Register, amount : UInt8) : Nil
      write_rex(true, X86_64Register::Rax, register)
      @buffer.write_u8(0xc1_u8)
      @buffer.write_u8(0xe0_u8 | register.code)
      @buffer.write_u8(amount)
    end

    def shift_right_logical_register(register : X86_64Register, amount : UInt8) : Nil
      write_rex(true, X86_64Register::Rax, register)
      @buffer.write_u8(0xc1_u8)
      @buffer.write_u8(0xe8_u8 | register.code)
      @buffer.write_u8(amount)
    end

    def shift_right_arithmetic_register(register : X86_64Register, amount : UInt8) : Nil
      write_rex(true, X86_64Register::Rax, register)
      @buffer.write_u8(0xc1_u8)
      @buffer.write_u8(0xf8_u8 | register.code)
      @buffer.write_u8(amount)
    end

    def sign_extend_rax_to_rdx : Nil
      @buffer.write_bytes([0x48_u8, 0x99_u8])
    end

    def divide_by_register(divisor : X86_64Register, signed : Bool) : Nil
      write_rex(true, X86_64Register::Rax, divisor)
      @buffer.write_u8(0xf7_u8)
      extension = signed ? 7_u8 : 6_u8
      @buffer.write_u8(0xc0_u8 | (extension << 3) | divisor.code)
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

    def multiply_register(destination : X86_64Register, source : X86_64Register) : Nil
      write_rex(true, destination, source)
      @buffer.write_bytes([0x0f_u8, 0xaf_u8])
      write_modrm(0b11_u8, destination, source)
    end

    def multiply_immediate_register(register : X86_64Register, value : Int32) : Nil
      write_rex(true, register, register)
      @buffer.write_u8(0x69_u8)
      write_modrm(0b11_u8, register, register)
      @buffer.write_i32(value)
    end

    def multiply_rbp_memory(destination : X86_64Register, offset : Int32) : Nil
      write_rex(true, destination, X86_64Register::Rbp)
      @buffer.write_bytes([0x0f_u8, 0xaf_u8])
      write_memory_operand(destination, X86_64Register::Rbp, offset)
    end

    def emit_prologue(frame_size : Int32) : Nil
      @buffer.write_u8(0x55_u8)
      record_cfi_event([0x0e_u8, 16_u8, 0x86_u8, 2_u8])
      @buffer.write_bytes([0x48_u8, 0x89_u8, 0xe5_u8])
      record_cfi_event([0x0d_u8, 6_u8])
      unless frame_size == 0
        @buffer.write_bytes([0x48_u8, 0x81_u8, 0xec_u8])
        @buffer.write_u32(frame_size.to_u32)
      end
      move_rbp_from_register(-8, X86_64Register::R15)
      move_register(X86_64Register::R15, X86_64Register::Rbp)
    end

    def emit_epilogue : Nil
      move_register_from_rbp(X86_64Register::R15, -8)
      record_cfi_event([0x0a_u8])
      @buffer.write_bytes([0x48_u8, 0x89_u8, 0xec_u8])
      record_cfi_event([0x0d_u8, 7_u8])
      @buffer.write_u8(0x5d_u8)
      record_cfi_event([0x0e_u8, 8_u8, 0xc6_u8])
      @buffer.write_u8(0xc3_u8)
      record_cfi_event([0x0b_u8])
    end

    def emit_call : Int32
      @buffer.write_u8(0xe8_u8)
      displacement_offset = @buffer.size
      @buffer.write_u32(0_u32)
      displacement_offset
    end

    def mark_label(label : Int32) : Nil
      raise X86_64BackendFailure.new("machine label #{label} is defined more than once") if @labels.has_key?(label)
      @labels[label] = @buffer.size
    end

    def jump_to(label : Int32) : Nil
      @buffer.write_u8(0xe9_u8)
      record_branch_fixup(label)
    end

    def jump_if_not_zero_to(label : Int32) : Nil
      @buffer.write_bytes([0x0f_u8, 0x85_u8])
      record_branch_fixup(label)
    end

    def jump_if_zero_to(label : Int32) : Nil
      @buffer.write_bytes([0x0f_u8, 0x84_u8])
      record_branch_fixup(label)
    end

    def jump_if_equal_to(label : Int32) : Nil
      jump_if_zero_to(label)
    end

    def jump_if_not_equal_to(label : Int32) : Nil
      jump_if_not_zero_to(label)
    end

    def jump_if_above_or_equal_to(label : Int32) : Nil
      @buffer.write_bytes([0x0f_u8, 0x83_u8])
      record_branch_fixup(label)
    end

    def jump_if_sign_to(label : Int32) : Nil
      @buffer.write_bytes([0x0f_u8, 0x88_u8])
      record_branch_fixup(label)
    end

    def jump_if_greater_equal_to(label : Int32) : Nil
      @buffer.write_bytes([0x0f_u8, 0x8d_u8])
      record_branch_fixup(label)
    end

    def xor_register(register : X86_64Register) : Nil
      write_rex(true, register, register)
      @buffer.write_u8(0x31_u8)
      write_modrm(0b11_u8, register, register)
    end

    def emit_syscall : Nil
      @buffer.write_bytes([0x0f_u8, 0x05_u8])
    end

    def emit_return_instruction : Nil
      @buffer.write_u8(0xc3_u8)
    end

    def test_register(register : X86_64Register) : Nil
      write_rex(true, register, register)
      @buffer.write_u8(0x85_u8)
      write_modrm(0b11_u8, register, register)
    end

    def emit_trap : Nil
      @buffer.write_bytes([0x0f_u8, 0x0b_u8])
    end

    def resolve_labels : Nil
      @branch_fixups.each do |fixup|
        displacement_offset, target_label = fixup
        target_offset = @labels[target_label]?
        raise X86_64BackendFailure.new("machine branch targets undefined label #{target_label}") unless target_offset
        displacement = target_offset - (displacement_offset + 4)
        unless Int32::MIN <= displacement <= Int32::MAX
          raise X86_64BackendFailure.new("machine branch to label #{target_label} is out of range")
        end
        4.times do |index|
          @bytes[displacement_offset + index] = ((displacement >> (index * 8)) & 0xff).to_u8
        end
      end
      @rip_relative_fixups.each do |fixup|
        displacement_offset, target_label = fixup
        target_offset = @labels[target_label]?
        raise X86_64BackendFailure.new("RIP-relative reference targets undefined label #{target_label}") unless target_offset
        displacement = target_offset - (displacement_offset + 4)
        unless Int32::MIN <= displacement <= Int32::MAX
          raise X86_64BackendFailure.new("RIP-relative reference to label #{target_label} is out of range")
        end
        4.times do |index|
          @bytes[displacement_offset + index] = ((displacement >> (index * 8)) & 0xff).to_u8
        end
      end
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

    private def record_branch_fixup(label : Int32) : Nil
      displacement_offset = @buffer.size
      @buffer.write_u32(0_u32)
      @branch_fixups << {displacement_offset, label}
    end

    private def record_cfi_event(instructions : Array(UInt8)) : Nil
      @cfi_events << X86_64CfiEvent.new(@buffer.size, instructions)
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
      @buffer.write_u8(0x24_u8) if mode != 0b11_u8 && rm_field.code == X86_64Register::Rsp.code
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

  struct X86_64EhFrameRelocation
    getter offset : Int32
    getter text_offset : Int32

    def initialize(@offset : Int32, @text_offset : Int32)
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
    @literal_labels : Hash(String, Int32)
    @literal_order : Array(Tuple(String, Int32))

    def initialize(@code : X86_64CodeBuffer, @frame : X86_64FrameLayout, @allocation : RegisterAllocation)
      @relocations = [] of X86_64Relocation
      @literal_labels = {} of String => Int32
      @literal_order = [] of Tuple(String, Int32)
    end

    def location(value_id : ValueId) : ValueLocation
      @allocation.location(value_id)
    end

    def constant_bits(type : IrType, value : Int128) : UInt64
      if type == IrType::Bool
        unless value == 0 || value == 1
          raise X86_64BackendFailure.new("bool constant must be 0 or 1, got #{value}")
        end
        return value.to_u64
      end
      unless type.integer?
        raise X86_64BackendFailure.new("unsupported constant type #{type}")
      end

      width = integer_bit_width(type)
      if type.signed?
        minimum = -(1_i128 << (width - 1))
        maximum = (1_i128 << (width - 1)) - 1
        unless value >= minimum && value <= maximum
          raise X86_64BackendFailure.new("constant #{value} does not fit #{type.label} on x86_64")
        end
      else
        maximum = (1_i128 << width) - 1
        unless value >= 0 && value <= maximum
          raise X86_64BackendFailure.new("constant #{value} does not fit #{type.label} on x86_64")
        end
      end

      bits = (value & ((1_i128 << width) - 1)).to_u64
      if type.signed? && width < 64 && (bits & (1_u64 << (width - 1))) != 0
        bits |= UInt64::MAX << width
      end
      bits
    end

    def normalize_integer_register(register : X86_64Register, type : IrType) : Nil
      return unless type.integer?
      width = integer_bit_width(type)
      return if width == 64

      shift = (64 - width).to_u8
      @code.shift_left_register(register, shift)
      if type.signed?
        @code.shift_right_arithmetic_register(register, shift)
      else
        @code.shift_right_logical_register(register, shift)
      end
    end

    private def integer_bit_width(type : IrType) : Int32
      if width = type.fixed_bit_width
        return width
      end
      return 64 if type == IrType::Isize || type == IrType::Usize

      raise X86_64BackendFailure.new("unsupported integer type #{type}")
    end

    def initialize_parameters(function : IrFunction) : Nil
      parameters = function.parameters.reject { |parameter| parameter.type.zero_sized? }
      has_hidden_result = function.signature.result_type.is_a?(IrArrayType) && !function.signature.result_type.zero_sized?
      hidden_argument_count = has_hidden_result ? 1 : 0
      staged_count = {parameters.size + hidden_argument_count, ARGUMENT_REGISTERS.size}.min

      staged_count.times do |index|
        @code.move_rbp_from_register(@frame.argument_stage_offset(index), ARGUMENT_REGISTERS[index])
      end

      if has_hidden_result
        @code.move_register_from_rbp(X86_64Register::Rax, @frame.argument_stage_offset(0))
        @code.move_rbp_from_register(@frame.hidden_return_pointer_offset, X86_64Register::Rax)
      end

      parameters.each_with_index do |parameter, index|
        machine_index = index + hidden_argument_count
        if machine_index < staged_count
          @code.move_register_from_rbp(X86_64Register::Rax, @frame.argument_stage_offset(machine_index))
        else
          stack_offset = 16 + (machine_index - ARGUMENT_REGISTERS.size) * 8
          @code.move_register_from_rbp(X86_64Register::Rax, stack_offset)
        end
        unless parameter.type.is_a?(IrArrayType)
          normalize_integer_register(X86_64Register::Rax, parameter.type)
        end
        location(parameter.value_id).store_from(@code, X86_64Register::Rax, @frame)
      end
    end

    def initialize_frame(function : IrFunction) : Nil
      set_function_name(function.name)
      set_source_location(IrSourceLocation.new("<ir>", 0))
    end

    def set_source_location(location : IrSourceLocation) : Nil
      label = intern_literal(location.file)
      @code.lea_rip_relative(X86_64Register::Rax, label)
      @code.move_rbp_from_register(@frame.source_file_offset, X86_64Register::Rax)
      @code.move_immediate_to_memory(X86_64Register::Rbp, @frame.source_file_length_offset, location.file.bytesize.to_u32)
      line = location.line.to_s
      line_label = intern_literal(line)
      @code.lea_rip_relative(X86_64Register::Rax, line_label)
      @code.move_rbp_from_register(@frame.source_line_offset, X86_64Register::Rax)
      @code.move_immediate_to_memory(X86_64Register::Rbp, @frame.source_line_length_offset, line.bytesize.to_u32)
    end

    def append_string_literals : Nil
      @literal_order.each do |value, label|
        @code.mark_label(label)
        @code.write_bytes(value.to_slice.to_a)
        @code.write_bytes([0_u8])
      end
    end

    def emit_invoke(call : MachineCall) : Nil
      @allocation.call_spills_at(call.position).each do |spill|
        @code.move_rbp_from_register(@frame.spill_offset(spill.slot), spill.register)
      end

      argument_index = 0
      if call.result_type.is_a?(IrArrayType) && !call.result_type.zero_sized?
        location(call.result_id).load_to(@code, X86_64Register::Rax, @frame)
        @code.move_rbp_from_register(@frame.argument_stage_offset(0), X86_64Register::Rax)
        argument_index = 1
      end
      call.arguments.each_with_index do |value_id, parameter_index|
        next if call.argument_types[parameter_index].zero_sized?

        location(value_id).load_to(@code, X86_64Register::Rax, @frame)
        if argument_index < ARGUMENT_REGISTERS.size
          @code.move_rbp_from_register(@frame.argument_stage_offset(argument_index), X86_64Register::Rax)
        else
          stack_index = argument_index - ARGUMENT_REGISTERS.size
          @code.move_rsp_from_register(@frame.outgoing_stack_argument_offset(stack_index), X86_64Register::Rax)
        end
        argument_index += 1
      end

      {argument_index, ARGUMENT_REGISTERS.size}.min.times do |index|
        @code.move_register_from_rbp(ARGUMENT_REGISTERS[index], @frame.argument_stage_offset(index))
      end

      relocation_offset = @code.emit_call
      @relocations << X86_64Relocation.new(relocation_offset, call.function_id)

      unless call.result_type.zero_sized?
        @code.move_rbp_from_register(@frame.invoke_normal_result_offset, X86_64Register::Rax)
      end
      @code.move_rbp_from_register(@frame.invoke_exception_offset, X86_64Register::Rdx)

      @allocation.call_spills_at(call.position).each do |spill|
        @code.move_register_from_rbp(spill.register, @frame.spill_offset(spill.slot))
      end

      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_exception_offset)
      @code.test_register(X86_64Register::Rax)
      exception_result_label = @code.new_label
      @code.jump_if_not_zero_to(exception_result_label)
      unless call.result_type.zero_sized?
        @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_normal_result_offset)
        location(call.result_id).store_from(@code, X86_64Register::Rax, @frame)
      end
      @code.jump_to(call.normal_successor_label)
      @code.mark_label(exception_result_label)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_exception_offset)
      location(call.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(call.exception_successor_label)
    end

    def emit_integer_division(division : MachineIntegerDivision) : Nil
      spills = @allocation.call_spills_at(division.position)
      save_call_spills(spills)
      zero_divisor_label = @code.new_label
      normal_divisor = location(division.right_id)
      normal_divisor.load_to(@code, X86_64Register::Rcx, @frame)
      @code.test_register(X86_64Register::Rcx)
      @code.jump_if_zero_to(zero_divisor_label)

      location(division.left_id).load_to(@code, X86_64Register::Rax, @frame)
      normal_divisor.load_to(@code, X86_64Register::Rcx, @frame)
      if division.type.signed?
        emit_signed_division(division, zero_divisor_label)
      else
        @code.xor_register(X86_64Register::Rdx)
        @code.divide_by_register(X86_64Register::Rcx, false)
        @code.move_register(X86_64Register::Rax, X86_64Register::Rdx) if division.remainder?
      end
      normalize_integer_register(X86_64Register::Rax, division.type)

      @code.move_rbp_from_register(@frame.invoke_normal_result_offset, X86_64Register::Rax)
      restore_call_spills(spills)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_normal_result_offset)
      location(division.result_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(division.normal_successor_label)

      @code.mark_label(zero_divisor_label)
      call_runtime(X86_64RuntimeSymbols::DIVISION_BY_ZERO)
      @code.move_rbp_from_register(@frame.invoke_exception_offset, X86_64Register::Rax)
      restore_call_spills(spills)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_exception_offset)
      location(division.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(division.exception_successor_label)
    end

    def emit_array_literal(literal : MachineArrayLiteral) : Nil
      element_type = literal.array_type.element_type
      element_size = storage_size(element_type)
      literal.elements.each_with_index do |value_id, index|
        destination_offset = frame.array_offset(literal.result_id) + index * element_size
        if element_type.is_a?(IrArrayType)
          location(value_id).load_to(@code, X86_64Register::Rax, @frame)
          @frame.copy_address_to_memory(@code, X86_64Register::Rax, X86_64Register::Rbp, destination_offset, element_size)
        else
          location(value_id).load_to(@code, X86_64Register::Rax, @frame)
          @code.move_rbp_from_register_sized(destination_offset, X86_64Register::Rax, element_size * 8)
        end
      end
    end

    def emit_pointer_load(load : MachinePointerLoad) : Nil
      value_type = load.pointer_type.pointee_type
      location(load.address_id).load_to(@code, X86_64Register::Rax, @frame)
      @code.move_register_from_memory_sized(
        X86_64Register::Rax,
        X86_64Register::Rax,
        0,
        storage_size(value_type) * 8,
        value_type.signed?
      )
      normalize_integer_register(X86_64Register::Rax, value_type)
      location(load.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end

    def emit_stack_allocate(allocation : MachineStackAllocate) : Nil
      value_type = allocation.pointer_type.pointee_type
      location(allocation.initial_value_id).load_to(@code, X86_64Register::Rax, @frame)
      @code.move_rbp_from_register_sized(
        @frame.stack_allocation_offset(allocation.instruction_id),
        X86_64Register::Rax,
        storage_size(value_type) * 8
      )
      @code.lea_rbp_relative(X86_64Register::Rax, @frame.stack_allocation_offset(allocation.instruction_id))
      location(allocation.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end

    def emit_stack_storage(storage : MachineStackStorage) : Nil
      @code.lea_rbp_relative(X86_64Register::Rax, @frame.stack_storage_offset(storage.instruction_id))
      alignment = storage.alignment.to_i32
      @code.add_immediate_register(X86_64Register::Rax, alignment - 1)
      @code.and_immediate_register(X86_64Register::Rax, -alignment)
      location(storage.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end

    def emit_pointer_offset(offset : MachinePointerOffset) : Nil
      location(offset.address_id).load_to(@code, X86_64Register::Rax, @frame)
      location(offset.index_id).load_to(@code, X86_64Register::R10, @frame)
      scale_index(offset.pointer_type.pointee_type, X86_64Register::R10)
      @code.add_register(X86_64Register::Rax, X86_64Register::R10)
      location(offset.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end

    def emit_pointer_cast(pointer_cast : MachinePointerCast) : Nil
      location(pointer_cast.address_id).load_to(@code, X86_64Register::Rax, @frame)
      location(pointer_cast.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end

    def emit_pointer_store(store : MachinePointerStore) : Nil
      location(store.address_id).load_to(@code, X86_64Register::Rax, @frame)
      location(store.value_id).load_to(@code, X86_64Register::R11, @frame)
      @code.move_memory_from_register_sized(
        X86_64Register::Rax,
        0,
        X86_64Register::R11,
        storage_size(store.pointer_type.pointee_type) * 8
      )
    end

    def emit_pointer_free(release : MachinePointerFree) : Nil
      spills = @allocation.call_spills_at(release.position)
      save_call_spills(spills)
      location(release.address_id).load_to(@code, X86_64Register::Rdi, @frame)
      @code.move_immediate(X86_64Register::Rsi, storage_size(release.pointer_type.pointee_type).to_u64)
      @code.move_immediate(X86_64Register::Rax, X86_64RuntimeEmitter::UNMAP_SYSCALL)
      @code.emit_syscall
      restore_call_spills(spills)
    end

    def emit_allocate(allocation : MachineAllocate) : Nil
      spills = @allocation.call_spills_at(allocation.position)
      save_call_spills(spills)

      location(allocation.initial_value_id).load_to(@code, X86_64Register::R10, @frame)
      @code.move_rbp_from_register(@frame.invoke_normal_result_offset, X86_64Register::R10)
      @code.move_immediate(X86_64Register::Rax, X86_64RuntimeEmitter::MAP_SYSCALL)
      @code.xor_register(X86_64Register::Rdi)
      @code.move_immediate(X86_64Register::Rsi, storage_size(allocation.pointer_type.pointee_type).to_u64)
      @code.move_immediate(X86_64Register::Rdx, 3_u64)
      @code.move_immediate(X86_64Register::R10, 0x22_u64)
      @code.move_immediate(X86_64Register::R8, UInt64::MAX)
      @code.xor_register(X86_64Register::R9)
      @code.emit_syscall

      allocation_failed = @code.new_label
      @code.test_register(X86_64Register::Rax)
      @code.jump_if_sign_to(allocation_failed)
      @code.move_register_from_rbp(X86_64Register::R10, @frame.invoke_normal_result_offset)
      @code.move_memory_from_register_sized(
        X86_64Register::Rax,
        0,
        X86_64Register::R10,
        storage_size(allocation.pointer_type.pointee_type) * 8
      )
      @code.move_rbp_from_register(@frame.invoke_normal_result_offset, X86_64Register::Rax)
      @code.xor_register(X86_64Register::Rax)
      @code.move_rbp_from_register(@frame.invoke_exception_offset, X86_64Register::Rax)
      restore_call_spills(spills)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_normal_result_offset)
      location(allocation.result_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_exception_offset)
      location(allocation.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(allocation.normal_successor_label)

      @code.mark_label(allocation_failed)
      call_runtime(X86_64RuntimeSymbols::OUT_OF_MEMORY)
      @code.move_rbp_from_register(@frame.invoke_exception_offset, X86_64Register::Rax)
      restore_call_spills(spills)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_exception_offset)
      location(allocation.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(allocation.exception_successor_label)
    end

    def emit_array_get(access : MachineArrayAccess) : Nil
      spills = @allocation.call_spills_at(access.position)
      save_call_spills(spills)
      index = location(access.index_id)
      index.load_to(@code, X86_64Register::R10, @frame)
      bounds_failure = @code.new_label
      @code.compare_register_immediate(X86_64Register::R10, checked_array_length(access.array_type))
      @code.jump_if_above_or_equal_to(bounds_failure)

      location(access.array_id).load_to(@code, X86_64Register::Rax, @frame)
      scale_index(access.array_type.element_type, X86_64Register::R10)
      @code.add_register(X86_64Register::Rax, X86_64Register::R10)
      result_type = access.array_type.element_type
      if result_type.is_a?(IrArrayType)
        location(access.result_id).store_from(@code, X86_64Register::Rax, @frame)
      else
        @code.move_register_from_memory_sized(
          X86_64Register::Rax,
          X86_64Register::Rax,
          0,
          storage_size(result_type) * 8,
          result_type.signed?
        )
        normalize_integer_register(X86_64Register::Rax, result_type)
        location(access.result_id).store_from(@code, X86_64Register::Rax, @frame)
      end
      restore_call_spills(spills)
      @code.jump_to(access.normal_successor_label)

      @code.mark_label(bounds_failure)
      call_runtime(X86_64RuntimeSymbols::INDEX_OUT_OF_BOUNDS)
      restore_call_spills(spills)
      location(access.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(access.exception_successor_label)
    end

    def emit_array_set(update : MachineArrayUpdate) : Nil
      spills = @allocation.call_spills_at(update.position)
      save_call_spills(spills)
      index = location(update.index_id)
      index.load_to(@code, X86_64Register::R10, @frame)
      bounds_failure = @code.new_label
      @code.compare_register_immediate(X86_64Register::R10, checked_array_length(update.array_type))
      @code.jump_if_above_or_equal_to(bounds_failure)
      @code.move_rbp_from_register(@frame.invoke_normal_result_offset, X86_64Register::R10)

      location(update.array_id).load_to(@code, X86_64Register::Rax, @frame)
      @frame.copy_address_to_array(@code, X86_64Register::Rax, update.result_id)
      @code.move_register_from_rbp(X86_64Register::R10, @frame.invoke_normal_result_offset)
      location(update.result_id).load_to(@code, X86_64Register::Rax, @frame)
      scale_index(update.array_type.element_type, X86_64Register::R10)
      @code.add_register(X86_64Register::Rax, X86_64Register::R10)
      element_type = update.array_type.element_type
      if element_type.is_a?(IrArrayType)
        location(update.value_id).load_to(@code, X86_64Register::R11, @frame)
        @frame.copy_address_to_memory(@code, X86_64Register::R11, X86_64Register::Rax, 0, storage_size(element_type))
      else
        location(update.value_id).load_to(@code, X86_64Register::R11, @frame)
        @code.move_memory_from_register_sized(X86_64Register::Rax, 0, X86_64Register::R11, storage_size(element_type) * 8)
      end
      @code.move_immediate(X86_64Register::Rax, 0_u64)
      location(update.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      restore_call_spills(spills)
      @code.jump_to(update.normal_successor_label)

      @code.mark_label(bounds_failure)
      call_runtime(X86_64RuntimeSymbols::INDEX_OUT_OF_BOUNDS)
      restore_call_spills(spills)
      location(update.exception_id).store_from(@code, X86_64Register::Rax, @frame)
      @code.jump_to(update.exception_successor_label)
    end

    def emit_return(value_id : ValueId, result_type : IrType) : Nil
      if array_type = result_type.as?(IrArrayType)
        unless array_type.zero_sized?
          @code.move_register_from_rbp(X86_64Register::Rcx, @frame.hidden_return_pointer_offset)
          location(value_id).load_to(@code, X86_64Register::Rax, @frame)
          @frame.copy_address_to_memory(@code, X86_64Register::Rax, X86_64Register::Rcx, 0, storage_size(array_type))
          @code.move_register(X86_64Register::Rax, X86_64Register::Rcx)
        else
          @code.xor_register(X86_64Register::Rax)
        end
      else
        location(value_id).load_to(@code, X86_64Register::Rax, @frame)
      end
      @code.xor_register(X86_64Register::Rdx)
      @code.emit_epilogue
    end

    def emit_exception_dispatch(dispatch : MachineExceptionDispatch) : Nil
      location(dispatch.exception_id).load_to(@code, X86_64Register::Rax, @frame)
      @code.move_register_from_memory(X86_64Register::Rcx, X86_64Register::Rax, 0)
      dispatch.cases.each do |kind, target_label|
        unless kind
          @code.jump_to(target_label)
          return
        end
        @code.compare_register_immediate(X86_64Register::Rcx, exception_kind_tag(kind))
        @code.jump_if_equal_to(target_label)
      end
      target_label = dispatch.default_label
      raise X86_64BackendFailure.new("exception dispatch has no fallback successor") unless target_label
      @code.jump_to(target_label)
    end

    def emit_suppress_exception(suppress : MachineSuppressException) : Nil
      spills = @allocation.call_spills_at(suppress.position)
      save_call_spills(spills)
      location(suppress.new_exception_id).load_to(@code, X86_64Register::Rax, @frame)
      location(suppress.old_exception_id).load_to(@code, X86_64Register::Rcx, @frame)
      find_tail = @code.new_label
      append_suppressed = @code.new_label
      @code.move_register(X86_64Register::R10, X86_64Register::Rax)
      @code.mark_label(find_tail)
      @code.move_register_from_memory(X86_64Register::R11, X86_64Register::R10, 8)
      @code.test_register(X86_64Register::R11)
      @code.jump_if_zero_to(append_suppressed)
      @code.move_register(X86_64Register::R10, X86_64Register::R11)
      @code.jump_to(find_tail)
      @code.mark_label(append_suppressed)
      @code.move_memory_from_register(X86_64Register::R10, 8, X86_64Register::Rcx)
      @code.move_rbp_from_register(@frame.invoke_normal_result_offset, X86_64Register::Rax)
      restore_call_spills(spills)
      @code.move_register_from_rbp(X86_64Register::Rax, @frame.invoke_normal_result_offset)
      location(suppress.result_id).store_from(@code, X86_64Register::Rax, @frame)
    end

    def emit_exception_release(release : MachineExceptionRelease) : Nil
      spills = @allocation.call_spills_at(release.position)
      save_call_spills(spills)
      location(release.exception_id).load_to(@code, X86_64Register::Rdi, @frame)
      call_runtime(X86_64RuntimeSymbols::EXCEPTION_RELEASE)
      restore_call_spills(spills)
    end

    private def emit_signed_division(division : MachineIntegerDivision, zero_divisor_label : Int32) : Nil
      overflow_done_label = @code.new_label
      divide_label = @code.new_label
      width = integer_bit_width(division.type)
      minimum = -(1_i128 << (width - 1))
      minimum_bits = (minimum & ((1_i128 << width) - 1)).to_u64
      @code.move_immediate(X86_64Register::R10, minimum_bits)
      @code.compare_registers(X86_64Register::Rax, X86_64Register::R10)
      @code.jump_if_not_equal_to(divide_label)
      @code.move_immediate(X86_64Register::R10, UInt64::MAX)
      @code.compare_registers(X86_64Register::Rcx, X86_64Register::R10)
      @code.jump_if_not_equal_to(divide_label)
      @code.xor_register(X86_64Register::Rax) if division.remainder?
      @code.jump_to(overflow_done_label)
      @code.mark_label(divide_label)
      @code.sign_extend_rax_to_rdx
      @code.divide_by_register(X86_64Register::Rcx, true)
      @code.move_register(X86_64Register::Rax, X86_64Register::Rdx) if division.remainder?
      @code.mark_label(overflow_done_label)
    end

    private def save_call_spills(spills : Array(CallSpill)) : Nil
      spills.each do |spill|
        @code.move_rbp_from_register(@frame.spill_offset(spill.slot), spill.register)
      end
    end

    private def restore_call_spills(spills : Array(CallSpill)) : Nil
      spills.each do |spill|
        @code.move_register_from_rbp(spill.register, @frame.spill_offset(spill.slot))
      end
    end

    private def call_runtime(function_id : FunctionId) : Nil
      relocation_offset = @code.emit_call
      @relocations << X86_64Relocation.new(relocation_offset, function_id)
    end

    private def exception_kind_tag(kind : IrExceptionKind) : Int32
      case kind
      when IrExceptionKind::DivisionByZero
        1
      when IrExceptionKind::IndexOutOfBounds
        2
      when IrExceptionKind::OutOfMemory
        3
      else
        raise X86_64BackendFailure.new("unsupported exception kind #{kind}")
      end
    end

    private def checked_array_length(type : IrArrayType) : Int32
      raise X86_64BackendFailure.new("array length exceeds backend bounds-check range") if type.length > Int32::MAX
      type.length.to_i32
    end

    private def storage_size(type : IrType) : Int32
      size = type.storage_size || raise X86_64BackendFailure.new("type #{type.label} has no storage size")
      raise X86_64BackendFailure.new("type #{type.label} is too large for backend addressing") if size > Int32::MAX
      size.to_i32
    end

    private def scale_index(element_type : IrType, index_register : X86_64Register) : Nil
      stride = storage_size(element_type)
      return if stride <= 1
      raise X86_64BackendFailure.new("array element stride exceeds backend immediate range") if stride > Int32::MAX
      @code.multiply_immediate_register(index_register, stride)
    end

    private def set_function_name(name : String) : Nil
      label = intern_literal(name)
      @code.lea_rip_relative(X86_64Register::Rax, label)
      @code.move_rbp_from_register(@frame.function_name_offset, X86_64Register::Rax)
      @code.move_immediate_to_memory(X86_64Register::Rbp, @frame.function_name_length_offset, name.bytesize.to_u32)
    end

    private def intern_literal(value : String) : Int32
      if label = @literal_labels[value]?
        return label
      end
      label = @code.new_label
      @literal_labels[value] = label
      @literal_order << {value, label}
      label
    end
  end

  struct EmittedFunction
    getter function : IrFunction
    getter bytes : Array(UInt8)
    getter relocations : Array(X86_64Relocation)
    getter cfi_events : Array(X86_64CfiEvent)

    def initialize(
      @function : IrFunction,
      @bytes : Array(UInt8),
      @relocations : Array(X86_64Relocation),
      cfi_events : Array(X86_64CfiEvent),
    )
      @cfi_events = cfi_events.dup
    end
  end

  class X86_64FunctionEmitter
    def emit(function : IrFunction) : EmittedFunction
      instructions = X86_64InstructionSelector.new.lower(function)
      allocation = LinearScanRegisterAllocator.new.allocate(function, instructions)
      max_outgoing_arguments = instructions.map(&.outgoing_argument_count).max? || 0
      argument_register_count = X86_64EmissionContext::ARGUMENT_REGISTERS.size
      machine_parameter_count = function.parameters.count { |parameter| !parameter.type.zero_sized? }
      machine_parameter_count += 1 if function.signature.result_type.is_a?(IrArrayType) && !function.signature.result_type.zero_sized?
      parameter_stage_count = {machine_parameter_count, argument_register_count}.min
      call_stage_count = {max_outgoing_arguments, argument_register_count}.min
      staged_argument_count = parameter_stage_count > call_stage_count ? parameter_stage_count : call_stage_count
      outgoing_stack_argument_count = max_outgoing_arguments > argument_register_count ? max_outgoing_arguments - argument_register_count : 0
      frame = X86_64FrameLayout.new(function, allocation.spill_slot_count, staged_argument_count, outgoing_stack_argument_count)
      code = X86_64CodeBuffer.new
      code.emit_prologue(frame.frame_size)
      context = X86_64EmissionContext.new(code, frame, allocation)
      context.initialize_frame(function)
      context.initialize_parameters(function)
      instructions.each(&.emit(context))
      context.append_string_literals
      code.resolve_labels

      EmittedFunction.new(function, code.bytes.dup, context.relocations.dup, code.cfi_events)
    end
  end

  class X86_64EntryEmitter
    EXIT_SYSCALL      = 60_u64
    ENTRY_FUNCTION_ID = X86_64RuntimeSymbols::ENTRY

    def emit(user_main_id : FunctionId, expected_result : UInt64? = nil) : EmittedFunction
      code = X86_64CodeBuffer.new
      code.xor_register(X86_64Register::R15)
      call_offset = code.emit_call
      code.test_register(X86_64Register::Rdx)
      exception_label = code.new_label
      code.jump_if_not_zero_to(exception_label)
      relocations = [X86_64Relocation.new(call_offset, user_main_id)] of X86_64Relocation

      if expected = expected_result
        mismatch_label = code.new_label
        code.move_immediate(X86_64Register::R10, expected)
        code.compare_registers(X86_64Register::Rax, X86_64Register::R10)
        code.jump_if_not_equal_to(mismatch_label)
        emit_exit(code, 0_u64)
        code.mark_label(mismatch_label)
        emit_exit(code, 1_u64)
        code.mark_label(exception_label)
        emit_exit(code, 2_u64)
      else
        code.move_register(X86_64Register::Rdi, X86_64Register::Rax)
        code.move_immediate(X86_64Register::Rax, EXIT_SYSCALL)
        code.emit_syscall
        code.mark_label(exception_label)
        code.move_register(X86_64Register::Rdi, X86_64Register::Rdx)
        report_offset = code.emit_call
        relocations << X86_64Relocation.new(report_offset, X86_64RuntimeSymbols::REPORT_UNCAUGHT)
        emit_exit(code, 1_u64)
      end
      code.resolve_labels

      function = IrFunction.new(ENTRY_FUNCTION_ID, "_start", Array(IrType).new, IrType::Isize)
      EmittedFunction.new(function, code.bytes.dup, relocations, Array(X86_64CfiEvent).new)
    end

    private def emit_exit(code : X86_64CodeBuffer, status : UInt64) : Nil
      code.move_immediate(X86_64Register::Rdi, status)
      code.move_immediate(X86_64Register::Rax, EXIT_SYSCALL)
      code.emit_syscall
    end
  end

  class X86_64RuntimeEmitter
    MAP_SYSCALL                         =    9_u64
    UNMAP_SYSCALL                       =   11_u64
    WRITE_SYSCALL                       =    1_u64
    EXIT_SYSCALL                        =   60_u64
    PAGE_SIZE                           = 4096_u64
    EXCEPTION_KIND_DIVISION_BY_ZERO     =        1
    EXCEPTION_KIND_INDEX_OUT_OF_BOUNDS  =        2
    EXCEPTION_KIND_OUT_OF_MEMORY        =        3
    EXCEPTION_RECORD_KIND_OFFSET        =        0
    EXCEPTION_RECORD_SUPPRESSED_OFFSET  =        8
    EXCEPTION_RECORD_FRAME_COUNT_OFFSET =       16
    EXCEPTION_RECORD_FRAMES_OFFSET      =       24
    EXCEPTION_FRAME_SIZE                =       48
    MAX_EXCEPTION_FRAMES                =       64

    def emit : Array(EmittedFunction)
      [emit_division_by_zero, emit_index_out_of_bounds, emit_out_of_memory, emit_release, emit_report_uncaught]
    end

    private def emit_division_by_zero : EmittedFunction
      emit_exception_constructor(
        X86_64RuntimeSymbols::DIVISION_BY_ZERO,
        "__smalang_new_division_by_zero",
        EXCEPTION_KIND_DIVISION_BY_ZERO
      )
    end

    private def emit_index_out_of_bounds : EmittedFunction
      emit_exception_constructor(
        X86_64RuntimeSymbols::INDEX_OUT_OF_BOUNDS,
        "__smalang_new_index_out_of_bounds",
        EXCEPTION_KIND_INDEX_OUT_OF_BOUNDS
      )
    end

    private def emit_out_of_memory : EmittedFunction
      emit_exception_constructor(
        X86_64RuntimeSymbols::OUT_OF_MEMORY,
        "__smalang_new_out_of_memory",
        EXCEPTION_KIND_OUT_OF_MEMORY
      )
    end

    private def emit_exception_constructor(function_id : FunctionId, name : String, kind_tag : Int32) : EmittedFunction
      code = X86_64CodeBuffer.new
      capture_loop = code.new_label
      capture_done = code.new_label
      allocation_failed = code.new_label
      emit_exception_allocation(code, allocation_failed, kind_tag)
      emit_frame_capture_loop(code, capture_loop, capture_done)
      emit_exception_capture_return(code, capture_done)

      code.mark_label(allocation_failed)
      if kind_tag == EXCEPTION_KIND_OUT_OF_MEMORY
        emit_out_of_memory_fallback(code)
      else
        emit_exit(code, 127_u64)
      end
      code.resolve_labels
      emit_helper(function_id, name, code)
    end

    private def emit_out_of_memory_fallback(code : X86_64CodeBuffer) : Nil
      strings = X86_64RuntimeStringPool.new(code)
      frame_loop = code.new_label
      frame_done = code.new_label
      strings.write("Uncaught exception: OutOfMemory\n")
      code.move_register(X86_64Register::R12, X86_64Register::R15)
      code.xor_register(X86_64Register::R13)
      code.mark_label(frame_loop)
      code.test_register(X86_64Register::R12)
      code.jump_if_zero_to(frame_done)
      code.compare_register_immediate(X86_64Register::R13, MAX_EXCEPTION_FRAMES)
      code.jump_if_greater_equal_to(frame_done)
      strings.write("  at ")
      write_frame_field(code, strings, -16, -24)
      strings.write(" (")
      write_frame_field(code, strings, -32, -40)
      strings.write(":")
      write_frame_field(code, strings, -48, -56)
      strings.write(")\n")
      code.move_register_from_memory(X86_64Register::R12, X86_64Register::R12, -8)
      code.add_immediate_register(X86_64Register::R13, 1)
      code.jump_to(frame_loop)
      code.mark_label(frame_done)
      emit_exit(code, 1_u64)
      strings.append
    end

    private def write_frame_field(code : X86_64CodeBuffer, strings : X86_64RuntimeStringPool, pointer_offset : Int32, length_offset : Int32) : Nil
      code.move_register_from_memory(X86_64Register::Rsi, X86_64Register::R12, pointer_offset)
      code.move_register_from_memory(X86_64Register::Rdx, X86_64Register::R12, length_offset)
      strings.write_registers(X86_64Register::Rsi, X86_64Register::Rdx)
    end

    private def emit_exception_allocation(code : X86_64CodeBuffer, allocation_failed : Int32, kind_tag : Int32) : Nil
      code.move_immediate(X86_64Register::Rax, MAP_SYSCALL)
      code.xor_register(X86_64Register::Rdi)
      code.move_immediate(X86_64Register::Rsi, PAGE_SIZE)
      code.move_immediate(X86_64Register::Rdx, 3_u64)
      code.move_immediate(X86_64Register::R10, 0x22_u64)
      code.move_immediate(X86_64Register::R8, UInt64::MAX)
      code.xor_register(X86_64Register::R9)
      code.emit_syscall
      code.test_register(X86_64Register::Rax)
      code.jump_if_sign_to(allocation_failed)
      code.move_register(X86_64Register::Rdi, X86_64Register::Rax)
      code.move_immediate(X86_64Register::Rcx, kind_tag.to_u64)
      code.move_memory_from_register(X86_64Register::Rdi, EXCEPTION_RECORD_KIND_OFFSET, X86_64Register::Rcx)
    end

    private def emit_frame_capture_loop(code : X86_64CodeBuffer, capture_loop : Int32, capture_done : Int32) : Nil
      code.move_register(X86_64Register::Rsi, X86_64Register::R15)
      code.xor_register(X86_64Register::Rcx)
      code.mark_label(capture_loop)
      code.test_register(X86_64Register::Rsi)
      code.jump_if_zero_to(capture_done)
      code.compare_register_immediate(X86_64Register::Rcx, MAX_EXCEPTION_FRAMES)
      code.jump_if_greater_equal_to(capture_done)
      emit_frame_record_copy(code)
      code.move_register_from_memory(X86_64Register::Rsi, X86_64Register::Rsi, -8)
      code.add_immediate_register(X86_64Register::Rcx, 1)
      code.jump_to(capture_loop)
    end

    private def emit_frame_record_copy(code : X86_64CodeBuffer) : Nil
      code.move_register(X86_64Register::R10, X86_64Register::Rcx)
      code.shift_left_register(X86_64Register::R10, 4_u8)
      code.move_register(X86_64Register::R11, X86_64Register::Rcx)
      code.shift_left_register(X86_64Register::R11, 5_u8)
      code.add_register(X86_64Register::R10, X86_64Register::R11)
      code.move_register(X86_64Register::R11, X86_64Register::Rdi)
      code.add_immediate_register(X86_64Register::R11, EXCEPTION_RECORD_FRAMES_OFFSET)
      code.add_register(X86_64Register::R11, X86_64Register::R10)
      copy_frame_field(code, -16, 0)
      copy_frame_field(code, -24, 8)
      copy_frame_field(code, -32, 16)
      copy_frame_field(code, -40, 24)
      copy_frame_field(code, -48, 32)
      copy_frame_field(code, -56, 40)
    end

    private def copy_frame_field(code : X86_64CodeBuffer, frame_offset : Int32, record_offset : Int32) : Nil
      code.move_register_from_memory(X86_64Register::Rax, X86_64Register::Rsi, frame_offset)
      code.move_memory_from_register(X86_64Register::R11, record_offset, X86_64Register::Rax)
    end

    private def emit_exception_capture_return(code : X86_64CodeBuffer, capture_done : Int32) : Nil
      code.mark_label(capture_done)
      code.move_memory_from_register(X86_64Register::Rdi, EXCEPTION_RECORD_FRAME_COUNT_OFFSET, X86_64Register::Rcx)
      code.move_register(X86_64Register::Rax, X86_64Register::Rdi)
      code.xor_register(X86_64Register::Rdx)
      code.emit_return_instruction
    end

    private def emit_release : EmittedFunction
      code = X86_64CodeBuffer.new
      loop_label = code.new_label
      done_label = code.new_label
      code.mark_label(loop_label)
      code.test_register(X86_64Register::Rdi)
      code.jump_if_zero_to(done_label)
      code.move_register(X86_64Register::R8, X86_64Register::Rdi)
      code.move_register_from_memory(X86_64Register::R9, X86_64Register::R8, EXCEPTION_RECORD_SUPPRESSED_OFFSET)
      code.move_immediate(X86_64Register::Rax, UNMAP_SYSCALL)
      code.move_immediate(X86_64Register::Rsi, PAGE_SIZE)
      code.emit_syscall
      code.move_register(X86_64Register::Rdi, X86_64Register::R9)
      code.jump_to(loop_label)
      code.mark_label(done_label)
      code.xor_register(X86_64Register::Rax)
      code.xor_register(X86_64Register::Rdx)
      code.emit_return_instruction
      code.resolve_labels
      emit_helper(X86_64RuntimeSymbols::EXCEPTION_RELEASE, "__smalang_exception_release", code)
    end

    private def emit_report_uncaught : EmittedFunction
      code = X86_64CodeBuffer.new
      strings = X86_64RuntimeStringPool.new(code)
      exceptions = code.new_label
      frames = code.new_label
      no_frames = code.new_label
      code.move_register(X86_64Register::R12, X86_64Register::Rdi)
      code.xor_register(X86_64Register::R15)
      code.mark_label(exceptions)
      emit_exception_prefix(code, strings)
      emit_exception_kind(code, strings)
      emit_exception_frames(code, strings, frames, no_frames)
      code.mark_label(no_frames)
      code.move_register_from_memory(X86_64Register::R12, X86_64Register::R12, EXCEPTION_RECORD_SUPPRESSED_OFFSET)
      code.add_immediate_register(X86_64Register::R15, 1)
      code.test_register(X86_64Register::R12)
      code.jump_if_not_zero_to(exceptions)
      code.emit_return_instruction

      strings.append
      code.resolve_labels
      emit_helper(X86_64RuntimeSymbols::REPORT_UNCAUGHT, "__smalang_report_uncaught", code)
    end

    private def emit_exception_prefix(code : X86_64CodeBuffer, strings : X86_64RuntimeStringPool) : Nil
      suppressed_prefix = code.new_label
      after_prefix = code.new_label
      code.test_register(X86_64Register::R15)
      code.jump_if_not_zero_to(suppressed_prefix)
      strings.write("Uncaught exception: ")
      code.jump_to(after_prefix)
      code.mark_label(suppressed_prefix)
      strings.write("Suppressed exception: ")
      code.mark_label(after_prefix)
    end

    private def emit_exception_kind(code : X86_64CodeBuffer, strings : X86_64RuntimeStringPool) : Nil
      unknown_kind = code.new_label
      index_out_of_bounds = code.new_label
      out_of_memory = code.new_label
      done = code.new_label
      code.move_register_from_memory(X86_64Register::Rcx, X86_64Register::R12, EXCEPTION_RECORD_KIND_OFFSET)
      code.compare_register_immediate(X86_64Register::Rcx, EXCEPTION_KIND_DIVISION_BY_ZERO)
      code.jump_if_not_equal_to(index_out_of_bounds)
      strings.write("DivisionByZero\n")
      code.jump_to(done)
      code.mark_label(index_out_of_bounds)
      code.compare_register_immediate(X86_64Register::Rcx, EXCEPTION_KIND_INDEX_OUT_OF_BOUNDS)
      code.jump_if_not_equal_to(out_of_memory)
      strings.write("IndexOutOfBounds\n")
      code.jump_to(done)
      code.mark_label(out_of_memory)
      code.compare_register_immediate(X86_64Register::Rcx, EXCEPTION_KIND_OUT_OF_MEMORY)
      code.jump_if_not_equal_to(unknown_kind)
      strings.write("OutOfMemory\n")
      code.jump_to(done)
      code.mark_label(unknown_kind)
      strings.write("Unknown\n")
      code.mark_label(done)
    end

    private def emit_exception_frames(
      code : X86_64CodeBuffer,
      strings : X86_64RuntimeStringPool,
      loop_label : Int32,
      done_label : Int32,
    ) : Nil
      code.move_register_from_memory(X86_64Register::R13, X86_64Register::R12, EXCEPTION_RECORD_FRAME_COUNT_OFFSET)
      code.move_register(X86_64Register::R14, X86_64Register::R12)
      code.add_immediate_register(X86_64Register::R14, EXCEPTION_RECORD_FRAMES_OFFSET)
      code.mark_label(loop_label)
      code.test_register(X86_64Register::R13)
      code.jump_if_zero_to(done_label)
      strings.write("  at ")
      emit_exception_frame(code, strings)
      code.add_immediate_register(X86_64Register::R14, EXCEPTION_FRAME_SIZE)
      code.add_immediate_register(X86_64Register::R13, -1)
      code.jump_to(loop_label)
    end

    private def emit_exception_frame(code : X86_64CodeBuffer, strings : X86_64RuntimeStringPool) : Nil
      code.move_register_from_memory(X86_64Register::R10, X86_64Register::R14, 0)
      code.move_register_from_memory(X86_64Register::R9, X86_64Register::R14, 8)
      strings.write_registers(X86_64Register::R10, X86_64Register::R9)
      strings.write(" (")
      code.move_register_from_memory(X86_64Register::R10, X86_64Register::R14, 16)
      code.move_register_from_memory(X86_64Register::R9, X86_64Register::R14, 24)
      strings.write_registers(X86_64Register::R10, X86_64Register::R9)
      strings.write(":")
      code.move_register_from_memory(X86_64Register::R10, X86_64Register::R14, 32)
      code.move_register_from_memory(X86_64Register::R9, X86_64Register::R14, 40)
      strings.write_registers(X86_64Register::R10, X86_64Register::R9)
      strings.write(")\n")
    end

    private def emit_exit(code : X86_64CodeBuffer, status : UInt64) : Nil
      code.move_immediate(X86_64Register::Rdi, status)
      code.move_immediate(X86_64Register::Rax, EXIT_SYSCALL)
      code.emit_syscall
    end

    private def emit_helper(id : FunctionId, name : String, code : X86_64CodeBuffer) : EmittedFunction
      function = IrFunction.new(id, name, Array(IrType).new, IrType::Isize)
      EmittedFunction.new(function, code.bytes.dup, Array(X86_64Relocation).new, Array(X86_64CfiEvent).new)
    end
  end

  class X86_64RuntimeStringPool
    def initialize(@code : X86_64CodeBuffer)
      @labels = {} of String => Int32
      @entries = [] of Tuple(String, Int32)
    end

    def write(value : String) : Nil
      label = intern(value)
      @code.lea_rip_relative(X86_64Register::Rsi, label)
      @code.move_immediate(X86_64Register::Rdx, value.bytesize.to_u64)
      @code.move_immediate(X86_64Register::Rdi, 2_u64)
      @code.move_immediate(X86_64Register::Rax, X86_64RuntimeEmitter::WRITE_SYSCALL)
      @code.emit_syscall
    end

    def write_registers(pointer : X86_64Register, length : X86_64Register) : Nil
      @code.move_register(X86_64Register::Rsi, pointer)
      @code.move_register(X86_64Register::Rdx, length)
      @code.move_immediate(X86_64Register::Rdi, 2_u64)
      @code.move_immediate(X86_64Register::Rax, X86_64RuntimeEmitter::WRITE_SYSCALL)
      @code.emit_syscall
    end

    def append : Nil
      @entries.each do |value, label|
        @code.mark_label(label)
        @code.write_bytes(value.to_slice.to_a)
      end
    end

    private def intern(value : String) : Int32
      if label = @labels[value]?
        return label
      end
      label = @code.new_label
      @labels[value] = label
      @entries << {value, label}
      label
    end
  end

  struct ElfFunctionSymbol
    getter function : IrFunction
    getter offset : Int32
    getter size : Int32

    def initialize(@function : IrFunction, @offset : Int32, @size : Int32)
    end

    def global? : Bool
      @function.id == X86_64RuntimeSymbols::ENTRY || @function.name == "main"
    end

    def elf_name : String
      return "_start" if @function.id == X86_64RuntimeSymbols::ENTRY
      return "__smalang_user_main" if @function.name == "main"
      return @function.name if @function.id < 0
      ".Lsmalang_fn_#{@function.id}"
    end
  end

  struct X86_64EhFrameImage
    getter bytes : Array(UInt8)
    getter relocations : Array(X86_64EhFrameRelocation)

    def initialize(@bytes : Array(UInt8), @relocations : Array(X86_64EhFrameRelocation))
    end
  end

  class X86_64EhFrameWriter
    def write(
      functions : Array(ElfFunctionSymbol),
      cfi_events_by_function : Hash(FunctionId, Array(X86_64CfiEvent)),
    ) : X86_64EhFrameImage
      section = ByteBuffer.new
      append_cie(section)
      relocations = [] of X86_64EhFrameRelocation
      functions.each do |function|
        events = cfi_events_by_function[function.function.id]? || [] of X86_64CfiEvent
        append_fde(section, function, events, relocations)
      end
      X86_64EhFrameImage.new(section.bytes.dup, relocations)
    end

    private def append_cie(section : ByteBuffer) : Nil
      cie = ByteBuffer.new
      cie.write_u32(0_u32)
      cie.write_u32(0_u32)
      cie.write_u8(1_u8)
      cie.write_bytes([0x7a_u8, 0x52_u8, 0_u8]) # zR
      cie.write_u8(1_u8)                        # code alignment factor
      cie.write_u8(0x78_u8)                     # data alignment factor: -8
      cie.write_u8(16_u8)                       # return address register: RIP
      cie.write_u8(1_u8)                        # augmentation data length
      cie.write_u8(0x1b_u8)                     # DW_EH_PE_pcrel | DW_EH_PE_sdata4
      cie.write_bytes([0x0c_u8, 0x07_u8, 0x08_u8, 0x90_u8, 0x01_u8])
      cie.align(4)
      cie.overwrite_u32(0, (cie.size - 4).to_u32)
      section.write_bytes(cie.bytes)
    end

    private def append_fde(
      section : ByteBuffer,
      function : ElfFunctionSymbol,
      events : Array(X86_64CfiEvent),
      relocations : Array(X86_64EhFrameRelocation),
    ) : Nil
      fde_offset = section.size
      fde = ByteBuffer.new
      fde.write_u32(0_u32)
      cie_pointer_field = fde_offset + fde.size
      fde.write_u32(cie_pointer_field.to_u32)
      initial_location_offset = fde_offset + fde.size
      fde.write_u32(0_u32)
      fde.write_u32(function.size.to_u32)
      fde.write_u8(0_u8) # no FDE augmentation data
      append_cfi_instructions(fde, events)
      fde.align(4)
      fde.overwrite_u32(0, (fde.size - 4).to_u32)
      section.write_bytes(fde.bytes)
      relocations << X86_64EhFrameRelocation.new(initial_location_offset, function.offset)
    end

    private def append_cfi_instructions(buffer : ByteBuffer, events : Array(X86_64CfiEvent)) : Nil
      previous_offset = 0
      events.each do |event|
        delta = event.code_offset - previous_offset
        raise X86_64BackendFailure.new("CFI events are not ordered by code offset") if delta < 0
        if delta > 0
          buffer.write_u8(0x04_u8) # DW_CFA_advance_loc4
          buffer.write_u32(delta.to_u32)
        end
        buffer.write_bytes(event.instructions)
        previous_offset = event.code_offset
      end
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
    R_X86_64_PC32  =   2_u32
    R_X86_64_PLT32 =   4_u32

    TEXT_SECTION_INDEX        = 1_u32
    TEXT_SECTION_SYMBOL_INDEX = 1_u32
    EH_FRAME_SECTION_INDEX    = 3_u32
    SYMTAB_SECTION_INDEX      = 5_u32
    STRTAB_SECTION_INDEX      = 6_u32
    SHSTRTAB_SECTION_INDEX    = 7_u16

    def write(
      text : Array(UInt8),
      functions : Array(ElfFunctionSymbol),
      relocations : Array(X86_64Relocation),
      eh_frame : Array(UInt8),
      eh_frame_relocations : Array(X86_64EhFrameRelocation),
    ) : Array(UInt8)
      ensure_unique_main(functions)

      string_table = ElfStringTable.new
      symbols, symbol_indices, first_global_symbol = build_symbols(functions, string_table)
      rela_bytes = encode_relocations(relocations, symbol_indices)
      rela_eh_frame_bytes = encode_eh_frame_relocations(eh_frame_relocations)
      symbol_bytes = encode_symbols(symbols)
      section_names = ElfStringTable.new
      section_headers, section_data = build_sections(
        text,
        rela_bytes,
        eh_frame,
        rela_eh_frame_bytes,
        symbol_bytes,
        string_table.bytes,
        section_names
      )
      write_object(section_headers, section_data, first_global_symbol)
    end

    private def ensure_unique_main(functions : Array(ElfFunctionSymbol)) : Nil
      main_count = functions.count { |function| function.function.name == "main" }
      raise X86_64BackendFailure.new("module contains more than one main function") if main_count > 1
    end

    private def build_symbols(
      functions : Array(ElfFunctionSymbol),
      strings : ElfStringTable,
    ) : Tuple(Array(ElfSymbolEntry), Hash(FunctionId, UInt32), UInt32)
      symbols = [ElfSymbolEntry.new(0_u32, 0_u8, 0_u16, 0_u64, 0_u64)]
      symbols << ElfSymbolEntry.new(0_u32, (STB_LOCAL << 4) | STT_SECTION, 1_u16, 0_u64, 0_u64)
      symbols << ElfSymbolEntry.new(0_u32, (STB_LOCAL << 4) | STT_SECTION, EH_FRAME_SECTION_INDEX.to_u16, 0_u64, 0_u64)
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

    private def encode_eh_frame_relocations(
      relocations : Array(X86_64EhFrameRelocation),
    ) : Array(UInt8)
      buffer = ByteBuffer.new
      relocations.each do |relocation|
        info = (TEXT_SECTION_SYMBOL_INDEX.to_u64 << 32) | R_X86_64_PC32.to_u64
        buffer.write_u64(relocation.offset.to_u64)
        buffer.write_u64(info)
        buffer.write_i64(relocation.text_offset.to_i64)
      end
      buffer.bytes
    end

    private def build_sections(
      text : Array(UInt8),
      rela_text : Array(UInt8),
      eh_frame : Array(UInt8),
      rela_eh_frame : Array(UInt8),
      symbols : Array(UInt8),
      strings : Array(UInt8),
      section_names : ElfStringTable,
    ) : Tuple(Array(ElfSectionHeader), Array(NamedTuple(name: String, bytes: Array(UInt8), alignment: Int32)))
      text_name = section_names.add(".text")
      rela_text_name = section_names.add(".rela.text")
      eh_frame_name = section_names.add(".eh_frame")
      rela_eh_frame_name = section_names.add(".rela.eh_frame")
      symtab_name = section_names.add(".symtab")
      strtab_name = section_names.add(".strtab")
      shstrtab_name = section_names.add(".shstrtab")
      stack_name = section_names.add(".note.GNU-stack")

      data = [
        {name: ".text", bytes: text, alignment: 16},
        {name: ".rela.text", bytes: rela_text, alignment: 8},
        {name: ".eh_frame", bytes: eh_frame, alignment: 8},
        {name: ".rela.eh_frame", bytes: rela_eh_frame, alignment: 8},
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
      headers << ElfSectionHeader.new(rela_text_name, SHT_RELA, 0_u64, offsets[".rela.text"], rela_text.size.to_u64, SYMTAB_SECTION_INDEX, TEXT_SECTION_INDEX, 8_u64, 24_u64)
      headers << ElfSectionHeader.new(eh_frame_name, SHT_PROGBITS, SHF_ALLOC, offsets[".eh_frame"], eh_frame.size.to_u64, 0_u32, 0_u32, 8_u64, 0_u64)
      headers << ElfSectionHeader.new(rela_eh_frame_name, SHT_RELA, 0_u64, offsets[".rela.eh_frame"], rela_eh_frame.size.to_u64, SYMTAB_SECTION_INDEX, EH_FRAME_SECTION_INDEX, 8_u64, 24_u64)
      headers << ElfSectionHeader.new(symtab_name, SHT_SYMTAB, 0_u64, offsets[".symtab"], symbols.size.to_u64, STRTAB_SECTION_INDEX, 0_u32, 8_u64, 24_u64)
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
        if index == SYMTAB_SECTION_INDEX
          header = ElfSectionHeader.new(header.name_offset, header.type, header.flags, header.offset, header.size, header.link, first_global_symbol, header.alignment, header.entry_size)
        end
        header.write_to(buffer)
      end
      write_elf_header(buffer.bytes, section_header_offset.to_u64, headers.size.to_u16, SHSTRTAB_SECTION_INDEX)
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
      emit_object(ir_module, nil)
    end

    def emit_with_main_result_assertion(ir_module : IrModule, expected_result : UInt64) : Array(UInt8)
      emit_object(ir_module, expected_result)
    end

    private def emit_object(ir_module : IrModule, expected_result : UInt64?) : Array(UInt8)
      diagnostics = ir_module.verify
      unless diagnostics.empty?
        raise X86_64BackendFailure.new("cannot emit invalid IR:\n#{diagnostics.join("\n")}")
      end

      text = ByteBuffer.new
      function_symbols = [] of ElfFunctionSymbol
      relocations = [] of X86_64Relocation
      cfi_events_by_function = {} of FunctionId => Array(X86_64CfiEvent)
      ir_module.each_function do |function|
        text.align(16)
        text_offset = text.size
        emitted = X86_64FunctionEmitter.new.emit(function)
        text.write_bytes(emitted.bytes)
        function_symbols << ElfFunctionSymbol.new(function, text_offset, emitted.bytes.size)
        cfi_events_by_function[function.id] = emitted.cfi_events
        emitted.relocations.each do |relocation|
          relocations << X86_64Relocation.new(text_offset + relocation.offset, relocation.function_id)
        end
      end

      main_function = nil.as(IrFunction?)
      ir_module.each_function do |function|
        main_function = function if function.name == "main"
      end
      unless main_function
        raise X86_64BackendFailure.new("executable module must define main")
      end
      main = main_function.not_nil!
      if main.signature.result_type.zero_sized?
        raise X86_64BackendFailure.new("main cannot return unit because the entrypoint requires an exit status")
      end

      X86_64RuntimeEmitter.new.emit.each do |runtime_function|
        text.align(16)
        runtime_offset = text.size
        text.write_bytes(runtime_function.bytes)
        function_symbols << ElfFunctionSymbol.new(runtime_function.function, runtime_offset, runtime_function.bytes.size)
        cfi_events_by_function[runtime_function.function.id] = runtime_function.cfi_events
        runtime_function.relocations.each do |relocation|
          relocations << X86_64Relocation.new(runtime_offset + relocation.offset, relocation.function_id)
        end
      end

      text.align(16)
      entry_offset = text.size
      entry = X86_64EntryEmitter.new.emit(main.id, expected_result)
      text.write_bytes(entry.bytes)
      function_symbols << ElfFunctionSymbol.new(entry.function, entry_offset, entry.bytes.size)
      entry.relocations.each do |relocation|
        relocations << X86_64Relocation.new(entry_offset + relocation.offset, relocation.function_id)
      end
      cfi_events_by_function[entry.function.id] = entry.cfi_events

      eh_frame = X86_64EhFrameWriter.new.write(function_symbols, cfi_events_by_function)
      X86_64ElfObjectWriter.new.write(text.bytes, function_symbols, relocations, eh_frame.bytes, eh_frame.relocations)
    end
  end
end
