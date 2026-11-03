require "spec"
require "../src/smalang/ir"

describe Smalang::IrModule do
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
    result = main.emit_call(entry, target, [difference], Smalang::IrType::Isize)
    main.emit_return(entry, result)
    ir.internal_call_target(-1).should be_nil

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(func @increment (param %v0 isize) (result isize)")
    dump.should contain("(%v2 isize (add %v0 %v1))")
    dump.should contain("(%v1 isize (sub %v0 %v0))")
    dump.should contain("(%v2 isize (call @increment %v1))")
    dump.should contain("(return %v2)")
    ir.verify.should be_empty
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
    diagnostics.should contain("%v99 is not defined before use")
  end

  it "checks call signatures and function returns" do
    ir = Smalang::IrModule.new
    callee = ir.add_function("callee", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    callee.emit_return(callee.entry_block_id, callee.parameters[0].value_id)

    caller = ir.add_function("caller", [Smalang::IrType::Usize], Smalang::IrType::Isize)
    target = ir.internal_call_target(callee.id).not_nil!
    result = caller.emit_call(caller.entry_block_id, target, [caller.parameters[0].value_id], Smalang::IrType::Isize)
    caller.emit_return(caller.entry_block_id, result)

    missing_return = ir.add_function("missing_return", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    missing_return.emit_constant(missing_return.entry_block_id, Smalang::IrType::Isize, 1)

    wrong_return = ir.add_function("wrong_return", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    unsigned = wrong_return.emit_constant(wrong_return.entry_block_id, Smalang::IrType::Usize, 1)
    wrong_return.emit_return(wrong_return.entry_block_id, unsigned)

    diagnostics = ir.verify.join("\n")
    diagnostics.should contain("call argument 0 has type usize, expected isize")
    diagnostics.should contain("function missing_return: must end with return")
    diagnostics.should contain("return has type usize, expected isize")
  end
end
