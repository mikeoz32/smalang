require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"
require "../src/smalang/semantic"
require "../src/smalang/ir"
require "../src/smalang/ir_lowering"
require "./backend_spec_helpers"

module IrLoweringSpecHelpers
  def self.lower(source : String)
    tokens = Smalang::Lexer.new.tokenize(source, "ir_lowering_spec.py")
    parse_result = Smalang::Parser.new(tokens).parse
    parse_result.success?.should eq(true)

    semantic_result = Smalang::SemanticAnalyzer.new(parse_result.parsed_module).analyze
    semantic_result.success?.should eq(true)

    semantic_module = semantic_result.semantic_module.not_nil!
    parsed_module = semantic_module.parsed_module
    node_count = parsed_module.arena.size
    result = Smalang::IrLowerer.new(semantic_module).lower
    parsed_module.arena.size.should eq(node_count)
    result
  end

  def self.instructions(function : Smalang::IrFunction) : Array(Smalang::IrInstruction)
    instructions = [] of Smalang::IrInstruction
    function.each_block do |block|
      block.instruction_ids.each do |instruction_id|
        instructions << function.instruction(instruction_id).not_nil!
      end
    end
    instructions
  end
end

describe Smalang::IrLowerer do
  it "lowers and runs a scalar pointer allocation, store, load, and free" do
    source = "def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(42)\n        store(address, 17)\n        result: int = load(address)\n        free(address)\n    return result\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(17)
  end

  it "passes allocated pointers through function parameters and results" do
    source = "def allocate(value: int) -> ptr[int]:\n    unsafe:\n        address: ptr[int] = alloc(value)\n    return address\n\ndef read_and_free(address: ptr[int]) -> int:\n    unsafe:\n        result: int = load(address)\n        free(address)\n    return result\n\ndef main() -> int:\n    address: ptr[int] = allocate(42)\n    return read_and_free(address)\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "compiles bool and fixed-width scalar pointers to native behavior" do
    source = File.read("#{__DIR__}/../examples/unsafe_pointers.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "compiles and runs pointer alias and function API examples" do
    examples = [
      {"unsafe_pointer_alias.py", 42},
      {"unsafe_pointer_functions.py", 42},
    ]

    examples.each do |filename, expected_result|
      source = File.read("#{__DIR__}/../examples/#{filename}")
      result = IrLoweringSpecHelpers.lower(source)

      result.success?.should eq(true)
      ir = result.ir_module.not_nil!
      ir.verify.should be_empty
      BackendSpecHelpers.link_and_run(ir).should eq(expected_result)
    end
  end

  it "reports OutOfMemory when the process cannot map another allocation" do
    source = String.build do |program|
      program << "def main() -> int:\n    unsafe:\n"
      4096.times do |index|
        program << "        address_#{index}: ptr[int] = alloc(1)\n"
      end
      program << "    return 0\n"
    end
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    runtime = BackendSpecHelpers.link_and_capture(result.ir_module.not_nil!, 12 * 1024)
    runtime[:exit_code].should eq(1)
    runtime[:stderr].should contain("Uncaught exception: OutOfMemory")
    runtime[:stderr].should contain("at main (ir_lowering_spec.py:")
  end

  it "lowers the checked-in program to a verified executable returning 42" do
    source = File.read("#{__DIR__}/../examples/first_program.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "lowers bool literals, signatures, parameters, and nested calls" do
    source = "def identity(value: bool) -> bool:\n    return value\n\ndef true_value() -> bool:\n    return True\n\ndef false_value() -> bool:\n    return False\n\ndef forward() -> bool:\n    return identity(true_value())\n\ndef accept(value: bool) -> int:\n    return 42\n\ndef main() -> int:\n    return accept(forward())\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    identity = ir.function(0).not_nil!
    true_value = ir.function(1).not_nil!
    false_value = ir.function(2).not_nil!
    forward = ir.function(3).not_nil!
    identity.signature.parameter_types.should eq([Smalang::IrType::Bool])
    identity.signature.result_type.should eq(Smalang::IrType::Bool)
    true_value.signature.result_type.should eq(Smalang::IrType::Bool)
    literal = IrLoweringSpecHelpers.instructions(true_value).find! { |instruction| instruction.is_a?(Smalang::IrConstantInstruction) }
    literal.as(Smalang::IrConstantInstruction).value.should eq(1)
    false_literal = IrLoweringSpecHelpers.instructions(false_value).find! { |instruction| instruction.is_a?(Smalang::IrConstantInstruction) }
    false_literal.as(Smalang::IrConstantInstruction).value.should eq(0)
    forward.signature.result_type.should eq(Smalang::IrType::Bool)
    forward_calls = IrLoweringSpecHelpers.instructions(forward).select { |instruction| instruction.is_a?(Smalang::IrInvokeInstruction) }
    forward_calls.size.should eq(2)
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "lowers immutable and mutable bindings to the current SSA values" do
    source = File.read("#{__DIR__}/../examples/const_mut_bindings.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(20)
  end

  it "preserves unsigned parameter and expression types" do
    source = "def add(left: uint, right: uint) -> uint:\n    return left + right\n\ndef main() -> int:\n    return 0\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    function = result.ir_module.not_nil!.function(0).not_nil!
    function.signature.parameter_types.should eq([Smalang::IrType::Usize, Smalang::IrType::Usize])
    function.signature.result_type.should eq(Smalang::IrType::Usize)

    add = IrLoweringSpecHelpers.instructions(function).find! { |instruction| instruction.is_a?(Smalang::IrAddInstruction) }
    add.result_type.should eq(Smalang::IrType::Usize)
    parameters = function.parameters
    add.as(Smalang::IrAddInstruction).left.should eq(parameters[0].value_id)
    add.as(Smalang::IrAddInstruction).right.should eq(parameters[1].value_id)
  end

  it "lowers fixed-width integer result types into distinct IR types" do
    integer_types = ["int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"]
    source = String.build do |program|
      integer_types.each do |type|
        program << "def value_#{type}() -> #{type}:\n    return 0\n\n"
      end
      program << "def main() -> int:\n    return 0\n"
    end

    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    integer_types.each_with_index do |type, index|
      function = ir.function(index).not_nil!
      function.signature.result_type.label.should eq(type)
    end
    ir.verify.should be_empty
  end

  it "compiles and runs nested calls that pass an int8 result" do
    source = "def increment(value: int8) -> int8:\n    return value + 1\n\ndef consume(value: int8) -> int:\n    return 42\n\ndef main() -> int:\n    return consume(increment(127))\n"

    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "lowers forward and mutually recursive calls to their module function IDs" do
    source = "def is_even(value: int) -> int:\n    return is_odd(value)\n\ndef is_odd(value: int) -> int:\n    return is_even(value)\n\ndef main() -> int:\n    return is_even(0)\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    even = ir.function(0).not_nil!
    odd = ir.function(1).not_nil!
    main = ir.function(2).not_nil!

    even_call = IrLoweringSpecHelpers.instructions(even).find! { |instruction| instruction.is_a?(Smalang::IrInvokeInstruction) }.as(Smalang::IrInvokeInstruction)
    odd_call = IrLoweringSpecHelpers.instructions(odd).find! { |instruction| instruction.is_a?(Smalang::IrInvokeInstruction) }.as(Smalang::IrInvokeInstruction)
    main_call = IrLoweringSpecHelpers.instructions(main).find! { |instruction| instruction.is_a?(Smalang::IrInvokeInstruction) }.as(Smalang::IrInvokeInstruction)

    even_call.operation.as(Smalang::IrCallOperation).target.module_function_id.should eq(odd.id)
    odd_call.operation.as(Smalang::IrCallOperation).target.module_function_id.should eq(even.id)
    main_call.operation.as(Smalang::IrCallOperation).target.module_function_id.should eq(even.id)
    main_call.source_location.should eq(Smalang::IrSourceLocation.new("ir_lowering_spec.py", 8))
    ir.verify.should be_empty
  end
end
