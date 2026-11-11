require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"
require "../src/smalang/semantic"

module SemanticSpecHelpers
  def self.analyze(source : String, name : String = "semantic_spec.py")
    tokens = Smalang::Lexer.new.tokenize(source, name)
    parse_result = Smalang::Parser.new(tokens).parse
    parse_result.success?.should eq(true)
    Smalang::SemanticAnalyzer.new(parse_result.parsed_module).analyze
  end
end

describe Smalang::SemanticAnalyzer do
  it "accepts typed raw pointers in function parameters and results" do
    result = SemanticSpecHelpers.analyze(
      "def identity(address: ptr[int]) -> ptr[int]:\n    return address\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(true)
  end

  it "rejects unsupported pointer pointees and integer-pointer mixing" do
    invalid_programs = [
      {"def alloc() -> int:\n    return 0\n\ndef main() -> int:\n    return 0\n", "function name 'alloc' is reserved for an unsafe memory operation"},
      {"def invalid(address: ptr[array[int, 1]]) -> int:\n    return 0\n\ndef main() -> int:\n    return 0\n", "unsupported type 'ptr[array[int, 1]]'"},
      {"def main() -> int:\n    address: ptr[int] = 42\n    return 0\n", "initializer has type int, expected ptr[int]"},
      {"def main() -> int:\n    values: array[ptr[int], 1] = [0]\n    return 0\n", "unsupported type 'array[ptr[int], 1]'"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "checks scalar pointer operations in an unsafe block" do
    result = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(42)\n        store(address, 17)\n        result: int = load(address)\n        free(address)\n    return result\n"
    )

    result.success?.should eq(true)
  end

  it "checks stack allocation type, arity, and unsafe context" do
    accepted = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(42)\n        store(address, 17)\n        result: int = load(address)\n    return result\n"
    )
    accepted.success?.should eq(true)

    invalid_programs = [
      {"def shift(address: ptr[int], index: uint) -> ptr[int]:\n    return offset(address, index)\n\ndef main() -> int:\n    return 0\n", "unsafe operation 'offset' requires an unsafe block"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack()\n    return 0\n", "alloc_stack expects 1 argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1, 2)\n    return 0\n", "alloc_stack expects 1 argument, got 2"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(True)\n    return 0\n", "alloc_stack value has type bool, expected int"},
      {"def main() -> int:\n    value: int = 42\n    unsafe:\n        address: ptr[uint] = alloc_stack(value)\n    return 0\n", "alloc_stack value has type int, expected uint"},
      {"def main() -> int:\n    unsafe:\n        source: ptr[int] = alloc(1)\n        address: ptr[int] = alloc_stack(source)\n    return 0\n", "alloc_stack supports scalar values only"},
      {"def alloc_stack(value: int) -> int:\n    return value\n\ndef main() -> int:\n    return 0\n", "function name 'alloc_stack' is reserved for an unsafe memory operation"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "checks stack storage size, alignment, constants, arity, and unsafe context" do
    accepted = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    unsafe:\n        bytes: ptr[uint8] = stack_storage(4 + 4, 4 + 4)\n    return 0\n"
    )
    accepted.success?.should eq(true)

    invalid_programs = [
      {"def stack_storage(bytes: uint, alignment: uint) -> uint:\n    return bytes\n\ndef main() -> int:\n    return 0\n", "function name 'stack_storage' is reserved for an unsafe memory operation"},
      {"def reserve() -> ptr[uint8]:\n    return stack_storage(8, 8)\n\ndef main() -> int:\n    return 0\n", "unsafe operation 'stack_storage' requires an unsafe block"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage()\n    return 0\n", "stack_storage expects 2 arguments, got 0"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(8)\n    return 0\n", "stack_storage expects 2 arguments, got 1"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(8, 8, 8)\n    return 0\n", "stack_storage expects 2 arguments, got 3"},
      {"def main() -> int:\n    unsafe:\n        size: int = 8\n        storage: ptr[uint8] = stack_storage(size, 8)\n    return 0\n", "stack_storage byte size has type int, expected uint"},
      {"def main() -> int:\n    unsafe:\n        alignment: int = 8\n        storage: ptr[uint8] = stack_storage(8, alignment)\n    return 0\n", "stack_storage alignment has type int, expected uint"},
      {"def main() -> int:\n    unsafe:\n        size: uint = 8\n        storage: ptr[uint8] = stack_storage(size, 8)\n    return 0\n", "stack_storage byte size must be a compile-time constant"},
      {"def size() -> uint:\n    return 8\n\ndef main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(size(), 8)\n    return 0\n", "stack_storage byte size must be a compile-time constant"},
      {"def main() -> int:\n    unsafe:\n        alignment: uint = 8\n        storage: ptr[uint8] = stack_storage(8, alignment)\n    return 0\n", "stack_storage alignment must be a compile-time constant"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(0, 8)\n    return 0\n", "stack_storage byte size must be greater than zero"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(8, 0)\n    return 0\n", "stack_storage alignment must be greater than zero"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(8, 3)\n    return 0\n", "stack_storage alignment must be a power of two"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(18446744073709551615 + 1, 8)\n    return 0\n", "stack_storage byte size constant expression overflows uint"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(0 - 1, 8)\n    return 0\n", "stack_storage byte size constant expression overflows uint"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(8, 18446744073709551615 + 2)\n    return 0\n", "stack_storage alignment constant expression overflows uint"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(18446744073709551615, 2)\n    return 0\n", "stack_storage size and alignment overflow uint"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(2147483648, 1)\n    return 0\n", "stack_storage region exceeds x86_64 frame limits"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "accepts scalar and pointer layout queries as compile-time uint values" do
    layouts = [
      {"bool", 1_u64, 1_u64},
      {"int", 8_u64, 8_u64},
      {"uint", 8_u64, 8_u64},
      {"int8", 1_u64, 1_u64},
      {"uint8", 1_u64, 1_u64},
      {"int16", 2_u64, 2_u64},
      {"uint16", 2_u64, 2_u64},
      {"int32", 4_u64, 4_u64},
      {"uint32", 4_u64, 4_u64},
      {"int64", 8_u64, 8_u64},
      {"uint64", 8_u64, 8_u64},
    ]
    source_lines = ["def main() -> int:", "    unsafe:"]
    expected_values = [] of UInt64
    layouts.each do |type_name, size, alignment|
      source_lines << "        size_#{type_name}: uint = size_of(#{type_name})"
      source_lines << "        alignment_#{type_name}: uint = align_of(#{type_name})"
      expected_values << size << alignment
    end
    source_lines << "        pointer_size: uint = size_of(ptr[int])"
    source_lines << "        pointer_alignment: uint = align_of(ptr[bool])"
    source_lines << "        bool_pointer_size: uint = size_of(ptr[bool])"
    source_lines << "        int_pointer_alignment: uint = align_of(ptr[int])"
    source_lines << "        storage: ptr[uint8] = stack_storage(size_of(uint64), align_of(uint64))"
    source_lines << "        storage_sum: ptr[uint8] = stack_storage(size_of(uint64) + align_of(uint64), align_of(uint64))"
    source_lines << "        storage_difference: ptr[uint8] = stack_storage(size_of(uint64) - align_of(uint32), align_of(uint64))"
    expected_values.concat([8_u64, 8_u64, 8_u64, 8_u64, 8_u64, 8_u64, 8_u64, 8_u64, 8_u64, 8_u64, 4_u64, 8_u64])
    source_lines << "    return 0"
    source = source_lines.join("\n") + "\n"

    tokens = Smalang::Lexer.new.tokenize(source, "layout_queries.py")
    parsed = Smalang::Parser.new(tokens).parse
    parsed.success?.should eq(true)
    result = Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
    result.success?.should eq(true)

    semantic_module = result.semantic_module.not_nil!
    query_values = [] of UInt64?
    parsed.parsed_module.arena.size.times do |node_id|
      call = parsed.parsed_module.arena.node(node_id).as?(Smalang::CallExpr)
      next unless call
      name = parsed.parsed_module.source_file.slice(call.callee)
      next unless name == "size_of" || name == "align_of"
      query_values << semantic_module.constant_uint_value(node_id)
    end
    query_values.should eq(expected_values.map { |value| value.as(UInt64?) })
  end

  it "checks layout query unsafe context, type arguments, and arity" do
    invalid_programs = [
      {"def main() -> int:\n    return size_of(int)\n", "unsafe operation 'size_of' requires an unsafe block"},
      {"def main() -> int:\n    unsafe:\n        value: uint = size_of()\n    return 0\n", "size_of expects 1 type argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        value: uint = align_of(int, uint)\n    return 0\n", "align_of expects 1 type argument, got 2"},
      {"def main() -> int:\n    unsafe:\n        value: uint = size_of(missing_type)\n    return 0\n", "size_of expects a supported type name"},
      {"def main() -> int:\n    unsafe:\n        value: uint = size_of(42)\n    return 0\n", "size_of expects a supported type name"},
      {"def main() -> int:\n    unsafe:\n        value: uint = size_of(ptr[ptr[int]])\n    return 0\n", "size_of expects a supported type name"},
      {"def main() -> int:\n    unsafe:\n        storage: ptr[uint8] = stack_storage(size_of(int) + 18446744073709551615, 8)\n    return 0\n", "stack_storage byte size constant expression overflows uint"},
      {"def size_of(type_name: int) -> uint:\n    return 1\n\ndef main() -> int:\n    return 0\n", "function name 'size_of' is reserved for an unsafe memory operation"},
      {"def align_of(type_name: int) -> uint:\n    return 1\n\ndef main() -> int:\n    return 0\n", "function name 'align_of' is reserved for an unsafe memory operation"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "checks address_of unsafe context, arity, and place arguments" do
    invalid_programs = [
      {"def main() -> int:\n    value: int = 42\n    address: ptr[int] = address_of(value)\n    return 0\n", "unsafe operation 'address_of' requires an unsafe block"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = address_of()\n    return 0\n", "address_of expects 1 argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = address_of(42)\n    return 0\n", "address_of requires a scalar local binding or parameter"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(42)\n        pointer: ptr[uint8] = address_of(address)\n    return 0\n", "address_of supports scalar local bindings and parameters only"},
      {"def main() -> int:\n    values: array[int, 1] = [42]\n    unsafe:\n        address: ptr[int] = address_of(values)\n    return 0\n", "address_of supports scalar local bindings and parameters only"},
      {"def address_of(value: int) -> ptr[int]:\n    return value\n\ndef main() -> int:\n    return 0\n", "function name 'address_of' is reserved for an unsafe memory operation"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "checks pointer offset types, arity, and unsafe context" do
    accepted = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    unsafe:\n        address: ptr[int8] = alloc_stack(42)\n        shifted: ptr[int8] = offset(address, 1)\n    return 0\n"
    )
    accepted.success?.should eq(true)

    invalid_programs = [
      {"def main() -> int:\n    address: ptr[int] = alloc_stack(42)\n    return 0\n", "unsafe operation 'alloc_stack' requires an unsafe block"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(42)\n        shifted: ptr[int] = offset(address)\n    return 0\n", "offset expects 2 arguments, got 1"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(42)\n        shifted: ptr[int] = offset(address, 1, 2)\n    return 0\n", "offset expects 2 arguments, got 3"},
      {"def main() -> int:\n    unsafe:\n        value: int = 42\n        shifted: ptr[int] = offset(value, 1)\n    return 0\n", "offset requires ptr[T], got int"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(42)\n        index: int = 1\n        shifted: ptr[int] = offset(address, index)\n    return 0\n", "offset index has type int, expected uint"},
      {"def offset(address: ptr[int], index: uint) -> ptr[int]:\n    return address\n\ndef main() -> int:\n    return 0\n", "function name 'offset' is reserved for an unsafe memory operation"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "checks pointer cast types, arity, unsafe context, and reserved names" do
    accepted = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1)\n        converted: ptr[uint] = cast[uint](address)\n    return 0\n"
    )
    accepted.success?.should eq(true)

    invalid_programs = [
      {"def cast(value: int) -> int:\n    return value\n\ndef main() -> int:\n    return 0\n", "function name 'cast' is reserved for an unsafe memory operation"},
      {"def convert(address: ptr[int]) -> ptr[uint]:\n    return cast[uint](address)\n\ndef main() -> int:\n    return 0\n", "unsafe operation 'cast' requires an unsafe block"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1)\n        converted: ptr[uint] = cast(address)\n    return 0\n", "cast requires an explicit target type: cast[U](address)"},
      {"def main() -> int:\n    unsafe:\n        value: int = 1\n        converted: ptr[uint] = cast[uint](value)\n    return 0\n", "cast requires ptr[T], got int"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1)\n        converted: ptr[uint] = cast[array[int, 1]](address)\n    return 0\n", "cast target type must be scalar, got array[int, 1]"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1)\n        converted: ptr[int] = cast[ptr[uint]](address)\n    return 0\n", "cast target type must be scalar, got ptr[uint]"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1)\n        converted: ptr[uint] = cast[uint]()\n    return 0\n", "cast expects 1 argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc_stack(1)\n        converted: ptr[uint] = cast[uint](address, address)\n    return 0\n", "cast expects 1 argument, got 2"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "rejects raw memory operations outside an unsafe block" do
    invalid_programs = [
      {"def main() -> int:\n    address: ptr[int] = alloc(42)\n    return 0\n", "alloc"},
      {"def read(address: ptr[int]) -> int:\n    value: int = load(address)\n    return value\n\ndef main() -> int:\n    return 0\n", "load"},
      {"def write(address: ptr[int]) -> int:\n    store(address, 1)\n    return 0\n\ndef main() -> int:\n    return 0\n", "store"},
      {"def release(address: ptr[int]) -> int:\n    free(address)\n    return 0\n\ndef main() -> int:\n    return 0\n", "free"},
      {"def shift(address: ptr[int]) -> ptr[int]:\n    return offset(address, 1)\n\ndef main() -> int:\n    return 0\n", "offset"},
    ]

    invalid_programs.each do |source, operation|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq("unsafe operation '#{operation}' requires an unsafe block")
    end
  end

  it "reports invalid raw memory operations during semantic analysis" do
    invalid_programs = [
      {"def main() -> int:\n    unsafe:\n        value: int = 1\n        result: int = load(value)\n    return result\n", "load requires ptr[T], got int"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(1)\n        value: int = load()\n    return value\n", "load expects 1 argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(1)\n        store(address)\n    return 0\n", "store expects 2 arguments, got 1"},
      {"def main() -> int:\n    unsafe:\n        value: int = 1\n        free(value)\n    return 0\n", "free requires ptr[T], got int"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(1)\n        store(address, True)\n    return 0\n", "store value has type bool, expected int"},
      {"def main() -> int:\n    unsafe:\n        value: int = 1\n        store(value, 2)\n    return 0\n", "store requires ptr[T], got int"},
      {"def main() -> int:\n    unsafe:\n        free()\n    return 0\n", "free expects 1 argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc()\n    return 0\n", "alloc expects 1 argument, got 0"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(1)\n        result: int = store(address, 2)\n    return result\n", "store must be a standalone statement"},
      {"def main() -> int:\n    unsafe:\n        address: ptr[int] = alloc(1)\n        result: int = free(address)\n    return result\n", "free must be a standalone statement"},
      {"def main() -> int:\n    unsafe:\n        alloc(1)\n    return 0\n", "expression statements are not supported"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.description.should eq(expected_message)
    end
  end

  it "analyzes the checked-in program and resolves its call and parameter" do
    source = File.read("#{__DIR__}/../examples/first_program.py")
    tokens = Smalang::Lexer.new.tokenize(source, "first_program.py")
    parse_result = Smalang::Parser.new(tokens).parse
    parse_result.success?.should eq(true)
    parsed = parse_result.parsed_module
    node_count_before = parsed.arena.size

    semantic_result = Smalang::SemanticAnalyzer.new(parsed).analyze
    semantic_result.success?.should eq(true)

    semantic = semantic_result.semantic_module.not_nil!
    semantic.parsed_module.should be(parsed)
    parsed.arena.size.should eq(node_count_before)

    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)
    adjust_id = parsed.arena.child(module_node.functions, 0)
    adjust = parsed.arena.node(adjust_id).as(Smalang::FunctionNode)
    parameter_id = parsed.arena.child(adjust.parameters, 0)
    return_node = parsed.arena.node(adjust.body).as(Smalang::ReturnNode)
    subtraction_id = return_node.value
    subtraction = parsed.arena.node(subtraction_id).as(Smalang::BinaryExpr)
    addition_id = subtraction.left
    addition = parsed.arena.node(addition_id).as(Smalang::BinaryExpr)
    parameter_use_id = addition.left

    main_id = parsed.arena.child(module_node.functions, 1)
    main = parsed.arena.node(main_id).as(Smalang::FunctionNode)
    main_return = parsed.arena.node(main.body).as(Smalang::ReturnNode)
    call_id = main_return.value

    semantic.symbol_for(parameter_use_id).should eq(semantic.symbol_for(parameter_id))
    semantic.symbol_for(call_id).should eq(semantic.symbol_for(adjust_id))
    semantic.type_of(addition_id).should eq(semantic.type_table.int_type_id)
    semantic.type_of(call_id).should eq(semantic.type_table.int_type_id)
  end

  it "checks unsigned expressions from explicitly typed parameters" do
    source = "def add(left: uint, right: uint) -> uint:\n    return left + right\n\ndef main() -> int:\n    return 0\n"
    tokens = Smalang::Lexer.new.tokenize(source)
    parsed = Smalang::Parser.new(tokens).parse.parsed_module
    result = Smalang::SemanticAnalyzer.new(parsed).analyze

    result.success?.should eq(true)

    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)
    function_id = parsed.arena.child(module_node.functions, 0)
    function = parsed.arena.node(function_id).as(Smalang::FunctionNode)
    return_node = parsed.arena.node(function.body).as(Smalang::ReturnNode)
    expression = parsed.arena.node(return_node.value).as(Smalang::BinaryExpr)
    semantic = result.semantic_module.not_nil!
    semantic.type_of(return_node.value).should eq(semantic.type_table.uint_type_id)
    semantic.type_of(expression.left).should eq(semantic.type_table.uint_type_id)
  end

  it "accepts fixed-width integer signatures and contextual in-range literals" do
    source = String.build do |program|
      program << "def signed8() -> int8:\n    return 127\n\n"
      program << "def unsigned8() -> uint8:\n    return 255\n\n"
      program << "def signed16() -> int16:\n    return 32767\n\n"
      program << "def unsigned16() -> uint16:\n    return 65535\n\n"
      program << "def signed32() -> int32:\n    return 2147483647\n\n"
      program << "def unsigned32() -> uint32:\n    return 4294967295\n\n"
      program << "def signed64() -> int64:\n    return 9223372036854775807\n\n"
      program << "def unsigned64() -> uint64:\n    return 18446744073709551615\n\n"
      program << "def signed_pointer() -> int:\n    return 9223372036854775807\n\n"
      program << "def unsigned_pointer() -> uint:\n    return 18446744073709551615\n\n"
      program << "def main() -> int:\n    return 0\n"
    end

    result = SemanticSpecHelpers.analyze(source)

    result.success?.should eq(true)
  end

  it "checks bool parameters, results, literals, and calls" do
    result = SemanticSpecHelpers.analyze(
      "def identity(value: bool) -> bool:\n    return value\n\ndef truth() -> bool:\n    return identity(True)\n\ndef falsehood() -> bool:\n    return identity(False)\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(true)
    semantic = result.semantic_module.not_nil!
    semantic.type_table.label(semantic.type_table.bool_type_id).should eq("bool")

    parsed = semantic.parsed_module
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)
    identity_id = parsed.arena.child(module_node.functions, 0)
    identity = parsed.arena.node(identity_id).as(Smalang::FunctionNode)
    parameter_id = parsed.arena.child(identity.parameters, 0)
    returned_parameter = parsed.arena.node(identity.body).as(Smalang::ReturnNode).value
    semantic.type_of(returned_parameter).should eq(semantic.type_table.bool_type_id)
    semantic.symbol_for(returned_parameter).should eq(semantic.symbol_for(parameter_id))

    truth = parsed.arena.node(parsed.arena.child(module_node.functions, 1)).as(Smalang::FunctionNode)
    truth_call_id = parsed.arena.node(truth.body).as(Smalang::ReturnNode).value
    truth_call = parsed.arena.node(truth_call_id).as(Smalang::CallExpr)
    true_literal_id = parsed.arena.child(truth_call.arguments, 0)
    semantic.type_of(true_literal_id).should eq(semantic.type_table.bool_type_id)
    semantic.type_of(truth_call_id).should eq(semantic.type_table.bool_type_id)

    falsehood = parsed.arena.node(parsed.arena.child(module_node.functions, 2)).as(Smalang::FunctionNode)
    false_call_id = parsed.arena.node(falsehood.body).as(Smalang::ReturnNode).value
    false_call = parsed.arena.node(false_call_id).as(Smalang::CallExpr)
    false_literal_id = parsed.arena.child(false_call.arguments, 0)
    semantic.type_of(false_literal_id).should eq(semantic.type_table.bool_type_id)
  end

  it "treats lowercase true and false as ordinary function names" do
    result = SemanticSpecHelpers.analyze(
      "def true() -> bool:\n    return True\n\ndef false() -> bool:\n    return False\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(true)
  end

  it "checks a typed local initializer and resolves the binding in later statements" do
    result = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    total: int = 40\n    return total\n"
    )

    result.success?.should eq(true)
  end

  it "allows mutable parameters and local bindings to be reassigned" do
    result = SemanticSpecHelpers.analyze(
      "def update(value: mut[int]) -> int:\n    current: mut[int] = value\n    current = current + 1\n    value = current\n    return value\n\ndef main() -> int:\n    return update(40)\n"
    )

    result.success?.should eq(true)
  end

  it "rejects reassignment to immutable locals and parameters" do
    invalid_bindings = [
      {"def work() -> int:\n    value: int = 1\n    value = 2\n    return value\n\ndef main() -> int:\n    return work()\n", "immutable binding 'value'"},
      {"def work(value: int) -> int:\n    value = 2\n    return value\n\ndef main() -> int:\n    return work(1)\n", "immutable binding 'value'"},
      {"def work() -> int:\n    value: const[int] = 1\n    value = 2\n    return value\n\ndef main() -> int:\n    return work()\n", "immutable binding 'value'"},
    ]

    invalid_bindings.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)
      result.success?.should eq(false)
      result.diagnostic.not_nil!.message.should contain(expected_message)
    end
  end

  it "points to an assignment that violates binding immutability" do
    result = SemanticSpecHelpers.analyze(
      "def work() -> int:\n    value: int = 1\n    value = 2\n    return value\n\ndef main() -> int:\n    return work()\n",
      "immutable.py"
    )

    result.success?.should eq(false)
    diagnostic = result.diagnostic.not_nil!.message
    diagnostic.should contain("immutable.py:3:5:")
    diagnostic.should contain("cannot assign to immutable binding 'value'")
  end

  it "rejects duplicate names, use before declaration, and mismatched binding types" do
    invalid_programs = [
      {"def work(value: int) -> int:\n    value: mut[int] = 1\n    return value\n\ndef main() -> int:\n    return work(1)\n", "duplicate binding 'value'"},
      {"def work() -> int:\n    value: int = 1\n    value: mut[int] = 2\n    return value\n\ndef main() -> int:\n    return work()\n", "duplicate binding 'value'"},
      {"def work() -> int:\n    value = 1\n    return 0\n\ndef main() -> int:\n    return work()\n", "unknown name 'value'"},
      {"def work() -> int:\n    result: int = value\n    value: int = 1\n    return result\n\ndef main() -> int:\n    return work()\n", "unknown name 'value'"},
      {"def work() -> int:\n    value: int = True\n    return 0\n\ndef main() -> int:\n    return work()\n", "initializer has type bool, expected int"},
      {"def work() -> int:\n    value: mut[int] = 1\n    value = True\n    return value\n\ndef main() -> int:\n    return work()\n", "assignment has type bool, expected int"},
    ]

    invalid_programs.each do |source, expected_message|
      result = SemanticSpecHelpers.analyze(source)
      result.success?.should eq(false)
      result.diagnostic.not_nil!.message.should contain(expected_message)
    end
  end

  it "rejects implicit conversions between bool and integer types" do
    result = SemanticSpecHelpers.analyze(
      "def identity(value: bool) -> bool:\n    return value\n\ndef main() -> int:\n    return identity(1)\n"
    )
    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("argument 0 has type int, expected bool")
  end

  it "rejects a bool return from an int function" do
    result = SemanticSpecHelpers.analyze(
      "def wrong() -> int:\n    return True\n\ndef main() -> int:\n    return 0\n"
    )
    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("return has type bool, expected int")
  end

  it "rejects arithmetic on bool values" do
    result = SemanticSpecHelpers.analyze(
      "def add(left: bool, right: bool) -> bool:\n    return left + right\n\ndef main() -> int:\n    return 0\n"
    )
    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("operator '+' requires integer operands")
  end

  it "uses typed operands and enclosing signatures to type integer literals" do
    result = SemanticSpecHelpers.analyze(
      "def add(value: int8) -> int8:\n    return value + 1\n\ndef calculate() -> int16:\n    return 1 + 2\n\ndef identity(value: uint8) -> uint8:\n    return value\n\ndef call() -> uint8:\n    return identity(255)\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(true)
  end

  it "rejects integer literals that exceed the contextual type range" do
    invalid_literals = [
      {"int8", "128"},
      {"uint8", "256"},
      {"int16", "32768"},
      {"uint16", "65536"},
      {"int32", "2147483648"},
      {"uint32", "4294967296"},
      {"int64", "9223372036854775808"},
      {"uint64", "18446744073709551616"},
      {"int", "9223372036854775808"},
      {"uint", "18446744073709551616"},
    ]

    invalid_literals.each do |type, value|
      result = SemanticSpecHelpers.analyze(
        "def invalid() -> #{type}:\n    return #{value}\n\ndef main() -> int:\n    return 0\n"
      )

      result.success?.should eq(false)
      result.diagnostic.not_nil!.message.should contain("literal #{value} does not fit type #{type}")
    end
  end

  it "checks literal ranges when the context comes from calls and arithmetic operands" do
    invalid_sources = [
      "def take(value: uint8) -> int:\n    return 0\n\ndef main() -> int:\n    return take(256)\n",
      "def add(value: int8) -> int8:\n    return value + 128\n\ndef main() -> int:\n    return 0\n",
    ]

    invalid_sources.each do |source|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.message.should contain("does not fit type")
    end
  end

  it "rejects implicit conversions between differently typed integer values" do
    result = SemanticSpecHelpers.analyze(
      "def add(left: int8, right: int16) -> int16:\n    return left + right\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("operator '+' operands must have matching types")
  end

  it "rejects implicit integer conversions in calls and returns" do
    invalid_sources = [
      {"def take(value: int16) -> int16:\n    return value\n\ndef caller(value: int8) -> int16:\n    return take(value)\n\ndef main() -> int:\n    return 0\n", "argument 0 has type int8, expected int16"},
      {"def widen(value: int8) -> int16:\n    return value\n\ndef main() -> int:\n    return 0\n", "return has type int8, expected int16"},
      {"def widen(value: int) -> int64:\n    return value\n\ndef main() -> int:\n    return 0\n", "return has type int, expected int64"},
      {"def widen(value: uint) -> uint64:\n    return value\n\ndef main() -> int:\n    return 0\n", "return has type uint, expected uint64"},
      {"def add(left: int8, right: uint8) -> int8:\n    return left + right\n\ndef main() -> int:\n    return 0\n", "operator '+' operands must have matching types"},
    ]

    invalid_sources.each do |source, expected_diagnostic|
      result = SemanticSpecHelpers.analyze(source)

      result.success?.should eq(false)
      result.diagnostic.not_nil!.message.should contain(expected_diagnostic)
    end
  end

  it "resolves forward and mutually recursive function calls" do
    source = "def is_even(value: int) -> int:\n    return is_odd(value)\n\ndef is_odd(value: int) -> int:\n    return is_even(value)\n\ndef main() -> int:\n    return is_even(0)\n"
    tokens = Smalang::Lexer.new.tokenize(source)
    parsed = Smalang::Parser.new(tokens).parse.parsed_module
    result = Smalang::SemanticAnalyzer.new(parsed).analyze

    result.success?.should eq(true)
    semantic = result.semantic_module.not_nil!
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)
    even_id = parsed.arena.child(module_node.functions, 0)
    odd_id = parsed.arena.child(module_node.functions, 1)
    even = parsed.arena.node(even_id).as(Smalang::FunctionNode)
    odd = parsed.arena.node(odd_id).as(Smalang::FunctionNode)
    even_call = parsed.arena.node(even.body).as(Smalang::ReturnNode).value
    odd_call = parsed.arena.node(odd.body).as(Smalang::ReturnNode).value

    semantic.symbol_for(even_call).should eq(semantic.symbol_for(odd_id))
    semantic.symbol_for(odd_call).should eq(semantic.symbol_for(even_id))
  end

  it "rejects duplicate function names" do
    result = SemanticSpecHelpers.analyze(
      "def run() -> int:\n    return 1\n\ndef run() -> int:\n    return 2\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(false)
    result.semantic_module.should be_nil
    result.diagnostic.not_nil!.message.should contain("duplicate function")
  end

  it "rejects duplicate parameter names" do
    result = SemanticSpecHelpers.analyze(
      "def run(value: int, value: int) -> int:\n    return value\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("duplicate parameter")
  end

  it "rejects an unresolved identifier with a source location" do
    result = SemanticSpecHelpers.analyze("def main() -> int:\n    return missing\n", "unknown.py")

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("unknown.py:2:12:")
    result.diagnostic.not_nil!.message.should contain("unknown name 'missing'")
  end

  it "rejects an unresolved direct function call" do
    result = SemanticSpecHelpers.analyze("def main() -> int:\n    return missing()\n")

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("unknown function 'missing'")
  end

  it "rejects calls with the wrong arity" do
    result = SemanticSpecHelpers.analyze(
      "def identity(value: int) -> int:\n    return value\n\ndef main() -> int:\n    return identity()\n"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("expects 1 argument, got 0")
  end

  it "rejects call arguments with incompatible types" do
    result = SemanticSpecHelpers.analyze(
      "def identity(value: int) -> int:\n    return value\n\ndef caller(value: uint) -> int:\n    return identity(value)\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("argument 0 has type uint, expected int")
  end

  it "rejects arithmetic with mismatched operand types" do
    result = SemanticSpecHelpers.analyze(
      "def add(left: int, right: uint) -> int:\n    return left + right\n\ndef main() -> int:\n    return 0\n"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("+' operands must have matching types")
  end

  it "rejects a return expression whose type differs from the function result" do
    result = SemanticSpecHelpers.analyze(
      "def wrong(value: int) -> uint:\n    return value\n\ndef main() -> int:\n    return 0\n",
      "return_mismatch.py"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("return_mismatch.py:2:12:")
    result.diagnostic.not_nil!.message.should contain("return has type int, expected uint")
  end

  it "requires main to have no parameters and return int" do
    result = SemanticSpecHelpers.analyze("def main(value: int) -> int:\n    return value\n")

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("main must have no parameters")
  end

  it "rejects main with a non-int result" do
    result = SemanticSpecHelpers.analyze("def main() -> uint:\n    return 0\n")

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("main must return int")
  end

  it "requires the module to define main" do
    result = SemanticSpecHelpers.analyze("def helper() -> int:\n    return 1\n")

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("module must define 'main() -> int'")
  end

  it "stops after the first semantic error" do
    result = SemanticSpecHelpers.analyze(
      "def main() -> int:\n    return first_missing + second_missing\n"
    )

    result.success?.should eq(false)
    result.diagnostic.not_nil!.message.should contain("first_missing")
  end
end
