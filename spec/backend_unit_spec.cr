require "spec"
require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"
require "./backend_spec_helpers"

describe "unit values in x86-64 code generation" do
  it "omits unit arguments when laying out mixed internal calls" do
    ir = Smalang::IrModule.new
    unit_identity = ir.add_function("unit_identity", [Smalang::IrType::Unit], Smalang::IrType::Unit)
    unit_identity.emit_return(unit_identity.entry_block_id, unit_identity.parameters.first.value_id)

    mixed_parameter_types = [
      Smalang::IrType::Unit,
      Smalang::IrType::Isize,
      Smalang::IrType::Unit,
      Smalang::IrType::Isize,
      Smalang::IrType::Isize,
      Smalang::IrType::Isize,
      Smalang::IrType::Isize,
      Smalang::IrType::Isize,
      Smalang::IrType::Isize,
    ]
    mixed = ir.add_function("mixed", mixed_parameter_types, Smalang::IrType::Isize)
    mixed.emit_return(mixed.entry_block_id, mixed.parameters.last.value_id)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    unit = main.emit_unit_constant(entry)
    unit_identity_target = ir.internal_call_target(unit_identity.id).not_nil!
    identity_normal = main.add_block("identity_normal")
    identity_unwind = main.add_block("identity_unwind")
    identity_call = main.emit_invoke_call(entry, unit_identity_target, [unit], identity_normal, identity_unwind)

    arguments = [
      unit,
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 1),
      unit,
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 2),
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 3),
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 4),
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 5),
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 6),
      main.emit_constant(identity_normal, Smalang::IrType::Isize, 42),
    ]
    mixed_target = ir.internal_call_target(mixed.id).not_nil!
    mixed_normal = main.add_block("mixed_normal")
    mixed_unwind = main.add_block("mixed_unwind")
    mixed_call = main.emit_invoke_call(identity_normal, mixed_target, arguments, mixed_normal, mixed_unwind)
    main.emit_return(mixed_normal, mixed_call.value_id)
    main.emit_resume_exception(identity_unwind, identity_call.exception_id)
    main.emit_resume_exception(mixed_unwind, mixed_call.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "lowers unit phi values without machine locations" do
    ir = Smalang::IrModule.new
    choose = ir.add_function("choose", [Smalang::IrType::Bool], Smalang::IrType::Unit)
    entry = choose.entry_block_id
    left = choose.add_block("left")
    right = choose.add_block("right")
    join = choose.add_block("join")
    choose.emit_branch(entry, choose.parameters.first.value_id, left, right)
    left_value = choose.emit_unit_constant(left)
    choose.emit_jump(left, join)
    right_value = choose.emit_unit_constant(right)
    choose.emit_jump(right, join)
    merged = choose.emit_phi(join, Smalang::IrType::Unit, [
      Smalang::IrPhiIncoming.new(left, left_value),
      Smalang::IrPhiIncoming.new(right, right_value),
    ])
    choose.emit_return(join, merged)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    false_value = main.emit_constant(entry, Smalang::IrType::Bool, 0)
    normal = main.add_block("normal")
    unwind = main.add_block("unwind")
    result = main.emit_invoke_call(entry, ir.internal_call_target(choose.id).not_nil!, [false_value], normal, unwind)
    answer = main.emit_constant(normal, Smalang::IrType::Isize, 42)
    main.emit_return(normal, answer)
    main.emit_resume_exception(unwind, result.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "propagates an exception through a unit-returning function" do
    ir = Smalang::IrModule.new
    failure = ir.add_function("failure", Array(Smalang::IrType).new, Smalang::IrType::Unit)
    entry = failure.entry_block_id
    normal = failure.add_block("normal")
    unwind = failure.add_block("unwind")
    dividend = failure.emit_constant(entry, Smalang::IrType::Isize, 1)
    zero = failure.emit_constant(entry, Smalang::IrType::Isize, 0)
    division = failure.emit_invoke_divide(entry, Smalang::IrType::Isize, dividend, zero, normal, unwind)
    unit = failure.emit_unit_constant(normal)
    failure.emit_return(normal, unit)
    failure.emit_resume_exception(unwind, division.exception_id)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    call_normal = main.add_block("call_normal")
    dispatch = main.add_block("dispatch")
    caught = main.add_block("caught")
    rethrow = main.add_block("rethrow")
    call = main.emit_invoke_call(entry, ir.internal_call_target(failure.id).not_nil!, Array(Smalang::ValueId).new, call_normal, dispatch)
    unexpected = main.emit_constant(call_normal, Smalang::IrType::Isize, 1)
    main.emit_return(call_normal, unexpected)
    main.emit_exception_dispatch(dispatch, call.exception_id, [
      Smalang::IrExceptionCase.new(Smalang::IrExceptionKind::DivisionByZero, caught),
    ], rethrow)
    main.emit_exception_release(caught, call.exception_id)
    recovered = main.emit_constant(caught, Smalang::IrType::Isize, 42)
    main.emit_return(caught, recovered)
    main.emit_resume_exception(rethrow, call.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "rejects a unit-returning entrypoint because startup needs an exit status" do
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Unit)
    unit = main.emit_unit_constant(main.entry_block_id)
    main.emit_return(main.entry_block_id, unit)

    expect_raises(Smalang::X86_64BackendFailure, /main cannot return unit/) do
      Smalang::X86_64Backend.new.emit(ir)
    end
  end
end
