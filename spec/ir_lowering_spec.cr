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
  it "lowers the checked-in program to a verified executable returning 42" do
    source = File.read("#{__DIR__}/../examples/first_program.py")
    result = IrLoweringSpecHelpers.lower(source)

    result.success?.should eq(true)
    ir = result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
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
