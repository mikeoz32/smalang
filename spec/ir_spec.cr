require "spec"
require "../src/smalang/ir"

FIXED_WIDTH_IR_TYPES = [
  Smalang::IrType::Int8,
  Smalang::IrType::UInt8,
  Smalang::IrType::Int16,
  Smalang::IrType::UInt16,
  Smalang::IrType::Int32,
  Smalang::IrType::UInt32,
  Smalang::IrType::Int64,
  Smalang::IrType::UInt64,
]

describe Smalang::IrModule do
  it "represents fixed arrays as recursive, inline IR types" do
    byte_array = Smalang::IrArrayType.new(Smalang::IrType::Int8, 3_u128)
    nested_array = Smalang::IrArrayType.new(byte_array, 2_u128)
    empty_array = Smalang::IrArrayType.new(Smalang::IrType::Usize, 0_u128)

    byte_array.label.should eq("array[int8, 3]")
    byte_array.storage_size.should eq(3_u128)
    nested_array.label.should eq("array[array[int8, 3], 2]")
    nested_array.storage_size.should eq(6_u128)
    empty_array.zero_sized?.should be_true
    empty_array.storage_size.should eq(0_u128)
    Smalang::IrArrayType.new(Smalang::IrType::Unit, 1_u128).valid_element_type?.should be_false
  end

  it "dumps typed array literals and checked indexed reads in s notation" do
    ir = Smalang::IrModule.new
    array_type = Smalang::IrArrayType.new(Smalang::IrType::Isize, 2_u128)
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    first = function.emit_constant(entry, Smalang::IrType::Isize, 10)
    second = function.emit_constant(entry, Smalang::IrType::Isize, 20)
    array = function.emit_array_literal(entry, array_type, [first, second])
    index = function.emit_constant(entry, Smalang::IrType::Usize, 1)
    normal = function.add_block("normal")
    unwind = function.add_block("unwind")
    result = function.emit_invoke_array_get(entry, array, index, array_type, normal, unwind)
    function.emit_return(normal, result.value_id)
    function.emit_resume_exception(unwind, result.exception_id)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(%v2 array[isize, 2] (array %v0 %v1))")
    dump.should contain("(invoke (array.get %v2 %v3) (normal @normal %v4) (exception @unwind %v5)")
    ir.verify.should be_empty
  end

  it "verifies and dumps checked indexed array updates" do
    ir = Smalang::IrModule.new
    array_type = Smalang::IrArrayType.new(Smalang::IrType::Isize, 2_u128)
    function = ir.add_function("replace", Array(Smalang::IrType).new, array_type)
    entry = function.entry_block_id
    first = function.emit_constant(entry, Smalang::IrType::Isize, 10)
    second = function.emit_constant(entry, Smalang::IrType::Isize, 20)
    array = function.emit_array_literal(entry, array_type, [first, second])
    index = function.emit_constant(entry, Smalang::IrType::Usize, 1)
    replacement = function.emit_constant(entry, Smalang::IrType::Isize, 42)
    normal = function.add_block("normal")
    unwind = function.add_block("unwind")
    result = function.emit_invoke_array_set(entry, array, index, replacement, array_type, normal, unwind)
    function.emit_return(normal, result.value_id)
    function.emit_resume_exception(unwind, result.exception_id)

    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(invoke (array.set %v2 %v3 %v4)")
    ir.verify.should be_empty
  end

  it "rejects arrays containing IR-only unit values" do
    ir = Smalang::IrModule.new
    array_type = Smalang::IrArrayType.new(Smalang::IrType::Unit, 1_u128)
    parameter_types = Array(Smalang::IrType).new
    parameter_types << array_type
    function = ir.add_function("invalid", parameter_types, Smalang::IrType::Isize)
    value = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, 0)
    function.emit_return(function.entry_block_id, value)

    ir.verify.join("\n").should contain("array type with unsupported elements")
  end

  it "rejects raw pointers as inline array elements" do
    ir = Smalang::IrModule.new
    pointer_type = Smalang::IrPointerType.new(Smalang::IrType::Int64)
    array_type = Smalang::IrArrayType.new(pointer_type, 1_u128)
    parameter_types = [] of Smalang::IrType
    parameter_types << array_type
    function = ir.add_function("invalid", parameter_types, Smalang::IrType::Isize)
    result = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, 0)
    function.emit_return(function.entry_block_id, result)

    ir.verify.join("\n").should contain("array type with unsupported elements")
  end

  it "rejects pointer signatures with unsupported pointee types" do
    pointer_types = [
      Smalang::IrPointerType.new(Smalang::IrType::Unit),
      Smalang::IrPointerType.new(Smalang::IrArrayType.new(Smalang::IrType::Int64, 2_u128)),
    ]

    pointer_types.each do |pointer_type|
      ir = Smalang::IrModule.new
      parameter_types = [] of Smalang::IrType
      parameter_types << pointer_type
      function = ir.add_function("invalid", parameter_types, pointer_type)
      function.emit_return(function.entry_block_id, function.parameters.first.value_id)

      diagnostics = ir.verify.join("\n")
      diagnostics.should contain("parameter 0 has pointer type #{pointer_type.label} with unsupported pointee")
      diagnostics.should contain("result has pointer type #{pointer_type.label} with unsupported pointee")
    end
  end

  it "rejects stack allocation with an initial value of the wrong scalar type" do
    ir = Smalang::IrModule.new
    function = ir.add_function("invalid", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    value = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, 7)
    pointer_type = Smalang::IrPointerType.new(Smalang::IrType::Int8)
    function.emit_stack_allocate(function.entry_block_id, value, pointer_type)
    function.emit_return(function.entry_block_id, value)

    ir.verify.join("\n").should contain("stack.alloc value has type isize, expected int8")
  end

  it "rejects stack allocation with a non-scalar pointee type" do
    pointer_types = [
      Smalang::IrPointerType.new(Smalang::IrType::Unit),
      Smalang::IrPointerType.new(Smalang::IrArrayType.new(Smalang::IrType::Isize, 2_u128)),
    ]

    pointer_types.each do |pointer_type|
      ir = Smalang::IrModule.new
      function = ir.add_function("invalid", Array(Smalang::IrType).new, Smalang::IrType::Isize)
      value = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, 7)
      function.emit_stack_allocate(function.entry_block_id, value, pointer_type)
      function.emit_return(function.entry_block_id, value)

      ir.verify.join("\n").should contain("stack.alloc pointer type #{pointer_type.label} has an unsupported pointee")
    end
  end

  it "represents typed pointer offsets in s notation for each scalar storage width" do
    ir = Smalang::IrModule.new
    pointer_types = [
      Smalang::IrPointerType.new(Smalang::IrType::Bool),
      Smalang::IrPointerType.new(Smalang::IrType::Int16),
      Smalang::IrPointerType.new(Smalang::IrType::Int32),
      Smalang::IrPointerType.new(Smalang::IrType::Int64),
    ] of Smalang::IrType
    parameter_types = pointer_types.dup
    parameter_types << Smalang::IrType::Usize
    function = ir.add_function("offsets", parameter_types, pointer_types.last)
    index = function.parameters.last.value_id
    result = nil.as(Smalang::ValueId?)

    pointer_types.each_with_index do |pointer_type, index_in_types|
      result = function.emit_pointer_offset(
        function.entry_block_id,
        function.parameters[index_in_types].value_id,
        index,
        pointer_type.as(Smalang::IrPointerType)
      )
    end
    function.emit_return(function.entry_block_id, result.not_nil!)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(offset %v0 %v4)")
    dump.should contain("(offset %v1 %v4)")
    dump.should contain("(offset %v2 %v4)")
    dump.should contain("(offset %v3 %v4)")
    ir.verify.should be_empty
  end

  it "rejects pointer offsets with an integer address or a signed index" do
    ir = Smalang::IrModule.new
    function = ir.add_function("invalid", [Smalang::IrType::Isize, Smalang::IrType::Isize], Smalang::IrPointerType.new(Smalang::IrType::Isize))
    result = function.emit_pointer_offset(
      function.entry_block_id,
      function.parameters[0].value_id,
      function.parameters[1].value_id,
      Smalang::IrPointerType.new(Smalang::IrType::Isize)
    )
    function.emit_return(function.entry_block_id, result)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("offset address has type isize, expected ptr[isize]")
    diagnostics.should contain("offset index has type isize, expected usize")
  end

  it "verifies and dumps scalar pointer casts in s notation" do
    ir = Smalang::IrModule.new
    source_type = Smalang::IrPointerType.new(Smalang::IrType::Int64)
    target_type = Smalang::IrPointerType.new(Smalang::IrType::UInt64)
    parameter_types = [] of Smalang::IrType
    parameter_types << source_type
    function = ir.add_function("cast", parameter_types, target_type)
    result = function.emit_pointer_cast(function.entry_block_id, function.parameters.first.value_id, target_type)
    function.emit_return(function.entry_block_id, result)

    ir.verify.should be_empty
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(ptr.cast %v0)")
  end

  it "verifies and dumps stack storage layout in s notation" do
    ir = Smalang::IrModule.new
    pointer_type = Smalang::IrPointerType.new(Smalang::IrType::UInt8)
    function = ir.add_function("storage", Array(Smalang::IrType).new, pointer_type)
    result = function.emit_stack_storage(function.entry_block_id, 24_u64, 64_u64)
    function.emit_return(function.entry_block_id, result)

    ir.verify.should be_empty
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(stack.storage 24 64)")
    effects = function.instruction(0).not_nil!.memory_effects
    effects.allocates.should eq(true)
    effects.reads.should eq(false)
    effects.writes.should eq(false)
    effects.frees.should eq(false)
  end

  it "verifies and dumps byte copying with explicit read and write effects" do
    byte_pointer = Smalang::IrPointerType.new(Smalang::IrType::UInt8)
    ir = Smalang::IrModule.new
    function = ir.add_function("copy", [byte_pointer, byte_pointer, Smalang::IrType::Usize], Smalang::IrType::Unit)
    destination = function.parameters[0].value_id
    source = function.parameters[1].value_id
    byte_count = function.parameters[2].value_id
    result = function.emit_copy_memory(function.entry_block_id, destination, source, byte_count)
    function.emit_return(function.entry_block_id, result)

    ir.verify.should be_empty
    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(%v3 unit (copy.memory %v0 %v1 %v2))")
    copy = function.instruction(0).not_nil!
    copy.result_type.should eq(Smalang::IrType::Unit)
    copy.memory_effects.reads.should be_true
    copy.memory_effects.writes.should be_true
    copy.memory_effects.allocates.should be_false
    copy.memory_effects.frees.should be_false
  end

  it "rejects copy instructions with non-byte pointers or non-uint sizes" do
    ir = Smalang::IrModule.new
    typed_pointer = Smalang::IrPointerType.new(Smalang::IrType::Int64)
    function = ir.add_function("invalid_copy", [typed_pointer, typed_pointer, Smalang::IrType::Isize], Smalang::IrType::Unit)
    result = function.emit_copy_memory(
      function.entry_block_id,
      function.parameters[0].value_id,
      function.parameters[1].value_id,
      function.parameters[2].value_id
    )
    function.emit_return(function.entry_block_id, result)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("copy.memory destination has type ptr[int64], expected ptr[uint8]")
    diagnostics.should contain("copy.memory source has type ptr[int64], expected ptr[uint8]")
    diagnostics.should contain("copy.memory byte count has type isize, expected usize")
  end

  it "rejects stack storage with zero size, zero or non-power-of-two alignment, and overflow" do
    ir = Smalang::IrModule.new
    pointer_type = Smalang::IrPointerType.new(Smalang::IrType::UInt8)
    [
      {0_u64, 8_u64},
      {8_u64, 0_u64},
      {8_u64, 3_u64},
      {UInt64::MAX, 8_u64},
    ].each_with_index do |(byte_size, alignment), index|
      function = ir.add_function("invalid_storage_#{index}", Array(Smalang::IrType).new, pointer_type)
      result = function.emit_stack_storage(function.entry_block_id, byte_size, alignment)
      function.emit_return(function.entry_block_id, result)
    end

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("stack.storage byte size must be greater than zero")
    diagnostics.should contain("stack.storage alignment must be greater than zero")
    diagnostics.should contain("stack.storage alignment must be a power of two")
    diagnostics.should contain("stack.storage size and alignment overflow uint")
  end

  it "rejects pointer casts with a non-pointer source or target" do
    ir = Smalang::IrModule.new
    function = ir.add_function("invalid_source", [Smalang::IrType::Isize], Smalang::IrType::Unit)
    invalid_target = Smalang::IrPointerType.new(Smalang::IrType::Unit)
    function.emit_pointer_cast(function.entry_block_id, function.parameters.first.value_id, invalid_target)
    unit = function.emit_unit_constant(function.entry_block_id)
    function.emit_return(function.entry_block_id, unit)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("pointer cast target type ptr[unit] has an unsupported pointee")
    diagnostics.should contain("pointer cast address has type isize, expected ptr[T]")

    invalid_pointer_type = Smalang::IrPointerType.new(Smalang::IrType::Unit)
    valid_pointer_type = Smalang::IrPointerType.new(Smalang::IrType::Int64)
    invalid_pointer_parameters = [] of Smalang::IrType
    invalid_pointer_parameters << invalid_pointer_type
    invalid_pointer_function = ir.add_function("invalid_pointer_source", invalid_pointer_parameters, valid_pointer_type)
    cast_result = invalid_pointer_function.emit_pointer_cast(
      invalid_pointer_function.entry_block_id,
      invalid_pointer_function.parameters.first.value_id,
      valid_pointer_type
    )
    invalid_pointer_function.emit_return(invalid_pointer_function.entry_block_id, cast_result)

    ir.verify.join("\n").should contain("pointer cast source type ptr[unit] has an unsupported pointee")
  end

  it "represents and dumps the first-slice program as typed SSA" do
    ir = Smalang::IrModule.new
    increment = ir.add_function(
      "increment",
      [Smalang::IrType::Isize],
      Smalang::IrType::Isize
    )
    entry = increment.entry_block_id
    value = increment.parameters[0].value_id
    one = increment.emit_constant(entry, Smalang::IrType::Isize, 1)
    sum = increment.emit_add(entry, Smalang::IrType::Isize, value, one)
    increment.emit_return(entry, sum)

    no_parameters = [] of Smalang::IrType
    main = ir.add_function("main", no_parameters, Smalang::IrType::Isize)
    entry = main.entry_block_id
    argument = main.emit_constant(entry, Smalang::IrType::Isize, 41)
    difference = main.emit_subtract(entry, Smalang::IrType::Isize, argument, argument)
    target = ir.internal_call_target(increment.id).not_nil!
    normal = main.add_block("normal")
    unwind = main.add_block("unwind")
    result = main.emit_invoke_call(entry, target, [difference], normal, unwind)
    main.emit_return(normal, result.value_id)
    main.emit_resume_exception(unwind, result.exception_id)
    ir.internal_call_target(-1).should be_nil

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(func @increment (param %v0 isize) (result isize)")
    dump.should contain("(%v2 isize (add %v0 %v1))")
    dump.should contain("(%v1 isize (sub %v0 %v0))")
    dump.should contain("(invoke (call @increment %v1) (normal @normal %v2) (exception @unwind %v3))")
    dump.should contain("(return %v2)")
    ir.verify.should be_empty
  end

  it "defines distinct typed IR values for every fixed-width integer" do
    fixed_widths = [
      {Smalang::IrType::Int8, 8, true},
      {Smalang::IrType::UInt8, 8, false},
      {Smalang::IrType::Int16, 16, true},
      {Smalang::IrType::UInt16, 16, false},
      {Smalang::IrType::Int32, 32, true},
      {Smalang::IrType::UInt32, 32, false},
      {Smalang::IrType::Int64, 64, true},
      {Smalang::IrType::UInt64, 64, false},
    ]
    labels = Smalang::IrType::SCALAR_TYPES.map(&.label)

    fixed_widths.each do |type, width, signed|
      label = type.label
      labels.should contain(label)
      type.fixed_bit_width.should eq(width)
      type.signed?.should eq(signed)
      type.integer?.should be_true
    end
    Smalang::IrType::Isize.fixed_bit_width.should be_nil
    Smalang::IrType::Isize.signed?.should be_true
    Smalang::IrType::Usize.fixed_bit_width.should be_nil
    Smalang::IrType::Usize.signed?.should be_false
  end

  it "accepts in-range constants for every fixed-width integer type" do
    cases = [
      {Smalang::IrType::Int8, -128_i128, 127_i128},
      {Smalang::IrType::UInt8, 0_i128, 255_i128},
      {Smalang::IrType::Int16, -32_768_i128, 32_767_i128},
      {Smalang::IrType::UInt16, 0_i128, 65_535_i128},
      {Smalang::IrType::Int32, -2_147_483_648_i128, 2_147_483_647_i128},
      {Smalang::IrType::UInt32, 0_i128, 4_294_967_295_i128},
      {Smalang::IrType::Int64, Int64::MIN.to_i128, Int64::MAX.to_i128},
      {Smalang::IrType::UInt64, 0_i128, UInt64::MAX.to_i128},
    ]
    ir = Smalang::IrModule.new

    cases.each do |type, minimum, maximum|
      function = ir.add_function("constants_#{type.label}", Array(Smalang::IrType).new, type)
      entry = function.entry_block_id
      function.emit_constant(entry, type, minimum)
      maximum_value = function.emit_constant(entry, type, maximum)
      function.emit_return(entry, maximum_value)
    end

    ir.verify.should be_empty
  end

  it "accepts addition for every fixed-width type" do
    ir = Smalang::IrModule.new

    FIXED_WIDTH_IR_TYPES.each do |type|
      function = ir.add_function("add_#{type.label}", [type, type], type)
      entry = function.entry_block_id
      left = function.parameters[0].value_id
      right = function.parameters[1].value_id
      sum = function.emit_add(entry, type, left, right)
      function.emit_return(entry, sum)
    end

    ir.verify.should be_empty
  end

  it "accepts subtraction for every fixed-width type" do
    ir = Smalang::IrModule.new

    FIXED_WIDTH_IR_TYPES.each do |type|
      function = ir.add_function("sub_#{type.label}", [type, type], type)
      entry = function.entry_block_id
      left = function.parameters[0].value_id
      right = function.parameters[1].value_id
      difference = function.emit_subtract(entry, type, left, right)
      function.emit_return(entry, difference)
    end

    ir.verify.should be_empty
  end

  it "accepts multiplication for every fixed-width type" do
    ir = Smalang::IrModule.new

    FIXED_WIDTH_IR_TYPES.each do |type|
      function = ir.add_function("mul_#{type.label}", [type, type], type)
      entry = function.entry_block_id
      left = function.parameters[0].value_id
      right = function.parameters[1].value_id
      product = function.emit_multiply(entry, type, left, right)
      function.emit_return(entry, product)
    end

    ir.verify.should be_empty
  end

  it "accepts division for every fixed-width type" do
    ir = Smalang::IrModule.new

    FIXED_WIDTH_IR_TYPES.each do |type|
      function = ir.add_function("div_#{type.label}", [type, type], type)
      entry = function.entry_block_id
      normal = function.add_block("normal")
      unwind = function.add_block("unwind")
      left = function.parameters[0].value_id
      right = function.parameters[1].value_id
      division = function.emit_invoke_divide(entry, type, left, right, normal, unwind)
      function.emit_return(normal, division.value_id)
      function.emit_resume_exception(unwind, division.exception_id)
    end

    ir.verify.should be_empty
  end

  it "accepts remainder for every fixed-width type" do
    ir = Smalang::IrModule.new

    FIXED_WIDTH_IR_TYPES.each do |type|
      function = ir.add_function("rem_#{type.label}", [type, type], type)
      entry = function.entry_block_id
      normal = function.add_block("normal")
      unwind = function.add_block("unwind")
      left = function.parameters[0].value_id
      right = function.parameters[1].value_id
      remainder = function.emit_invoke_remainder(entry, type, left, right, normal, unwind)
      function.emit_return(normal, remainder.value_id)
      function.emit_resume_exception(unwind, remainder.exception_id)
    end

    ir.verify.should be_empty
  end

  it "prints fixed-width integer names in S-expression dumps" do
    ir = Smalang::IrModule.new
    FIXED_WIDTH_IR_TYPES.each do |type|
      function = ir.add_function("value_#{type.label}", Array(Smalang::IrType).new, type)
      value = function.emit_constant(function.entry_block_id, type, 0)
      function.emit_return(function.entry_block_id, value)
    end

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    FIXED_WIDTH_IR_TYPES.each { |type| dump.should contain("#{type.label}") }
  end

  it "rejects constants outside fixed-width integer ranges" do
    invalid_values = [
      {Smalang::IrType::Int8, -129_i128},
      {Smalang::IrType::UInt8, 256_i128},
      {Smalang::IrType::Int16, -32_769_i128},
      {Smalang::IrType::UInt16, 65_536_i128},
      {Smalang::IrType::Int32, -2_147_483_649_i128},
      {Smalang::IrType::UInt32, 4_294_967_296_i128},
      {Smalang::IrType::Int64, Int64::MIN.to_i128 - 1},
      {Smalang::IrType::UInt64, UInt64::MAX.to_i128 + 1},
    ]
    ir = Smalang::IrModule.new

    invalid_values.each_with_index do |(type, value), index|
      function = ir.add_function("invalid_#{index}", Array(Smalang::IrType).new, type)
      constant = function.emit_constant(function.entry_block_id, type, value)
      function.emit_return(function.entry_block_id, constant)
    end

    diagnostics = ir.verify.join("\n")
    ["int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"].each do |label|
      diagnostics.should contain("constant does not fit #{label}")
    end
  end

  it "rejects mixed fixed-width operands in addition" do
    ir = Smalang::IrModule.new
    function = ir.add_function("mixed", [Smalang::IrType::Int8, Smalang::IrType::UInt8], Smalang::IrType::Int8)
    entry = function.entry_block_id
    left = function.parameters[0].value_id
    right = function.parameters[1].value_id
    sum = function.emit_add(entry, Smalang::IrType::Int8, left, right)
    function.emit_return(entry, sum)

    ir.verify.join("\n").should contain("add operands must have matching types")
  end

  it "rejects mixed fixed-width operands in division" do
    ir = Smalang::IrModule.new
    function = ir.add_function("mixed", [Smalang::IrType::Int8, Smalang::IrType::UInt8], Smalang::IrType::Int8)
    entry = function.entry_block_id
    normal = function.add_block("normal")
    unwind = function.add_block("unwind")
    left = function.parameters[0].value_id
    right = function.parameters[1].value_id
    division = function.emit_invoke_divide(entry, Smalang::IrType::Int8, left, right, normal, unwind)
    function.emit_return(normal, division.value_id)
    function.emit_resume_exception(unwind, division.exception_id)

    ir.verify.join("\n").should contain("div right operand has type uint8, expected int8")
  end

  it "represents boolean constants, signatures, and returns as typed SSA" do
    ir = Smalang::IrModule.new
    identity = ir.add_function("identity", [Smalang::IrType::Bool], Smalang::IrType::Bool)
    identity.emit_return(identity.entry_block_id, identity.parameters.first.value_id)

    literal = ir.add_function("literal", Array(Smalang::IrType).new, Smalang::IrType::Bool)
    truth = literal.emit_constant(literal.entry_block_id, Smalang::IrType::Bool, 1)
    literal.emit_return(literal.entry_block_id, truth)

    caller = ir.add_function("caller", Array(Smalang::IrType).new, Smalang::IrType::Bool)
    argument = caller.emit_constant(caller.entry_block_id, Smalang::IrType::Bool, 0)
    normal = caller.add_block("normal")
    unwind = caller.add_block("unwind")
    target = ir.internal_call_target(identity.id).not_nil!
    result = caller.emit_invoke_call(caller.entry_block_id, target, [argument], normal, unwind)
    caller.emit_return(normal, result.value_id)
    caller.emit_resume_exception(unwind, result.exception_id)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(func @identity (param %v0 bool) (result bool)")
    dump.should contain("(%v0 bool (const 1))")
    dump.should contain("(invoke (call @identity %v0) (normal @normal %v1) (exception @unwind %v2))")
    ir.verify.should be_empty
  end

  it "accepts boolean branch conditions and merges bool values through phi" do
    ir = Smalang::IrModule.new
    function = ir.add_function("choose", [Smalang::IrType::Bool], Smalang::IrType::Bool)
    entry = function.entry_block_id
    truth = function.add_block("truth")
    falsity = function.add_block("falsity")
    join = function.add_block("join")
    function.emit_branch(entry, function.parameters.first.value_id, truth, falsity)
    true_value = function.emit_constant(truth, Smalang::IrType::Bool, 1)
    function.emit_jump(truth, join)
    false_value = function.emit_constant(falsity, Smalang::IrType::Bool, 0)
    function.emit_jump(falsity, join)
    result = function.emit_phi(join, Smalang::IrType::Bool, [
      Smalang::IrPhiIncoming.new(truth, true_value),
      Smalang::IrPhiIncoming.new(falsity, false_value),
    ])
    function.emit_return(join, result)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(branch %v0 @truth @falsity)")
    dump.should contain("(%v3 bool (phi [@truth %v1] [@falsity %v2]))")
    ir.verify.should be_empty
  end

  it "rejects noncanonical boolean constants and boolean arithmetic" do
    ir = Smalang::IrModule.new
    function = ir.add_function("broken", Array(Smalang::IrType).new, Smalang::IrType::Bool)
    entry = function.entry_block_id
    invalid = function.emit_constant(entry, Smalang::IrType::Bool, 2)
    function.emit_add(entry, Smalang::IrType::Bool, invalid, invalid)
    function.emit_return(entry, invalid)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("bool constant must be 0 or 1")
    diagnostics.should contain("add requires integer operands and result, got bool")
  end

  it "represents multiplication as a typed SSA operation" do
    ir = Smalang::IrModule.new
    function = ir.add_function("multiply", [Smalang::IrType::Isize, Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    left = function.parameters[0].value_id
    right = function.parameters[1].value_id
    product = function.emit_multiply(entry, Smalang::IrType::Isize, left, right)
    function.emit_return(entry, product)

    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(%v2 isize (mul %v0 %v1))")
    ir.verify.should be_empty

    unsigned_function = ir.add_function("multiply_unsigned", [Smalang::IrType::Usize, Smalang::IrType::Usize], Smalang::IrType::Usize)
    unsigned_product = unsigned_function.emit_multiply(
      unsigned_function.entry_block_id,
      Smalang::IrType::Usize,
      unsigned_function.parameters[0].value_id,
      unsigned_function.parameters[1].value_id
    )
    unsigned_function.emit_return(unsigned_function.entry_block_id, unsigned_product)
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(%v2 usize (mul %v0 %v1))")
    ir.verify.should be_empty
  end

  it "reports operand type mismatches and uses that are not defined earlier" do
    ir = Smalang::IrModule.new
    function = ir.add_function("broken", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    signed = function.emit_constant(entry, Smalang::IrType::Isize, 1)
    unsigned = function.emit_constant(entry, Smalang::IrType::Usize, 2)
    function.emit_add(entry, Smalang::IrType::Isize, signed, unsigned)
    function.emit_multiply(entry, Smalang::IrType::Isize, signed, unsigned)
    function.emit_multiply(entry, Smalang::IrType::Isize, unsigned, unsigned)
    undefined_sum = function.emit_add(entry, Smalang::IrType::Isize, 99, signed)
    function.emit_return(entry, undefined_sum)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("add operands must have matching types")
    diagnostics.should contain("mul operands must have matching types")
    diagnostics.should contain("mul result has type isize, expected usize")
    diagnostics.should contain("%v99 is not defined")
  end

  it "checks call signatures and function returns" do
    ir = Smalang::IrModule.new
    callee = ir.add_function("callee", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    callee.emit_return(callee.entry_block_id, callee.parameters[0].value_id)

    caller = ir.add_function("caller", [Smalang::IrType::Usize], Smalang::IrType::Isize)
    target = ir.internal_call_target(callee.id).not_nil!
    caller_normal = caller.add_block("normal")
    caller_unwind = caller.add_block("unwind")
    result = caller.emit_invoke_call(caller.entry_block_id, target, [caller.parameters[0].value_id], caller_normal, caller_unwind)
    caller.emit_return(caller_normal, result.value_id)
    caller.emit_resume_exception(caller_unwind, result.exception_id)

    missing_return = ir.add_function("missing_return", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    missing_return.emit_constant(missing_return.entry_block_id, Smalang::IrType::Isize, 1)

    wrong_return = ir.add_function("wrong_return", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    unsigned = wrong_return.emit_constant(wrong_return.entry_block_id, Smalang::IrType::Usize, 1)
    wrong_return.emit_return(wrong_return.entry_block_id, unsigned)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("call argument 0 has type usize, expected isize")
    diagnostics.should contain("function missing_return: block entry must end with a terminator")
    diagnostics.should contain("return has type usize, expected isize")
  end

  it "models throwing calls with explicit normal and exceptional edges" do
    ir = Smalang::IrModule.new
    callee = ir.add_function("callee", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    callee.emit_return(callee.entry_block_id, callee.parameters[0].value_id)

    caller = ir.add_function("caller", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = caller.entry_block_id
    normal = caller.add_block("normal")
    unwind = caller.add_block("unwind")
    target = ir.internal_call_target(callee.id).not_nil!
    result = caller.emit_invoke_call(entry, target, [caller.parameters[0].value_id], normal, unwind)
    caller.emit_return(normal, result.value_id)
    caller.emit_resume_exception(unwind, result.exception_id)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(invoke (call @callee %v0) (normal @normal %v1) (exception @unwind %v2))")
    dump.should contain("(resume %v2)")
    ir.verify.should be_empty
  end

  it "dumps invoke source locations in S-expression form" do
    ir = Smalang::IrModule.new
    callee = ir.add_function("callee", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    zero = callee.emit_constant(callee.entry_block_id, Smalang::IrType::Isize, 0)
    callee.emit_return(callee.entry_block_id, zero)
    caller = ir.add_function("caller", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    normal = caller.add_block("normal")
    unwind = caller.add_block("unwind")
    target = ir.internal_call_target(callee.id).not_nil!
    location = Smalang::IrSourceLocation.new("source.py", 17)
    result = caller.emit_invoke_call(caller.entry_block_id, target, Array(Smalang::ValueId).new, normal, unwind, location)
    caller.emit_return(normal, result.value_id)
    caller.emit_resume_exception(unwind, result.exception_id)

    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(at \"source.py\" 17)")
  end

  it "merges values from predecessor blocks with explicit phi inputs" do
    ir = Smalang::IrModule.new
    function = ir.add_function("choose", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    left = function.add_block("left")
    right = function.add_block("right")
    join = function.add_block("join")
    condition = function.parameters[0].value_id

    function.emit_branch(entry, condition, left, right)
    left_value = function.emit_constant(left, Smalang::IrType::Isize, 11)
    function.emit_jump(left, join)
    right_value = function.emit_constant(right, Smalang::IrType::Isize, 22)
    function.emit_jump(right, join)
    merged = function.emit_phi(join, Smalang::IrType::Isize, [
      Smalang::IrPhiIncoming.new(left, left_value),
      Smalang::IrPhiIncoming.new(right, right_value),
    ])
    function.emit_return(join, merged)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(branch %v0 @left @right)")
    dump.should contain("(%v3 isize (phi [@left %v1] [@right %v2]))")
    ir.verify.should be_empty
  end

  it "allows branch outcomes to share a successor block" do
    ir = Smalang::IrModule.new
    function = ir.add_function("same_successor", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    target = function.add_block("target")
    function.emit_branch(entry, function.parameters.first.value_id, target, target)
    function.emit_return(target, function.parameters.first.value_id)

    ir.verify.should be_empty
  end

  it "represents division failures and catch matching in the exceptional CFG" do
    ir = Smalang::IrModule.new
    function = ir.add_function("divide", [Smalang::IrType::Isize, Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    normal = function.add_block("normal")
    dispatch = function.add_block("dispatch")
    caught = function.add_block("caught")
    resume = function.add_block("resume")
    left = function.parameters[0].value_id
    right = function.parameters[1].value_id

    result = function.emit_invoke_divide(entry, Smalang::IrType::Isize, left, right, normal, dispatch)
    function.emit_return(normal, result.value_id)
    function.emit_exception_dispatch(dispatch, result.exception_id, [
      Smalang::IrExceptionCase.new(Smalang::IrExceptionKind::DivisionByZero, caught),
    ], resume)
    function.emit_exception_release(caught, result.exception_id)
    fallback = function.emit_constant(caught, Smalang::IrType::Isize, 0)
    function.emit_return(caught, fallback)
    function.emit_resume_exception(resume, result.exception_id)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(invoke (div %v0 %v1) (normal @normal %v2) (exception @dispatch %v3))")
    dump.should contain("(exception-switch %v3 (kind DivisionByZero @caught) (default @resume))")
    ir.verify.should be_empty
  end

  it "releases caught exceptions and verifies exception ownership transfers" do
    ir = Smalang::IrModule.new
    function = ir.add_function("divide", [Smalang::IrType::Isize, Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    normal = function.add_block("normal")
    dispatch = function.add_block("dispatch")
    caught = function.add_block("caught")
    resume = function.add_block("resume")

    result = function.emit_invoke_divide(
      entry,
      Smalang::IrType::Isize,
      function.parameters[0].value_id,
      function.parameters[1].value_id,
      normal,
      dispatch
    )
    function.emit_return(normal, result.value_id)
    function.emit_exception_dispatch(dispatch, result.exception_id, [
      Smalang::IrExceptionCase.new(Smalang::IrExceptionKind::DivisionByZero, caught),
    ], resume)
    function.emit_exception_release(caught, result.exception_id)
    fallback = function.emit_constant(caught, Smalang::IrType::Isize, 0)
    function.emit_return(caught, fallback)
    function.emit_resume_exception(resume, result.exception_id)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(exception.release %v3)")
    ir.verify.should be_empty
  end

  it "transfers exception ownership through an exceptional phi edge" do
    ir = Smalang::IrModule.new
    function = ir.add_function("merge_exceptions", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    left = function.add_block("left")
    left_normal = function.add_block("left_normal")
    left_failed = function.add_block("left_failed")
    right = function.add_block("right")
    right_normal = function.add_block("right_normal")
    right_failed = function.add_block("right_failed")
    merge = function.add_block("merge")
    caught = function.add_block("caught")
    function.emit_branch(entry, function.parameters.first.value_id, left, right)

    left_value = function.emit_constant(left, Smalang::IrType::Isize, 10)
    left_zero = function.emit_constant(left, Smalang::IrType::Isize, 0)
    left_division = function.emit_invoke_divide(left, Smalang::IrType::Isize, left_value, left_zero, left_normal, left_failed)
    function.emit_return(left_normal, left_division.value_id)
    function.emit_jump(left_failed, merge)

    right_value = function.emit_constant(right, Smalang::IrType::Isize, 20)
    right_zero = function.emit_constant(right, Smalang::IrType::Isize, 0)
    right_division = function.emit_invoke_divide(right, Smalang::IrType::Isize, right_value, right_zero, right_normal, right_failed)
    function.emit_return(right_normal, right_division.value_id)
    function.emit_jump(right_failed, merge)

    merged_exception = function.emit_phi(merge, Smalang::IrType::Exception, [
      Smalang::IrPhiIncoming.new(left_failed, left_division.exception_id),
      Smalang::IrPhiIncoming.new(right_failed, right_division.exception_id),
    ])
    function.emit_exception_dispatch(merge, merged_exception, [
      Smalang::IrExceptionCase.new(nil, caught),
    ])
    function.emit_exception_release(caught, merged_exception)
    recovered = function.emit_constant(caught, Smalang::IrType::Isize, 0)
    function.emit_return(caught, recovered)

    ir.verify.should be_empty
  end

  it "rejects use of an exception after release" do
    ir = Smalang::IrModule.new
    function = ir.add_function("invalid_release", [Smalang::IrType::Isize, Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    normal = function.add_block("normal")
    caught = function.add_block("caught")

    result = function.emit_invoke_divide(
      entry,
      Smalang::IrType::Isize,
      function.parameters[0].value_id,
      function.parameters[1].value_id,
      normal,
      caught
    )
    function.emit_return(normal, result.value_id)
    function.emit_exception_release(caught, result.exception_id)
    function.emit_resume_exception(caught, result.exception_id)

    ir.verify.join("\n").should contain("exception %v3 is not owned")
  end

  it "rejects an invoke that recreates an exception while its previous value remains owned" do
    ir = Smalang::IrModule.new
    function = ir.add_function("loop_exception", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    entry = function.entry_block_id
    normal = function.add_block("normal")
    value = function.parameters.first.value_id
    result = function.emit_invoke_divide(entry, Smalang::IrType::Isize, value, value, normal, entry)
    function.emit_return(normal, result.value_id)

    ir.verify.join("\n").should contain("exception %v2 is already owned in block entry")
  end
end
