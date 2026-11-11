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
  it "allocates initialized scalar storage in the stack frame" do
    source = File.read("#{__DIR__}/../examples/unsafe_stack_allocation.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(stack.alloc")
    BackendSpecHelpers.link_and_run(ir).should eq(72)
  end

  it "runs stack allocation round trips for every supported scalar type" do
    source = File.read("#{__DIR__}/../examples/unsafe_stack_allocation_scalars.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    dump = Smalang::IrSExpressionDumper.new.dump(ir)
    dump.lines.count(&.includes?("(stack.alloc")).should eq(11)
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "uses aligned uninitialized byte storage in the stack frame" do
    source = File.read("#{__DIR__}/../examples/unsafe_stack_storage.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(stack.storage 8 64)")
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "keeps separate stack storage regions independent" do
    source = "def main() -> int:\n    unsafe:\n        first_storage: ptr[uint8] = stack_storage(8, 8)\n        second_storage: ptr[uint8] = stack_storage(8, 8)\n        first: ptr[int] = cast[int](first_storage)\n        second: ptr[int] = cast[int](second_storage)\n        store(first, 11)\n        store(second, 22)\n        store(first, 42)\n        result: int = load(second)\n    return result\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(22)
  end

  it "keeps address-taken scalar bindings coherent across pointers and calls" do
    source = "def mutate(address: ptr[int]) -> int:\n    unsafe:\n        store(address, 73)\n        value: int = load(address)\n    return value\n\ndef update_parameter(value: int) -> int:\n    unsafe:\n        address: ptr[int] = address_of(value)\n        store(address, value + 1)\n        updated: int = value\n    return updated\n\ndef main() -> int:\n    value: mut[int] = 40\n    unsafe:\n        address: ptr[int] = address_of(value)\n        store(address, 41)\n        after_pointer_write: int = value\n        value = 42\n        after_binding_write: int = load(address)\n        updated: int = mutate(address)\n        parameter_value: int = update_parameter(value)\n        result: int = after_pointer_write + after_binding_write + parameter_value\n    return result\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(157)
  end

  it "uses scalar and pointer type layouts in executable memory operations" do
    source = File.read("#{__DIR__}/../examples/unsafe_type_layout_address.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(stack.storage 8 8)")
    BackendSpecHelpers.link_and_run(ir).should eq(230)
  end

  it "uses the declared memory width for stack-allocated scalar values" do
    source = "def main() -> int:\n    unsafe:\n        flag_address: ptr[bool] = alloc_stack(True)\n        byte_address: ptr[int8] = alloc_stack(42)\n        store(flag_address, False)\n        flag: bool = load(flag_address)\n        value: int8 = load(byte_address)\n    return match flag:\n        case True: 0\n        case False: 42\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "evaluates a stack allocation initializer once" do
    source = "def increment(address: ptr[int]) -> int:\n    unsafe:\n        value: int = load(address) + 1\n        store(address, value)\n    return value\n\ndef main() -> int:\n    unsafe:\n        counter: ptr[int] = alloc_stack(40)\n        copy: ptr[int] = alloc_stack(increment(counter))\n        counter_value: int = load(counter)\n        copy_value: int = load(copy)\n    return counter_value + copy_value\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(82)
  end

  it "computes typed pointer offsets and passes a one-past address without dereferencing it" do
    source = File.read("#{__DIR__}/../examples/unsafe_pointer_offsets.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "casts a pointer without changing the address" do
    source = File.read("#{__DIR__}/../examples/unsafe_pointer_cast.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    Smalang::IrSExpressionDumper.new.dump(ir).should contain("(ptr.cast")
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "compiles and executes every scalar pointer cast pair" do
    scalar_types = ["int", "uint", "bool", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"]
    source = String.build do |program|
      program << "def main() -> int:\n    unsafe:\n        storage: ptr[int] = alloc_stack(0)\n"
      scalar_types.each_with_index do |source_type, source_index|
        source_name = "source_#{source_index}"
        program << "        #{source_name}: ptr[#{source_type}] = cast[#{source_type}](storage)\n"
        scalar_types.each_with_index do |target_type, target_index|
          target_name = "target_#{source_index}_#{target_index}"
          value = target_type == "bool" ? "True" : "1"
          program << "        #{target_name}: ptr[#{target_type}] = cast[#{target_type}](#{source_name})\n"
          program << "        store(#{target_name}, #{value})\n"
        end
      end
      program << "        result: int = load(storage)\n    return result\n"
    end
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    function = ir.function(0).not_nil!
    IrLoweringSpecHelpers.instructions(function).count { |instruction| instruction.is_a?(Smalang::IrPointerCastInstruction) }.should eq(132)
    BackendSpecHelpers.link_and_run(ir).should eq(1)
  end

  it "evaluates a pointer cast address operand once" do
    source = "def mark_address(counter: ptr[int], target: ptr[int]) -> ptr[int]:\n    unsafe:\n        current: int = load(counter)\n        store(counter, current + 1)\n    return target\n\ndef main() -> int:\n    unsafe:\n        counter: ptr[int] = alloc_stack(0)\n        target: ptr[int] = alloc_stack(42)\n        converted: ptr[uint] = cast[uint](mark_address(counter, target))\n        store(converted, 7)\n        result: int = load(target) + load(counter)\n    return result\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(8)
  end

  it "allows casting a misaligned address without dereferencing it" do
    source = "def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(0)\n        bytes: ptr[uint8] = cast[uint8](address)\n        shifted: ptr[uint8] = offset(bytes, 1)\n        misaligned: ptr[int] = cast[int](shifted)\n    return 42\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "indexes a local array named cast" do
    source = "def main() -> int:\n    cast: array[int, 1] = [42]\n    return cast[0]\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "evaluates pointer offset arguments once in source order" do
    source = "def mark_address(counter: ptr[uint], target: ptr[int]) -> ptr[int]:\n    unsafe:\n        current: uint = load(counter)\n        store(counter, current + 1)\n    return target\n\ndef mark_index(counter: ptr[uint]) -> uint:\n    unsafe:\n        current: uint = load(counter)\n        store(counter, current + 1)\n    return current\n\ndef main() -> int:\n    unsafe:\n        counter: ptr[uint] = alloc_stack(0)\n        first: ptr[int] = alloc_stack(41)\n        second: ptr[int] = alloc_stack(42)\n        third: ptr[int] = alloc_stack(43)\n        shifted: ptr[int] = offset(mark_address(counter, third), mark_index(counter))\n        value: int = load(shifted)\n    return value\n"
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

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
