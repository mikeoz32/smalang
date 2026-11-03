require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"

module ParserSpecHelpers
  def self.parse(source : String, name : String = "parser_spec.py") : Smalang::ParsedModule
    tokens = Smalang::Lexer.new.tokenize(source, name)
    Smalang::Parser.new(tokens).parse
  end

  def self.function_at(parsed : Smalang::ParsedModule, index : Int32) : Smalang::FunctionNode
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)
    function_id = parsed.arena.child(module_node.functions, index)
    parsed.arena.node(function_id).as(Smalang::FunctionNode)
  end
end

class ParserSpecVisitor < Smalang::AstVisitor
  getter visited : Array(Symbol)

  def initialize
    @visited = [] of Symbol
  end

  def visit(node : Smalang::ModuleNode) : Nil
    @visited << :module
  end

  def visit(node : Smalang::FunctionNode) : Nil
    @visited << :function
  end

  def visit(node : Smalang::ParameterNode) : Nil
    @visited << :parameter
  end

  def visit(node : Smalang::ReturnNode) : Nil
    @visited << :return
  end

  def visit(node : Smalang::BinaryExpr) : Nil
    @visited << :binary
  end

  def visit(node : Smalang::CallExpr) : Nil
    @visited << :call
  end

  def visit(node : Smalang::IdentifierExpr) : Nil
    @visited << :identifier
  end

  def visit(node : Smalang::IntegerLiteralExpr) : Nil
    @visited << :integer
  end
end

describe Smalang::Parser do
  it "builds an AST for a typed function returning an integer literal" do
    tokens = Smalang::Lexer.new.tokenize("def main() -> int:\n    return 42\n", "simple.py")
    parsed = Smalang::Parser.new(tokens).parse
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    module_node.functions.count.should eq(1)

    function_id = parsed.arena.child(module_node.functions, 0)
    function = parsed.arena.node(function_id).as(Smalang::FunctionNode)
    parsed.source_file.slice(function.name).should eq("main")
    function.return_type.should eq(Smalang::AstType::Int)

    return_node = parsed.arena.node(function.body).as(Smalang::ReturnNode)
    literal = parsed.arena.node(return_node.value).as(Smalang::IntegerLiteralExpr)
    parsed.source_file.slice(literal.span).should eq("42")
  end

  it "parses the checked-in first program into both function ASTs" do
    source = File.read("#{__DIR__}/../examples/first_program.py")
    parsed = ParserSpecHelpers.parse(source, "first_program.py")
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    module_node.functions.count.should eq(2)
    adjust = ParserSpecHelpers.function_at(parsed, 0)
    parsed.source_file.slice(adjust.name).should eq("adjust")
    adjust.parameters.count.should eq(1)
    adjust_body = parsed.arena.node(adjust.body).as(Smalang::ReturnNode)
    subtraction = parsed.arena.node(adjust_body.value).as(Smalang::BinaryExpr)
    parsed.source_file.slice(parsed.arena.node(subtraction.left).span).should eq("value + 5")

    main = ParserSpecHelpers.function_at(parsed, 1)
    parsed.source_file.slice(main.name).should eq("main")
    main_body = parsed.arena.node(main.body).as(Smalang::ReturnNode)
    call = parsed.arena.node(main_body.value).as(Smalang::CallExpr)
    parsed.source_file.slice(call.callee).should eq("adjust")
  end

  it "preserves typed parameters and does not require a main function" do
    parsed = ParserSpecHelpers.parse("def compute(left: uint, right: int) -> uint:\n    return left\n")
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)
    function = parsed.arena.node(parsed.arena.child(module_node.functions, 0)).as(Smalang::FunctionNode)

    parsed.source_file.slice(function.name).should eq("compute")
    function.return_type.should eq(Smalang::AstType::UInt)
    function.parameters.count.should eq(2)

    left = parsed.arena.node(parsed.arena.child(function.parameters, 0)).as(Smalang::ParameterNode)
    right = parsed.arena.node(parsed.arena.child(function.parameters, 1)).as(Smalang::ParameterNode)
    parsed.source_file.slice(left.name).should eq("left")
    left.type.should eq(Smalang::AstType::UInt)
    parsed.source_file.slice(right.name).should eq("right")
    right.type.should eq(Smalang::AstType::Int)
  end

  it "builds nested calls and left-associative arithmetic expressions" do
    parsed = ParserSpecHelpers.parse("def main() -> int:\n    return outer(inner(1), 2 - 3 + 4)\n")
    function = ParserSpecHelpers.function_at(parsed, 0)
    returned = parsed.arena.node(function.body).as(Smalang::ReturnNode)
    outer = parsed.arena.node(returned.value).as(Smalang::CallExpr)

    parsed.source_file.slice(outer.callee).should eq("outer")
    outer.arguments.count.should eq(2)

    inner = parsed.arena.node(parsed.arena.child(outer.arguments, 0)).as(Smalang::CallExpr)
    parsed.source_file.slice(inner.callee).should eq("inner")
    inner.arguments.count.should eq(1)

    addition = parsed.arena.node(parsed.arena.child(outer.arguments, 1)).as(Smalang::BinaryExpr)
    addition.operator.should eq(Smalang::BinaryOperator::Add)
    subtraction = parsed.arena.node(addition.left).as(Smalang::BinaryExpr)
    subtraction.operator.should eq(Smalang::BinaryOperator::Subtract)
  end

  it "uses parentheses to group expressions" do
    parsed = ParserSpecHelpers.parse("def main() -> int:\n    return 1 + (2 - 3)\n")
    function = ParserSpecHelpers.function_at(parsed, 0)
    returned = parsed.arena.node(function.body).as(Smalang::ReturnNode)
    addition = parsed.arena.node(returned.value).as(Smalang::BinaryExpr)
    grouped = parsed.arena.node(addition.right).as(Smalang::BinaryExpr)

    addition.operator.should eq(Smalang::BinaryOperator::Add)
    grouped.operator.should eq(Smalang::BinaryOperator::Subtract)
  end

  it "leaves name resolution and declaration uniqueness to semantic analysis" do
    parsed = ParserSpecHelpers.parse(
      "def run(value: int) -> int:\n    return missing()\n\ndef run(value: int) -> int:\n    return value\n"
    )
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    module_node.functions.count.should eq(2)
  end

  it "rejects malformed syntax with a source location" do
    error = expect_raises(Smalang::ParseError) do
      ParserSpecHelpers.parse("def main() -> int:\n    return 1 +\n", "broken.py")
    end

    error.message.not_nil!.should contain("broken.py:2:15:")
    error.message.not_nil!.should contain("expected an expression")
  end

  it "rejects trailing commas in parameter lists" do
    error = expect_raises(Smalang::ParseError) do
      ParserSpecHelpers.parse("def main(value: int,) -> int:\n    return value\n")
    end

    error.message.not_nil!.should contain("expected a parameter name, found RightParen")
  end

  it "dispatches AST nodes through typed visitor methods" do
    parsed = ParserSpecHelpers.parse("def main() -> int:\n    return 1\n")
    visitor = ParserSpecVisitor.new

    parsed.arena.node(parsed.root_id).accept(visitor)

    visitor.visited.should eq([:module])
  end
end
