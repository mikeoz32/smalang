require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"
require "../src/smalang/semantic"
require "../src/smalang/ir_lowering"

module AstPassSpecHelpers
  def self.analyze(source : String) : Smalang::SemanticModule
    tokens = Smalang::Lexer.new.tokenize(source, "ast_pass_spec.py")
    parsed = Smalang::Parser.new(tokens).parse
    parsed.success?.should eq(true)
    result = Smalang::SemanticAnalyzer.new(parsed.parsed_module).analyze
    result.success?.should eq(true)
    result.semantic_module.not_nil!
  end
end

class IdentityAstPassForSpec < Smalang::AstPass
  def label : String
    "identity test pass"
  end

  def run(input : Smalang::SemanticModule) : Smalang::AstPassResult
    Smalang::AstPassResult.success(input.parsed_module)
  end
end

class FailingAstPassForSpec < Smalang::AstPass
  def label : String
    "failing test pass"
  end

  def run(input : Smalang::SemanticModule) : Smalang::AstPassResult
    root = input.parsed_module.arena.node(input.parsed_module.root_id)
    Smalang::AstPassResult.failure(root.span, "test pass rejected the module")
  end
end

class VerifyArraySemanticFactsPassForSpec < Smalang::AstPass
  def label : String
    "semantic facts test pass"
  end

  def run(input : Smalang::SemanticModule) : Smalang::AstPassResult
    module_node = input.parsed_module.arena.node(input.parsed_module.root_id).as(Smalang::ModuleNode)
    function_id = input.parsed_module.arena.child(module_node.functions, 0)
    function = input.parsed_module.arena.node(function_id).as(Smalang::FunctionNode)
    return_node = input.parsed_module.arena.node(function.body).as(Smalang::ReturnNode)
    type_id = input.type_of(return_node.value)
    unless type_id && input.type_table.label(type_id) == "ptr[uint8]"
      return Smalang::AstPassResult.failure(return_node.span, "semantic facts were not refreshed after array lowering")
    end

    Smalang::AstPassResult.success(input.parsed_module)
  end
end

class InvalidMainResultAstPassForSpec < Smalang::AstPass
  def label : String
    "invalid test pass"
  end

  def run(input : Smalang::SemanticModule) : Smalang::AstPassResult
    source = input.parsed_module
    source_arena = source.arena
    source_module = source_arena.node(source.root_id).as(Smalang::ModuleNode)
    source_function = source_arena.node(source_arena.child(source_module.functions, 0)).as(Smalang::FunctionNode)
    source_return = source_arena.node(source_function.body).as(Smalang::ReturnNode)

    type_arena = Smalang::AstTypeArena.new(source.source_file.source.bytesize.to_i32)
    bool_type = type_arena.add(Smalang::ScalarTypeSyntax.new(source_function.name.span, Smalang::AstType::Bool))

    arena = Smalang::AstArena.new(source.source_file.source.bytesize.to_i32)
    value_id = arena.add(Smalang::BooleanLiteralExpr.new(source_return.span, true))
    return_id = arena.add(Smalang::ReturnNode.new(source_return.span, value_id))
    function_id = arena.add(Smalang::FunctionNode.new(
      source_function.span,
      source_function.name,
      bool_type,
      Smalang::NodeRange.new(0, 0),
      Smalang::NodeRange.new(0, 0),
      return_id
    ))
    root_id = arena.add(Smalang::ModuleNode.new(source_module.span, arena.append_children([function_id])))
    parsed_module = Smalang::ParsedModule.new(source.source_file, arena, type_arena, root_id)
    Smalang::AstPassResult.success(parsed_module)
  end
end

describe Smalang::AstPassPipeline do
  it "runs multiple AST passes with semantic analysis between them" do
    source = "def read(values: array[int, 2]) -> array[int, 2]:\n    return values\n\ndef main() -> int:\n    values: array[int, 2] = [10, 20]\n    return 42\n"
    semantic_module = AstPassSpecHelpers.analyze(source)
    passes = [
      IdentityAstPassForSpec.new.as(Smalang::AstPass),
      Smalang::ArrayAstLoweringPass.new,
      VerifyArraySemanticFactsPassForSpec.new,
    ] of Smalang::AstPass

    result = Smalang::AstPassPipeline.new(passes).run(semantic_module)

    result.success?.should be_true
    lowered_module = result.semantic_module.not_nil!.parsed_module
    module_node = lowered_module.arena.node(lowered_module.root_id).as(Smalang::ModuleNode)
    read_function = lowered_module.arena.node(lowered_module.arena.child(module_node.functions, 0)).as(Smalang::FunctionNode)
    parameter = lowered_module.arena.node(lowered_module.arena.child(read_function.parameters, 0)).as(Smalang::ParameterNode)
    lowered_module.type_arena.type(read_function.return_type).should be_a(Smalang::PointerTypeSyntax)
    lowered_module.type_arena.type(parameter.type).should be_a(Smalang::PointerTypeSyntax)
  end

  it "preserves an AST pass diagnostic through IR lowering" do
    semantic_module = AstPassSpecHelpers.analyze("def main() -> int:\n    return 42\n")
    passes = [FailingAstPassForSpec.new.as(Smalang::AstPass)] of Smalang::AstPass
    ir_result = Smalang::IrLowerer.new(semantic_module, Smalang::AstPassPipeline.new(passes)).lower

    ir_result.success?.should be_false
    ir_result.diagnostic.not_nil!.message.should contain("ast_pass_spec.py:1:1: test pass rejected the module")
  end

  it "reports source-located diagnostics when a pass generates invalid AST" do
    semantic_module = AstPassSpecHelpers.analyze("def main() -> int:\n    return 42\n")
    passes = [InvalidMainResultAstPassForSpec.new.as(Smalang::AstPass)] of Smalang::AstPass
    ir_result = Smalang::IrLowerer.new(semantic_module, Smalang::AstPassPipeline.new(passes)).lower

    ir_result.success?.should be_false
    ir_result.diagnostic.not_nil!.message.should eq("ast_pass_spec.py:1:5: invalid test pass generated invalid AST: main must return int")
  end
end
