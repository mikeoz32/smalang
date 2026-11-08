require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"
require "../src/smalang/semantic"
require "../src/smalang/ir"
require "../src/smalang/ir_lowering"
require "./backend_spec_helpers"

module ArraySpecHelpers
  def self.lower_successfully(source : String) : Smalang::IrModule
    tokens = Smalang::Lexer.new.tokenize(source, "local_array.py")
    parsed = Smalang::Parser.new(tokens).parse
    parsed.success?.should eq(true)
    semantic = Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
    semantic.success?.should eq(true)
    lowered = Smalang::IrLowerer.new(semantic.semantic_module.not_nil!).lower
    lowered.success?.should eq(true)
    lowered.ir_module.not_nil!
  end

  def self.semantic_result(source : String) : Smalang::SemanticResult
    tokens = Smalang::Lexer.new.tokenize(source, "local_array.py")
    parsed = Smalang::Parser.new(tokens).parse
    parsed.success?.should eq(true)
    Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
  end

  def self.array_read_ir(type : Smalang::IrType, value : Int128) : Smalang::IrModule
    ir = Smalang::IrModule.new
    array_type = Smalang::IrArrayType.new(type, 1_u128)
    function = ir.add_function("main", Array(Smalang::IrType).new, type)
    entry = function.entry_block_id
    element = function.emit_constant(entry, type, value)
    array = function.emit_array_literal(entry, array_type, [element])
    index = function.emit_constant(entry, Smalang::IrType::Usize, 0)
    normal = function.add_block("normal")
    unwind = function.add_block("unwind")
    result = function.emit_invoke_array_get(entry, array, index, array_type, normal, unwind)
    function.emit_return(normal, result.value_id)
    function.emit_resume_exception(unwind, result.exception_id)
    ir
  end
end

describe "Smalang local arrays" do
  it "compiles and runs the fixed array example" do
    source = File.read(File.expand_path("../examples/fixed_arrays.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(56)
  end

  it "initializes a fixed array and reads an element" do
    source = "def main() -> int:\n    values: array[int, 3] = [10, 20, 30]\n    return values[1]\n"
    tokens = Smalang::Lexer.new.tokenize(source, "local_array_read.py")
    parsed = Smalang::Parser.new(tokens).parse

    parsed.success?.should eq(true)
    semantic = Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
    semantic.success?.should eq(true)
    lowered = Smalang::IrLowerer.new(semantic.semantic_module.not_nil!).lower

    lowered.success?.should eq(true)
    BackendSpecHelpers.link_and_run(lowered.ir_module.not_nil!).should eq(20)
  end

  it "updates an indexed element only through a mutable binding" do
    source = "def main() -> int:\n    values: mut[array[int, 3]] = [10, 20, 30]\n    values[1] = 42\n    return values[1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "keeps array copies independent after indexed mutation" do
    source = "def main() -> int:\n    values: mut[array[int, 2]] = [10, 20]\n    copy: mut[array[int, 2]] = values\n    copy[0] = 42\n    return values[0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(10)
  end

  it "copies nested arrays through indexed mutation" do
    source = "def main() -> int:\n    matrix: mut[array[array[int, 2], 2]] = [[1, 2], [3, 4]]\n    matrix[0][1] = 42\n    return matrix[0][1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "copies array parameters and return values" do
    source = "def update(values: mut[array[int, 2]]) -> array[int, 2]:\n    values[0] = 42\n    return values\n\ndef main() -> int:\n    original: array[int, 2] = [10, 20]\n    changed: array[int, 2] = update(original)\n    return changed[0] + original[0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(52)
  end

  it "passes array values through the stack argument area after an array result pointer" do
    source = "def pass(a: int, b: int, c: int, d: int, e: int, values: array[int, 2]) -> array[int, 2]:\n    return values\n\ndef main() -> int:\n    original: array[int, 2] = [10, 20]\n    copied: array[int, 2] = pass(0, 0, 0, 0, 0, original)\n    return copied[1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(20)
  end

  it "supports empty fixed arrays" do
    source = "def main() -> int:\n    values: array[int, 0] = []\n    return 42\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "folds literal arithmetic in array initializers at compile time" do
    source = "def main() -> int:\n    values: array[int8, 2] = [127 + 1, 0]\n    return 42\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    dump = Smalang::IrSExpressionDumper.new.dump(lowered)

    dump.should contain("(const -128)")
    dump.should_not contain("(add ")
    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "loads bool and narrow signed array elements with their declared widths" do
    source = "def accept(value: int8) -> int:\n    return 42\n\ndef choose(flag: bool) -> int:\n    return match flag:\n        case True: 42\n        case False: 0\n\ndef main() -> int:\n    signed_values: array[int8, 1] = [0 - 1]\n    flags: array[bool, 1] = [True]\n    return accept(signed_values[0]) + choose(flags[0])\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(84)
  end

  it "loads every fixed-width integer element with its declared sign and width" do
    cases = [
      {Smalang::IrType::Int8, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt8, 255_i128, 255_u64},
      {Smalang::IrType::Int16, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt16, 65_535_i128, 65_535_u64},
      {Smalang::IrType::Int32, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt32, 4_294_967_295_i128, 4_294_967_295_u64},
      {Smalang::IrType::Int64, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt64, UInt64::MAX.to_i128, UInt64::MAX},
    ]

    cases.each do |type, value, expected|
      ir = ArraySpecHelpers.array_read_ir(type, value)
      BackendSpecHelpers.link_and_compare_full_width_result(ir, expected).should eq(0)
    end
  end

  it "rejects statically known out-of-bounds indices during compilation" do
    source = "def main() -> int:\n    values: array[int, 2] = [10, 20]\n    return values[2]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("out of bounds for length 2")
  end

  it "requires array literals to contain exactly their declared length" do
    source = "def main() -> int:\n    values: array[int, 2] = [10]\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should eq("array literal has 1 elements, expected 2")
  end

  it "requires uint indices" do
    source = "def read(index: int) -> int:\n    values: array[int, 2] = [10, 20]\n    return values[index]\n\ndef main() -> int:\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should eq("array index must have type uint, got int")
  end

  it "requires mutable bindings for indexed assignment" do
    source = "def main() -> int:\n    values: array[int, 2] = [10, 20]\n    values[0] = 42\n    return values[0]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("cannot modify elements of immutable binding 'values'")
  end

  it "rejects runtime expressions inside fixed array literals" do
    source = "def value() -> int:\n    return 10\n\ndef main() -> int:\n    values: array[int, 1] = [value()]\n    return values[0]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should eq("array literal elements must be compile-time constants")
  end

  it "rejects array lengths that exceed x86_64 stack and index limits" do
    source = "def read(values: array[int, 2147483648], index: uint) -> int:\n    return values[index]\n\ndef main() -> int:\n    return 0\n"
    semantic = ArraySpecHelpers.semantic_result(source)
    semantic.success?.should be_true
    lowered = Smalang::IrLowerer.new(semantic.semantic_module.not_nil!).lower

    lowered.success?.should be_false
    lowered.diagnostic.not_nil!.description.should contain("array type exceeds x86_64 stack frame or index limits")
  end

  it "reports a dynamic out-of-bounds index as a runtime exception" do
    source = "def get(index: uint) -> int:\n    values: array[int, 2] = [10, 20]\n    return values[index]\n\ndef main() -> int:\n    return get(2)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("local_array.py:3")
  end

  it "checks dynamic indexed assignments before storing" do
    source = "def set_value(index: uint) -> int:\n    values: mut[array[int, 2]] = [10, 20]\n    values[index] = 42\n    return values[0]\n\ndef main() -> int:\n    return set_value(2)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("local_array.py:3")
  end
end
