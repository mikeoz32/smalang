require "spec"
require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"
require "./backend_spec_helpers"

describe Smalang::X86_64Backend do
  it "emits a linkable object for typed IR with an internal call" do
    ir = Smalang::IrModule.new
    increment = ir.add_function(
      "increment",
      [Smalang::IrType::Isize],
      Smalang::IrType::Isize
    )
    increment_entry = increment.entry_block_id
    value = increment.parameters[0].value_id
    one = increment.emit_constant(increment_entry, Smalang::IrType::Isize, 1)
    sum = increment.emit_add(increment_entry, Smalang::IrType::Isize, value, one)
    increment.emit_return(increment_entry, sum)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    main_entry = main.entry_block_id
    argument = main.emit_constant(main_entry, Smalang::IrType::Isize, 41)
    target = ir.internal_call_target(increment.id).not_nil!
    result = main.emit_call(main_entry, target, [argument], Smalang::IrType::Isize)
    main.emit_return(main_entry, result)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "emits 64-bit subtraction" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    fifty = function.emit_constant(entry, Smalang::IrType::Isize, 50)
    eight = function.emit_constant(entry, Smalang::IrType::Isize, 8)
    difference = function.emit_subtract(entry, Smalang::IrType::Isize, fifty, eight)
    function.emit_return(entry, difference)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "emits 64-bit multiplication" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    six = function.emit_constant(entry, Smalang::IrType::Isize, 6)
    seven = function.emit_constant(entry, Smalang::IrType::Isize, 7)
    product = function.emit_multiply(entry, Smalang::IrType::Isize, six, seven)
    function.emit_return(entry, product)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "preserves the full 64-bit multiplication result" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    left = function.emit_constant(entry, Smalang::IrType::Isize, 4_294_967_297_i64)
    right = function.emit_constant(entry, Smalang::IrType::Isize, 4_294_967_297_i64)
    product = function.emit_multiply(entry, Smalang::IrType::Isize, left, right)
    function.emit_return(entry, product)

    BackendSpecHelpers.link_and_compare_full_width_result(ir, 8_589_934_593_u64).should eq(0)
  end

  it "multiplies a value spilled under register pressure" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    values = (1..10).map do |value|
      function.emit_constant(entry, Smalang::IrType::Isize, value)
    end
    product = function.emit_multiply(entry, Smalang::IrType::Isize, values.first, values.last)
    result = values.reduce(product) do |sum, value|
      function.emit_add(entry, Smalang::IrType::Isize, sum, value)
    end
    function.emit_return(entry, result)

    BackendSpecHelpers.link_and_run(ir).should eq(65)
  end

  it "preserves signed 64-bit constants" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    negative = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, -42)
    function.emit_return(function.entry_block_id, negative)

    BackendSpecHelpers.link_and_run(ir).should eq(214)
  end

  it "preserves values that remain live across a call" do
    ir = Smalang::IrModule.new
    increment = ir.add_function("increment", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    increment_entry = increment.entry_block_id
    one = increment.emit_constant(increment_entry, Smalang::IrType::Isize, 1)
    incremented = increment.emit_add(increment_entry, Smalang::IrType::Isize, increment.parameters[0].value_id, one)
    increment.emit_return(increment_entry, incremented)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    live_value = main.emit_constant(entry, Smalang::IrType::Isize, 40)
    argument = main.emit_constant(entry, Smalang::IrType::Isize, 1)
    target = ir.internal_call_target(increment.id).not_nil!
    call_result = main.emit_call(entry, target, [argument], Smalang::IrType::Isize)
    result = main.emit_add(entry, Smalang::IrType::Isize, live_value, call_result)
    main.emit_return(entry, result)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "spills values when register pressure exceeds the available registers" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    values = (1..12).map do |value|
      function.emit_constant(entry, Smalang::IrType::Isize, value)
    end
    result = values.first
    values.each_with_index do |value, index|
      next if index == 0
      result = function.emit_add(entry, Smalang::IrType::Isize, result, value)
    end
    function.emit_return(entry, result)

    BackendSpecHelpers.link_and_run(ir).should eq(78)
  end

  it "passes integer arguments beyond the six ABI registers on the stack" do
    ir = Smalang::IrModule.new
    parameter_types = Array.new(7, Smalang::IrType::Isize)
    sum_function = ir.add_function("sum_seven", parameter_types, Smalang::IrType::Isize)
    sum_entry = sum_function.entry_block_id
    parameters = sum_function.parameters
    result = parameters.first.value_id
    parameters.each_with_index do |parameter, index|
      next if index == 0
      result = sum_function.emit_add(sum_entry, Smalang::IrType::Isize, result, parameter.value_id)
    end
    sum_function.emit_return(sum_entry, result)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    main_entry = main.entry_block_id
    arguments = (1..7).map do |value|
      main.emit_constant(main_entry, Smalang::IrType::Isize, value)
    end
    target = ir.internal_call_target(sum_function.id).not_nil!
    sum = main.emit_call(main_entry, target, arguments, Smalang::IrType::Isize)
    main.emit_return(main_entry, sum)

    BackendSpecHelpers.link_and_run(ir).should eq(28)
  end

  it "rejects invalid IR before emitting an object" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    unsigned = function.emit_constant(function.entry_block_id, Smalang::IrType::Usize, 1)
    function.emit_return(function.entry_block_id, unsigned)

    expect_raises(Smalang::X86_64BackendFailure, /cannot emit invalid IR/) do
      Smalang::X86_64Backend.new.emit(ir)
    end
  end

  it "rejects constants outside the target integer width" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Usize)
    negative = function.emit_constant(function.entry_block_id, Smalang::IrType::Usize, -1)
    function.emit_return(function.entry_block_id, negative)

    expect_raises(Smalang::X86_64BackendFailure, /does not fit usize on x86_64/) do
      Smalang::X86_64Backend.new.emit(ir)
    end
  end
end
