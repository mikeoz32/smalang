require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"

module ParserSpecHelpers
  def self.parse(source : String, name : String = "parser_spec.py") : Smalang::ParseResult
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

  def visit(node : Smalang::MatchExpressionNode) : Nil
    @visited << :match_expression
  end

  def visit(node : Smalang::MatchCaseNode) : Nil
    @visited << :match_case
  end

  def visit(node : Smalang::BooleanMatchPatternNode) : Nil
    @visited << :boolean_match_pattern
  end

  def visit(node : Smalang::WildcardMatchPatternNode) : Nil
    @visited << :wildcard_match_pattern
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

  def visit(node : Smalang::BooleanLiteralExpr) : Nil
    @visited << :boolean
  end

  def visit(node : Smalang::ErrorNode) : Nil
    @visited << :error
  end
end

describe Smalang::Parser do
  it "builds an AST for a typed function returning an integer literal" do
    tokens = Smalang::Lexer.new.tokenize("def main() -> int:\n    return 42\n", "simple.py")
    result = Smalang::Parser.new(tokens).parse
    result.diagnostics.should be_empty
    result.success?.should eq(true)
    parsed = result.parsed_module
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
    result = ParserSpecHelpers.parse(source, "first_program.py")
    result.diagnostics.should be_empty
    parsed = result.parsed_module
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
    result = ParserSpecHelpers.parse("def compute(left: uint, right: int) -> uint:\n    return left\n")
    result.diagnostics.should be_empty
    parsed = result.parsed_module
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

  it "parses each fixed-width integer type in parameter and result annotations" do
    types = [
      {"int8", Smalang::AstType::Int8},
      {"uint8", Smalang::AstType::UInt8},
      {"int16", Smalang::AstType::Int16},
      {"uint16", Smalang::AstType::UInt16},
      {"int32", Smalang::AstType::Int32},
      {"uint32", Smalang::AstType::UInt32},
      {"int64", Smalang::AstType::Int64},
      {"uint64", Smalang::AstType::UInt64},
    ]

    types.each do |name, ast_type|
      result = ParserSpecHelpers.parse("def identity(value: #{name}) -> #{name}:\n    return value\n")
      result.diagnostics.should be_empty

      function = ParserSpecHelpers.function_at(result.parsed_module, 0)
      function.return_type.should eq(ast_type)
      parameter = result.parsed_module.arena.node(result.parsed_module.arena.child(function.parameters, 0)).as(Smalang::ParameterNode)
      parameter.type.should eq(ast_type)
    end
  end

  it "parses bool annotations and boolean literals into the AST" do
    result = ParserSpecHelpers.parse(
      "def identity(value: bool) -> bool:\n    return value\n\ndef truth() -> bool:\n    return True\n\ndef main() -> int:\n    return 0\n"
    )
    result.diagnostics.should be_empty

    parsed = result.parsed_module
    identity = ParserSpecHelpers.function_at(parsed, 0)
    identity.return_type.should eq(Smalang::AstType::Bool)
    parameter = parsed.arena.node(parsed.arena.child(identity.parameters, 0)).as(Smalang::ParameterNode)
    parameter.type.should eq(Smalang::AstType::Bool)
    truth = ParserSpecHelpers.function_at(parsed, 1)
    literal = parsed.arena.node(parsed.arena.node(truth.body).as(Smalang::ReturnNode).value).as(Smalang::BooleanLiteralExpr)
    parsed.source_file.slice(literal.span).should eq("True")
  end

  it "parses a boolean match expression with inline case results" do
    result = ParserSpecHelpers.parse(
      "def choose(value: bool) -> int:\n    return match value:\n        case True: 1\n        case False: 2\n"
    )

    result.diagnostics.should be_empty
    result.success?.should eq(true)

    parsed = result.parsed_module
    returned = parsed.arena.node(ParserSpecHelpers.function_at(parsed, 0).body).as(Smalang::ReturnNode)
    match_expression = parsed.arena.node(returned.value).as(Smalang::MatchExpressionNode)
    scrutinee = parsed.arena.node(match_expression.scrutinee).as(Smalang::IdentifierExpr)
    parsed.source_file.slice(scrutinee.span).should eq("value")
    match_expression.cases.count.should eq(2)

    true_case = parsed.arena.node(parsed.arena.child(match_expression.cases, 0)).as(Smalang::MatchCaseNode)
    true_pattern = parsed.arena.node(true_case.pattern).as(Smalang::BooleanMatchPatternNode)
    true_pattern.value.should eq(true)
    parsed.source_file.slice(parsed.arena.node(true_case.result).span).should eq("1")

    false_case = parsed.arena.node(parsed.arena.child(match_expression.cases, 1)).as(Smalang::MatchCaseNode)
    false_pattern = parsed.arena.node(false_case.pattern).as(Smalang::BooleanMatchPatternNode)
    false_pattern.value.should eq(false)
    parsed.source_file.slice(parsed.arena.node(false_case.result).span).should eq("2")
  end

  it "parses a wildcard default and full expressions as case results" do
    result = ParserSpecHelpers.parse(
      "def choose(value: bool) -> int:\n    return match value:\n        case True: calculate(1 + 2)\n        case _: 0\n"
    )
    result.diagnostics.should be_empty

    parsed = result.parsed_module
    returned = parsed.arena.node(ParserSpecHelpers.function_at(parsed, 0).body).as(Smalang::ReturnNode)
    match_expression = parsed.arena.node(returned.value).as(Smalang::MatchExpressionNode)
    true_case = parsed.arena.node(parsed.arena.child(match_expression.cases, 0)).as(Smalang::MatchCaseNode)
    call = parsed.arena.node(true_case.result).as(Smalang::CallExpr)
    parsed.source_file.slice(call.callee).should eq("calculate")

    wildcard_case = parsed.arena.node(parsed.arena.child(match_expression.cases, 1)).as(Smalang::MatchCaseNode)
    parsed.arena.node(wildcard_case.pattern).should be_a(Smalang::WildcardMatchPatternNode)
    parsed.source_file.slice(parsed.arena.node(wildcard_case.result).span).should eq("0")
  end

  it "parses a match expression nested as a case result" do
    result = ParserSpecHelpers.parse(
      "def choose(first: bool, second: bool) -> int:\n    return match first:\n        case True: match second:\n            case True: 1\n            case False: 2\n        case False: 0\n"
    )
    result.diagnostics.should be_empty

    parsed = result.parsed_module
    returned = parsed.arena.node(ParserSpecHelpers.function_at(parsed, 0).body).as(Smalang::ReturnNode)
    outer_match = parsed.arena.node(returned.value).as(Smalang::MatchExpressionNode)
    first_case = parsed.arena.node(parsed.arena.child(outer_match.cases, 0)).as(Smalang::MatchCaseNode)
    inner_match = parsed.arena.node(first_case.result).as(Smalang::MatchExpressionNode)
    inner_match.cases.count.should eq(2)
    final_case = parsed.arena.node(parsed.arena.child(outer_match.cases, 1)).as(Smalang::MatchCaseNode)
    parsed.source_file.slice(parsed.arena.node(final_case.result).span).should eq("0")
  end

  it "parses a match expression as a function-call argument" do
    result = ParserSpecHelpers.parse(
      "def choose(value: bool) -> int:\n    return wrap(match value:\n        case True: 1\n        case False: 0\n    )\n"
    )
    result.diagnostics.should be_empty

    parsed = result.parsed_module
    returned = parsed.arena.node(ParserSpecHelpers.function_at(parsed, 0).body).as(Smalang::ReturnNode)
    call = parsed.arena.node(returned.value).as(Smalang::CallExpr)
    call.arguments.count.should eq(1)
    parsed.arena.node(parsed.arena.child(call.arguments, 0)).should be_a(Smalang::MatchExpressionNode)
  end

  it "reports invalid match patterns and recovers through nested indentation" do
    result = ParserSpecHelpers.parse(
      "def broken(value: bool) -> int:\n    return match value:\n        case unknown: 1\n            return 9\n\ndef later() -> int:\n    return 7\n",
      "match_recovery.py"
    )
    parsed = result.parsed_module
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    result.success?.should eq(false)
    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should contain("match_recovery.py:3:14:")
    result.diagnostics.first.message.should contain("expected 'True', 'False', or '_' as a case pattern")
    module_node.functions.count.should eq(2)
    broken_function = parsed.arena.node(parsed.arena.child(module_node.functions, 0)).as(Smalang::FunctionNode)
    parsed.arena.node(broken_function.body).should be_a(Smalang::ErrorNode)
    parsed.source_file.slice(ParserSpecHelpers.function_at(parsed, 1).name).should eq("later")
  end

  it "reports a missing case result and keeps the following function" do
    result = ParserSpecHelpers.parse(
      "def broken(value: bool) -> int:\n    return match value:\n        case True:\n\ndef later() -> int:\n    return 7\n",
      "missing_case_result.py"
    )
    parsed = result.parsed_module
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    result.success?.should eq(false)
    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should contain("missing_case_result.py:3:19:")
    result.diagnostics.first.message.should contain("expected an expression")
    module_node.functions.count.should eq(2)
    parsed.source_file.slice(ParserSpecHelpers.function_at(parsed, 1).name).should eq("later")
  end

  it "builds nested calls and left-associative arithmetic expressions" do
    result = ParserSpecHelpers.parse("def main() -> int:\n    return outer(inner(1), 2 - 3 + 4)\n")
    result.diagnostics.should be_empty
    parsed = result.parsed_module
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
    result = ParserSpecHelpers.parse("def main() -> int:\n    return 1 + (2 - 3)\n")
    result.diagnostics.should be_empty
    parsed = result.parsed_module
    function = ParserSpecHelpers.function_at(parsed, 0)
    returned = parsed.arena.node(function.body).as(Smalang::ReturnNode)
    addition = parsed.arena.node(returned.value).as(Smalang::BinaryExpr)
    grouped = parsed.arena.node(addition.right).as(Smalang::BinaryExpr)

    addition.operator.should eq(Smalang::BinaryOperator::Add)
    grouped.operator.should eq(Smalang::BinaryOperator::Subtract)
  end

  it "leaves name resolution and declaration uniqueness to semantic analysis" do
    result = ParserSpecHelpers.parse(
      "def run(value: int) -> int:\n    return missing()\n\ndef run(value: int) -> int:\n    return value\n"
    )
    result.diagnostics.should be_empty
    parsed = result.parsed_module
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    module_node.functions.count.should eq(2)
  end

  it "reports malformed syntax with a source location" do
    result = ParserSpecHelpers.parse("def main() -> int:\n    return 1 +\n", "broken.py")
    parsed = result.parsed_module
    returned = parsed.arena.node(ParserSpecHelpers.function_at(parsed, 0).body).as(Smalang::ReturnNode)
    expression = parsed.arena.node(returned.value).as(Smalang::BinaryExpr)
    missing = parsed.arena.node(expression.right).as(Smalang::ErrorNode)

    result.success?.should eq(false)
    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should contain("broken.py:2:15:")
    result.diagnostics.first.message.should contain("expected an expression")
    missing.span.length.should eq(0)
  end

  it "reports trailing commas in parameter lists" do
    result = ParserSpecHelpers.parse("def main(value: int,) -> int:\n    return value\n")

    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should contain("trailing comma")
  end

  it "dispatches AST nodes through typed visitor methods" do
    parsed = ParserSpecHelpers.parse("def main() -> int:\n    return 1\n").parsed_module
    visitor = ParserSpecVisitor.new

    parsed.arena.node(parsed.root_id).accept(visitor)

    visitor.visited.should eq([:module])
  end

  it "keeps a partial expression and parses later functions after an error" do
    result = ParserSpecHelpers.parse(
      "def broken() -> int:\n    return 1 +\n\ndef later() -> int:\n    return 7\n",
      "recover.py"
    )
    parsed = result.parsed_module
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    result.success?.should eq(false)
    result.diagnostics.size.should eq(1)
    module_node.functions.count.should eq(2)

    broken = ParserSpecHelpers.function_at(parsed, 0)
    returned = parsed.arena.node(broken.body).as(Smalang::ReturnNode)
    expression = parsed.arena.node(returned.value).as(Smalang::BinaryExpr)
    parsed.arena.node(expression.right).as(Smalang::ErrorNode)

    later = ParserSpecHelpers.function_at(parsed, 1)
    parsed.source_file.slice(later.name).should eq("later")
  end

  it "recovers inside parameter and argument lists and reports each error" do
    result = ParserSpecHelpers.parse(
      "def run(first: int, : uint, last: int) -> int:\n    return combine(1, , 2)\n"
    )
    parsed = result.parsed_module
    function = ParserSpecHelpers.function_at(parsed, 0)
    returned = parsed.arena.node(function.body).as(Smalang::ReturnNode)
    call = parsed.arena.node(returned.value).as(Smalang::CallExpr)

    result.diagnostics.size.should eq(2)
    function.parameters.count.should eq(3)
    parsed.arena.node(parsed.arena.child(function.parameters, 1)).as(Smalang::ErrorNode)
    parsed.source_file.slice(
      parsed.arena.node(parsed.arena.child(function.parameters, 2)).as(Smalang::ParameterNode).name
    ).should eq("last")
    call.arguments.count.should eq(3)
    parsed.arena.node(parsed.arena.child(call.arguments, 1)).as(Smalang::ErrorNode)
    parsed.source_file.slice(
      parsed.arena.node(parsed.arena.child(call.arguments, 2)).as(Smalang::IntegerLiteralExpr).span
    ).should eq("2")
  end

  it "recovers from invalid top-level syntax and keeps following declarations" do
    result = ParserSpecHelpers.parse("return 0\n\ndef main() -> int:\n    return 1\n")
    parsed = result.parsed_module
    module_node = parsed.arena.node(parsed.root_id).as(Smalang::ModuleNode)

    result.diagnostics.size.should eq(1)
    module_node.functions.count.should eq(2)
    error_node = parsed.arena.node(parsed.arena.child(module_node.functions, 0)).as(Smalang::ErrorNode)
    visitor = ParserSpecVisitor.new
    error_node.accept(visitor)
    visitor.visited.should eq([:error])
    parsed.source_file.slice(ParserSpecHelpers.function_at(parsed, 1).name).should eq("main")
  end

  it "wraps a recovered call when its closing parenthesis is missing" do
    result = ParserSpecHelpers.parse("def main() -> int:\n    return compute(41\n")
    parsed = result.parsed_module
    returned = parsed.arena.node(ParserSpecHelpers.function_at(parsed, 0).body).as(Smalang::ReturnNode)
    error = parsed.arena.node(returned.value).as(Smalang::ErrorNode)
    call = parsed.arena.node(error.recovered_node.not_nil!).as(Smalang::CallExpr)

    result.diagnostics.size.should eq(1)
    parsed.source_file.slice(call.callee).should eq("compute")
    call.arguments.count.should eq(1)
  end

  it "recovers from a malformed function body and parses the next function" do
    result = ParserSpecHelpers.parse("def broken() -> int:\n    41\n\ndef next() -> int:\n    return 2\n")
    parsed = result.parsed_module
    broken = ParserSpecHelpers.function_at(parsed, 0)
    later = ParserSpecHelpers.function_at(parsed, 1)

    result.diagnostics.size.should eq(1)
    parsed.arena.node(broken.body).as(Smalang::ErrorNode)
    parsed.source_file.slice(later.name).should eq("next")
  end
end
