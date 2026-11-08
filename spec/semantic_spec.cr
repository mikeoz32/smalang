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
