require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"
require "../src/smalang/semantic"
require "../src/smalang/ir"
require "../src/smalang/ir_lowering"
require "./backend_spec_helpers"

module ArraySpecHelpers
  def self.lower_successfully(source : String, source_name : String = "local_array.py") : Smalang::IrModule
    tokens = Smalang::Lexer.new.tokenize(source, source_name)
    parsed = Smalang::Parser.new(tokens).parse
    parsed.success?.should eq(true)
    source_node_count = parsed.parsed_module.arena.size
    source_type_count = parsed.parsed_module.type_arena.size
    semantic = Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
    semantic.success?.should eq(true)
    lowered = Smalang::IrLowerer.new(semantic.semantic_module.not_nil!).lower
    parsed.parsed_module.arena.size.should eq(source_node_count)
    parsed.parsed_module.type_arena.size.should eq(source_type_count)
    lowered.success?.should eq(true)
    lowered.ir_module.not_nil!
  end

  def self.semantic_result(source : String) : Smalang::SemanticResult
    tokens = Smalang::Lexer.new.tokenize(source, "local_array.py")
    parsed = Smalang::Parser.new(tokens).parse
    parsed.success?.should eq(true)
    Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
  end
end

describe "Smalang local arrays" do
  it "compiles and runs the fixed array example" do
    source = File.read(File.expand_path("../examples/fixed_arrays.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source, "fixed_arrays.py")

    BackendSpecHelpers.link_and_run(lowered).should eq(56)
  end

  it "compiles and runs the whole and nested value-copy example" do
    source = File.read(File.expand_path("../examples/fixed_arrays_value_copy.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(91)
  end

  it "compiles and runs nested array function and mixed-ABI examples" do
    source = File.read(File.expand_path("../examples/fixed_arrays_function_values.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(47)
  end

  it "returns array values selected from distinct locals by match" do
    source = "def select(flag: bool) -> array[int, 2]:\n    first: array[int, 2] = [10, 20]\n    second: array[int, 2] = [30, 40]\n    return match flag:\n        case True: first\n        case False: second\n\ndef main() -> int:\n    first: array[int, 2] = select(True)\n    second: array[int, 2] = select(False)\n    return first[0] + first[1] + second[0] + second[1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(100)
  end

  it "compiles and runs the zero-length array example" do
    source = File.read(File.expand_path("../examples/fixed_arrays_empty.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "compiles and runs the evaluation-order example" do
    source = File.read(File.expand_path("../examples/fixed_arrays_evaluation_order.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(45)
  end

  it "reports the source bounds failure in the runtime-error example" do
    source = File.read(File.expand_path("../examples/fixed_arrays_bounds_error.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source, "fixed_arrays_bounds_error.py")
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("at read (fixed_arrays_bounds_error.py:3)")
    result[:stderr].should contain("at main (fixed_arrays_bounds_error.py:6)")
  end

  it "compiles every supported scalar element type in the array example" do
    source = File.read(File.expand_path("../examples/fixed_arrays_scalar_types.py", __DIR__))
    lowered = ArraySpecHelpers.lower_successfully(source)
    dump = Smalang::IrSExpressionDumper.new.dump(lowered)

    ["isize", "usize", "bool", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"].each do |type|
      dump.should contain(" #{type} (load ")
    end
    ["(const -9223372036854775808)", "(const -128)", "(const -32768)", "(const -2147483648)", "(const 18446744073709551615)"].each do |constant|
      dump.should contain(constant)
    end
    ["(stack.storage 2 1)", "(stack.storage 4 2)", "(stack.storage 8 4)", "(stack.storage 16 8)"].each do |storage_layout|
      dump.should contain(storage_layout)
    end
    BackendSpecHelpers.link_and_run(lowered).should eq(42)
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

  it "copies whole arrays during mutable reassignment" do
    source = "def main() -> int:\n    original: array[int, 2] = [1, 2]\n    replacement: array[int, 2] = [3, 4]\n    target: mut[array[int, 2]] = original\n    target = replacement\n    target = target\n    target[0] = 42\n    return original[0] + replacement[0] + target[0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(46)
  end

  it "copies whole arrays when reassigning a mutable array parameter" do
    source = "def replace(target: mut[array[int, 2]], replacement: array[int, 2]) -> array[int, 2]:\n    target = replacement\n    target[0] = 42\n    return target\n\ndef main() -> int:\n    original: array[int, 2] = [10, 20]\n    replacement: array[int, 2] = [3, 4]\n    result: array[int, 2] = replace(original, replacement)\n    return original[0] + replacement[0] + result[0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(55)
  end

  it "copies nested aggregate elements independently" do
    source = "def main() -> int:\n    matrix: mut[array[array[int, 2], 2]] = [[1, 2], [3, 4]]\n    row: mut[array[int, 2]] = matrix[0]\n    row[0] = 42\n    matrix[1] = row\n    row[1] = 99\n    return matrix[1][0] + matrix[1][1] + matrix[0][0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(45)
  end

  it "copies one nested array element into another without aliasing rows" do
    source = "def main() -> int:\n    matrix: mut[array[array[int, 2], 2]] = [[1, 2], [3, 4]]\n    matrix[0] = matrix[1]\n    return matrix[0][0] + matrix[0][1] + matrix[1][0] + matrix[1][1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(14)
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

  it "preserves nested array values through chained function calls" do
    source = "def update(values: mut[array[array[int, 2], 2]]) -> array[array[int, 2], 2]:\n    values[0][0] = 42\n    return values\n\ndef forward(values: array[array[int, 2], 2]) -> array[array[int, 2], 2]:\n    return update(values)\n\ndef observe(values: array[array[int, 2], 2]) -> int:\n    return values[0][0]\n\ndef main() -> int:\n    original: array[array[int, 2], 2] = [[1, 2], [3, 4]]\n    returned: array[array[int, 2], 2] = forward(original)\n    return observe(returned) + original[0][0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(43)
  end

  it "passes array values through the stack argument area after an array result pointer" do
    source = "def pass(a: int, b: int, c: int, d: int, e: int, values: array[int, 2]) -> array[int, 2]:\n    return values\n\ndef main() -> int:\n    original: array[int, 2] = [10, 20]\n    copied: array[int, 2] = pass(0, 0, 0, 0, 0, original)\n    return copied[1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(20)
  end

  it "keeps interleaved array and scalar arguments across the register and stack boundary" do
    source = "def combine(first: int, values: array[int, 2], second: int, third: int, fourth: int, fifth: int, sixth: int) -> int:\n    return first + values[0] + second + third + fourth + fifth + sixth\n\ndef main() -> int:\n    values: array[int, 2] = [10, 20]\n    return combine(1, values, 2, 3, 4, 5, 6)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(31)
  end

  it "passes multiple arrays in both register and stack argument slots" do
    source = "def combine(first: array[int, 2], a: int, b: int, c: int, d: int, second: array[int, 2], tail: int) -> int:\n    return first[0] + second[1] + a + b + c + d + tail\n\ndef main() -> int:\n    first: array[int, 2] = [10, 20]\n    second: array[int, 2] = [30, 40]\n    return combine(first, 1, 2, 3, 4, second, 5)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(65)
  end

  it "keeps mixed scalar and array arguments aligned when returning an array" do
    source = "def transform(first: int, second: int, third: int, fourth: int, values: array[int, 2], tail: int) -> array[int, 2]:\n    result: mut[array[int, 2]] = values\n    result[0] = first + second + third + fourth + tail\n    return result\n\ndef main() -> int:\n    values: array[int, 2] = [10, 20]\n    changed: array[int, 2] = transform(1, 2, 3, 4, values, 5)\n    return changed[0] + values[0]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(25)
  end

  it "supports empty fixed arrays" do
    source = "def main() -> int:\n    values: array[int, 0] = []\n    return 42\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "passes and returns zero-length arrays, including nested zero-length elements" do
    source = "def identity(values: array[int, 0]) -> array[int, 0]:\n    return values\n\ndef nested_identity(values: array[array[int, 0], 2]) -> array[array[int, 0], 2]:\n    return values\n\ndef consume(values: array[array[int, 0], 2]) -> int:\n    return 42\n\ndef main() -> int:\n    empty: array[int, 0] = []\n    returned: array[int, 0] = identity(empty)\n    nested: array[array[int, 0], 2] = [[], []]\n    nested_returned: array[array[int, 0], 2] = nested_identity(nested)\n    copied: array[array[int, 0], 2] = nested_returned\n    return consume(copied)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    dump = Smalang::IrSExpressionDumper.new.dump(lowered)

    dump.should contain("(stack.storage 1 8)")
    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "reports statically known indexing into an empty array" do
    source = "def main() -> int:\n    values: array[int, 0] = []\n    return values[0]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("out of bounds for length 0")
  end

  it "raises for a dynamic index into an empty array" do
    source = "def read(values: array[int, 0], index: uint) -> int:\n    return values[index]\n\ndef main() -> int:\n    values: array[int, 0] = []\n    return read(values, 0)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("local_array.py:2")
    result[:stderr].should contain("at main (local_array.py:6)")
  end

  it "round-trips array elements with every supported scalar IR type" do
    types = [
      {"int", "isize", "42"},
      {"uint", "usize", "42"},
      {"bool", "bool", "True"},
      {"int8", "int8", "1"},
      {"uint8", "uint8", "2"},
      {"int16", "int16", "3"},
      {"uint16", "uint16", "4"},
      {"int32", "int32", "5"},
      {"uint32", "uint32", "6"},
      {"int64", "int64", "7"},
      {"uint64", "uint64", "8"},
    ]
    source_lines = ["def main() -> int:"]
    types.each_with_index do |(source_type, _ir_type, first_value), index|
      second_value = source_type == "bool" ? "False" : "0"
      source_lines << "    values_#{index}: array[#{source_type}, 2] = [#{first_value}, #{second_value}]"
      source_lines << "    element_#{index}: #{source_type} = values_#{index}[1]"
    end
    source_lines << "    return values_0[0]"
    lowered = ArraySpecHelpers.lower_successfully(source_lines.join("\n") + "\n")
    dump = Smalang::IrSExpressionDumper.new.dump(lowered)

    types.each do |_source_type, ir_type, _first_value|
      dump.should contain(" #{ir_type} (load ")
    end
    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "uses recursive array layout queries in generated stack storage" do
    source = "def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(size_of(array[int, 2]), align_of(array[int, 2]))\n        last: ptr[uint8] = offset(storage, size_of(array[int, 2]) - size_of(int))\n        typed: ptr[int] = cast[int](last)\n        store(typed, 42)\n        result: int = load(typed)\n    return result\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "keeps compiler-generated temporary names distinct from source bindings" do
    source = "def main() -> int:\n    __sma_array_source_0: int = 1\n    values: array[int, 1] = [42]\n    return values[0] + __sma_array_source_0\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(43)
  end

  it "folds literal arithmetic in array initializers at compile time" do
    source = "def main() -> int:\n    values: array[int8, 2] = [127 + 1, 0]\n    return 42\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    dump = Smalang::IrSExpressionDumper.new.dump(lowered)

    dump.should contain("(const -128)")
    dump.should_not contain("(add ")
    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "folds unsigned fixed-width overflow in array initializers" do
    source = "def main() -> int:\n    values: array[uint8, 1] = [255 + 1]\n    return 42\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    dump = Smalang::IrSExpressionDumper.new.dump(lowered)

    dump.should_not contain("(add ")
    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "loads bool and narrow signed array elements with their declared widths" do
    source = "def accept(value: int8) -> int:\n    return 42\n\ndef choose(flag: bool) -> int:\n    return match flag:\n        case True: 42\n        case False: 0\n\ndef main() -> int:\n    signed_values: array[int8, 1] = [0 - 1]\n    flags: array[bool, 1] = [True]\n    return accept(signed_values[0]) + choose(flags[0])\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(84)
  end

  it "rejects statically known out-of-bounds indices during compilation" do
    source = "def main() -> int:\n    values: array[int, 2] = [10, 20]\n    return values[2]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("out of bounds for length 2")
  end

  it "rejects statically known out-of-bounds indices in nested arrays" do
    source = "def main() -> int:\n    matrix: array[array[int, 2], 2] = [[1, 2], [3, 4]]\n    return matrix[0][2]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("out of bounds for length 2")
  end

  it "rejects out-of-bounds indices computed by compile-time layout queries" do
    source = "def main() -> int:\n    values: mut[array[int, 4]] = [10, 20, 30, 40]\n    unsafe:\n        values[size_of(uint64)] = 42\n    return values[0]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("out of bounds for length 4")
  end

  it "evaluates constant arithmetic before checking array bounds" do
    ["1 + 1", "0 - 1"].each do |index_expression|
      source = "def main() -> int:\n    values: array[int, 2] = [10, 20]\n    return values[#{index_expression}]\n"
      result = ArraySpecHelpers.semantic_result(source)

      result.success?.should be_false
      result.diagnostic.not_nil!.description.should contain("out of bounds for length 2")
    end
  end

  it "requires array literals to contain exactly their declared length" do
    source = "def main() -> int:\n    values: array[int, 2] = [10]\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should eq("array literal has 1 elements, expected 2")
  end

  it "checks the declared length of every nested array literal" do
    source = "def main() -> int:\n    matrix: array[array[int, 2], 2] = [[1, 2], [3]]\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should eq("array literal has 1 elements, expected 2")
  end

  it "checks element types at every nested array literal level" do
    source = "def main() -> int:\n    matrix: array[array[int, 2], 2] = [[1, 2], [True, False]]\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("array element has type bool, expected int")
  end

  it "rejects whole-array assignment with a different fixed length" do
    source = "def main() -> int:\n    target: mut[array[int, 2]] = [1, 2]\n    replacement: array[int, 3] = [3, 4, 5]\n    target = replacement\n    return target[0]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("assignment has type array[int, 3], expected array[int, 2]")
  end

  it "rejects a function argument with a different fixed array length" do
    source = "def first(values: array[int, 2]) -> int:\n    return values[0]\n\ndef main() -> int:\n    values: array[int, 3] = [1, 2, 3]\n    return first(values)\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("argument 0 has type array[int, 3], expected array[int, 2]")
  end

  it "rejects returning an array with a different fixed length" do
    source = "def invalid() -> array[int, 2]:\n    values: array[int, 3] = [1, 2, 3]\n    return values\n\ndef main() -> int:\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("return has type array[int, 3], expected array[int, 2]")
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

  it "requires mutable root bindings for nested indexed assignment" do
    source = "def main() -> int:\n    matrix: array[array[int, 2], 2] = [[1, 2], [3, 4]]\n    matrix[0][1] = 42\n    return matrix[0][1]\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should contain("cannot modify elements of immutable binding 'matrix'")
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

  it "rejects oversized nested array dimensions even when their storage size is zero" do
    ["array[array[int, 0], 2147483648]", "array[array[int, 2147483648], 0]"].each do |array_type|
      source = "def consume(values: #{array_type}) -> int:\n    return 42\n\ndef main() -> int:\n    return 0\n"
      semantic = ArraySpecHelpers.semantic_result(source)
      semantic.success?.should be_true
      lowered = Smalang::IrLowerer.new(semantic.semantic_module.not_nil!).lower

      lowered.success?.should be_false
      lowered.diagnostic.not_nil!.description.should contain("array type exceeds x86_64 stack frame or index limits")
    end
  end

  it "reports a dynamic out-of-bounds index as a runtime exception" do
    source = "def get(index: uint) -> int:\n    values: array[int, 2] = [10, 20]\n    return values[index]\n\ndef main() -> int:\n    return get(2)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("local_array.py:3")
    result[:stderr].should contain("at main (local_array.py:6)")
  end

  it "accepts the first and last dynamic indices" do
    source = "def get(values: array[int, 2], index: uint) -> int:\n    return values[index]\n\ndef main() -> int:\n    values: array[int, 2] = [10, 20]\n    return get(values, 0) + get(values, 1)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(30)
  end

  it "rejects the maximum uint as an array index at runtime" do
    source = "def read(index: uint) -> int:\n    values: array[int, 2] = [10, 20]\n    return values[index]\n\ndef main() -> int:\n    return read(18446744073709551615)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("at read (local_array.py:3)")
    result[:stderr].should contain("at main (local_array.py:6)")
  end

  it "reports the inner source location for a nested dynamic bounds failure" do
    source = "def read(column: uint) -> int:\n    matrix: array[array[int, 2], 2] = [[1, 2], [3, 4]]\n    return matrix[1][column]\n\ndef main() -> int:\n    return read(2)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("at read (local_array.py:3)")
    result[:stderr].should contain("at main (local_array.py:6)")
  end

  it "checks dynamic indexed assignments before storing" do
    source = "def set_value(index: uint) -> int:\n    values: mut[array[int, 2]] = [10, 20]\n    values[index] = 42\n    return values[0]\n\ndef main() -> int:\n    return set_value(2)\n"
    lowered = ArraySpecHelpers.lower_successfully(source)
    result = BackendSpecHelpers.link_and_capture(lowered)

    result[:exit_code].should eq(1)
    result[:stderr].should contain("IndexOutOfBounds")
    result[:stderr].should contain("local_array.py:3")
    result[:stderr].should contain("at main (local_array.py:7)")
  end

  it "evaluates indexed assignment RHS before its index exactly once" do
    source = "def rhs(counter: ptr[uint]) -> int:\n    unsafe:\n        value: uint = load(counter)\n        store(counter, value + 1)\n    return 42\n\ndef next_index(counter: ptr[uint]) -> uint:\n    unsafe:\n        value: uint = load(counter)\n        store(counter, value + 1)\n    return value\n\ndef main() -> int:\n    unsafe:\n        counter: ptr[uint] = alloc(0)\n    values: mut[array[int, 2]] = [10, 20]\n    values[next_index(counter)] = rhs(counter)\n    unsafe:\n        free(counter)\n    return values[1]\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(42)
  end

  it "evaluates RHS before nested assignment indices, left to right, exactly once" do
    source = "def next_index(counter: ptr[uint]) -> uint:\n    unsafe:\n        value: uint = load(counter)\n        store(counter, value + 1)\n    return value\n\ndef rhs(counter: ptr[uint]) -> int:\n    unsafe:\n        value: uint = load(counter)\n        store(counter, value + 1)\n    return 42\n\ndef main() -> int:\n    unsafe:\n        counter: ptr[uint] = alloc(0)\n    matrix: mut[array[array[int, 3], 2]] = [[1, 2, 3], [4, 5, 6]]\n    matrix[next_index(counter)][next_index(counter)] = rhs(counter)\n    unsafe:\n        count: int = load(cast[int](counter))\n        free(counter)\n    return matrix[1][2] + count\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(45)
  end

  it "evaluates an indexed read base before its indices, exactly once" do
    source = "def next_index(counter: ptr[uint]) -> uint:\n    unsafe:\n        value: uint = load(counter)\n        store(counter, value + 1)\n    return value\n\ndef matrix_after_marking(counter: ptr[uint]) -> array[array[int, 3], 3]:\n    unsafe:\n        value: uint = load(counter)\n        store(counter, value + 1)\n    return [[1, 2, 3], [4, 5, 6], [7, 8, 9]]\n\ndef main() -> int:\n    unsafe:\n        counter: ptr[uint] = alloc(0)\n    value: int = matrix_after_marking(counter)[next_index(counter)][next_index(counter)]\n    unsafe:\n        count: int = load(cast[int](counter))\n        free(counter)\n    return value + count\n"
    lowered = ArraySpecHelpers.lower_successfully(source)

    BackendSpecHelpers.link_and_run(lowered).should eq(9)
  end

  it "rejects array layouts whose size does not fit uint" do
    source = "def main() -> int:\n    unsafe:\n        size: uint = size_of(array[int64, 18446744073709551615])\n    return 0\n"
    result = ArraySpecHelpers.semantic_result(source)

    result.success?.should be_false
    result.diagnostic.not_nil!.description.should eq("size_of layout is not representable as uint")
  end
end
