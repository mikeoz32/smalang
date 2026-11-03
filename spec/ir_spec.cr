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
