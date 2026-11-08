require "spec"
require "../src/smalang/ir"

describe "unit values in typed IR" do
  it "preserves unit through a constant, function signature, call result, and return" do
    ir = Smalang::IrModule.new
    identity = ir.add_function("identity", [Smalang::IrType::Unit], Smalang::IrType::Unit)
    identity.emit_return(identity.entry_block_id, identity.parameters.first.value_id)

    caller = ir.add_function("caller", Array(Smalang::IrType).new, Smalang::IrType::Unit)
    entry = caller.entry_block_id
    unit = caller.emit_unit_constant(entry)
    normal = caller.add_block("normal")
    unwind = caller.add_block("unwind")
    target = ir.internal_call_target(identity.id).not_nil!
    call = caller.emit_invoke_call(entry, target, [unit], normal, unwind)
    caller.emit_return(normal, call.value_id)
    caller.emit_resume_exception(unwind, call.exception_id)

    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.should contain("(func @identity (param %v0 unit) (result unit)")
    dump.should contain("(%v0 unit (unit))")
    dump.should contain("(invoke (call @identity %v0) (normal @normal %v1) (exception @unwind %v2))")
    ir.verify.should be_empty
  end

  it "merges unit values through phi nodes" do
    ir = Smalang::IrModule.new
    function = ir.add_function("choose", [Smalang::IrType::Bool], Smalang::IrType::Unit)
    entry = function.entry_block_id
    left = function.add_block("left")
    right = function.add_block("right")
    join = function.add_block("join")
    function.emit_branch(entry, function.parameters.first.value_id, left, right)
    left_value = function.emit_unit_constant(left)
    function.emit_jump(left, join)
    right_value = function.emit_unit_constant(right)
    function.emit_jump(right, join)
    merged = function.emit_phi(join, Smalang::IrType::Unit, [
      Smalang::IrPhiIncoming.new(left, left_value),
      Smalang::IrPhiIncoming.new(right, right_value),
    ])
    function.emit_return(join, merged)

    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(%v3 unit (phi [@left %v1] [@right %v2]))")
    ir.verify.should be_empty
  end

  it "rejects integer constants typed as unit" do
    ir = Smalang::IrModule.new
    function = ir.add_function("invalid", Array(Smalang::IrType).new, Smalang::IrType::Unit)
    invalid = function.emit_constant(function.entry_block_id, Smalang::IrType::Unit, 0)
    function.emit_return(function.entry_block_id, invalid)

    ir.verify.join("\n").should contain("const result must have an integer type, got unit")
  end

  it "rejects returning a boolean value from a unit function" do
    ir = Smalang::IrModule.new
    function = ir.add_function("invalid", Array(Smalang::IrType).new, Smalang::IrType::Unit)
    boolean = function.emit_constant(function.entry_block_id, Smalang::IrType::Bool, 0)
    function.emit_return(function.entry_block_id, boolean)

    ir.verify.join("\n").should contain("return has type bool, expected unit")
  end
end
