require "spec"
require "../src/smalang/lexer"
require "../src/smalang/parser"
require "../src/smalang/semantic"
require "../src/smalang/ir"
require "../src/smalang/ir_lowering"
require "./backend_spec_helpers"

module MatchExpressionSpecHelpers
  def self.run(source : String, name : String = "match_expression_spec.py") : Int32
    parse_result = Smalang::Parser.new(Smalang::Lexer.new.tokenize(source, name)).parse
    parse_result.success?.should eq(true)

    semantic_result = Smalang::SemanticAnalyzer.new(parse_result.parsed_module).analyze
    semantic_result.success?.should eq(true)

    ir_result = Smalang::IrLowerer.new(semantic_result.semantic_module.not_nil!).lower
    ir_result.success?.should eq(true)

    ir = ir_result.ir_module.not_nil!
    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir)
  end

  def self.run_example(name : String) : Int32
    run(File.read("#{__DIR__}/../examples/#{name}"), name)
  end

  def self.semantic_diagnostic(source : String) : String
    parse_result = Smalang::Parser.new(Smalang::Lexer.new.tokenize(source, "match_invalid.py")).parse
    parse_result.success?.should eq(true)

    semantic_result = Smalang::SemanticAnalyzer.new(parse_result.parsed_module).analyze
    semantic_result.diagnostic.try(&.message) || ""
  end
end

describe "boolean match expression compilation" do
  it "compiles and runs the explicit True/False example" do
    MatchExpressionSpecHelpers.run_example("bool_match_explicit.py").should eq(46)
  end

  it "compiles and runs the wildcard default example" do
    MatchExpressionSpecHelpers.run_example("bool_match_default.py").should eq(17)
  end

  it "compiles nested matches, call arguments, and call results" do
    source = "def choose(value: bool) -> int:\n    return match value:\n        case True: match False:\n            case True: 1\n            case False: 2\n        case False: identity(match True:\n            case True: identity(40)\n            case False: 41\n        )\n\ndef identity(value: int) -> int:\n    return value\n\ndef main() -> int:\n    return choose(False)\n"

    MatchExpressionSpecHelpers.run(source).should eq(40)
  end

  it "passes boolean match results to a later match" do
    source = "def invert(value: bool) -> bool:\n    return match value:\n        case True: False\n        case False: True\n\ndef condition() -> bool:\n    return invert(True)\n\ndef main() -> int:\n    return match condition():\n        case True: 17\n        case False: 29\n"

    MatchExpressionSpecHelpers.run(source).should eq(29)
  end

  it "rejects non-boolean scrutinees during semantic analysis" do
    source = "def main() -> int:\n    return match 1:\n        case True: 1\n        case False: 0\n"

    diagnostic = MatchExpressionSpecHelpers.semantic_diagnostic(source)
    diagnostic.should contain("match value has type int, expected bool")
    diagnostic.should contain("match_invalid.py:2:18:")
  end

  it "rejects non-exhaustive, wildcard-only, and duplicate patterns" do
    cases = [
      {"case True: 1\n", "bool match must have exactly two cases"},
      {"case _: 1\n", "bool match must have exactly two cases"},
      {"case True: 1\n        case True: 2\n", "duplicate bool pattern True"},
      {"case False: 1\n        case False: 2\n", "duplicate bool pattern False"},
    ]

    cases.each do |case_source, expected_message|
      source = "def main() -> int:\n    return match True:\n        #{case_source}"
      MatchExpressionSpecHelpers.semantic_diagnostic(source).should contain(expected_message)
    end
  end

  it "rejects cases after a wildcard and mismatched result types" do
    after_wildcard = "def main() -> int:\n    return match True:\n        case _: 1\n        case True: 2\n"
    MatchExpressionSpecHelpers.semantic_diagnostic(after_wildcard)
      .should contain("wildcard pattern must be the final case")

    mismatched_results = "def main() -> int:\n    return match True:\n        case True: 1\n        case False: True\n"
    MatchExpressionSpecHelpers.semantic_diagnostic(mismatched_results)
      .should contain("match case has type bool, expected int")
  end
end
