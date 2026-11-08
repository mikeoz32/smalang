require "spec"
require "../src/smalang/ir"
require "../src/smalang/match_core"
require "./backend_spec_helpers"

class UnsupportedMatchPattern < Smalang::MatchPattern
end

class MatchCoreFixture
  getter ir : Smalang::IrModule
  getter function : Smalang::IrFunction
  getter entry : Smalang::BlockId
  getter truth : Smalang::BlockId
  getter falsity : Smalang::BlockId
  getter join : Smalang::BlockId
  getter true_result : Smalang::ValueId
  getter false_result : Smalang::ValueId
  getter scrutinees : Array(Smalang::ValueId)

  @result_type : Smalang::IrType

  def initialize(
    parameter_types : Array(Smalang::IrType) = Array(Smalang::IrType).new,
    @result_type : Smalang::IrType = Smalang::IrType::Isize,
    condition_value : Bool = true,
  )
    @ir = Smalang::IrModule.new
    @function = @ir.add_function("main", parameter_types, @result_type)
    @entry = @function.entry_block_id
    @scrutinees = @function.parameters.map(&.value_id)
    if @scrutinees.empty?
      @scrutinees << @function.emit_constant(@entry, Smalang::IrType::Bool, condition_value ? 1 : 0)
    end

    @truth = @function.add_block("truth")
    @falsity = @function.add_block("falsity")
    @join = @function.add_block("join")
    @true_result = @function.emit_constant(@truth, @result_type, @result_type == Smalang::IrType::Bool ? 1 : 42)
    @false_result = @function.emit_constant(@falsity, @result_type, @result_type == Smalang::IrType::Bool ? 0 : 7)
    @function.emit_jump(@truth, @join)
    @function.emit_jump(@falsity, @join)
  end

  def expression(
    scrutinees : Array(Smalang::ValueId)? = nil,
    result_type : Smalang::IrType = @result_type,
    clauses : Array(Smalang::MatchClause)? = nil,
  ) : Smalang::MatchExpression
    Smalang::MatchExpression.new(scrutinees || @scrutinees, result_type, clauses || default_clauses)
  end

  def default_clauses : Array(Smalang::MatchClause)
    [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], @truth, @true_result),
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(false)], @falsity, @false_result),
    ] of Smalang::MatchClause
  end
end

module MatchCoreSpecHelpers
  def self.expect_failure(
    fixture : MatchCoreFixture,
    expression : Smalang::MatchExpression,
    kind : Smalang::MatchDiagnosticKind,
    message : String,
    source_block_id : Smalang::BlockId? = nil,
    join_block_id : Smalang::BlockId? = nil,
  ) : Nil
    instruction_count = fixture.function.instruction_count
    value_count = fixture.function.value_count
    block_count = fixture.function.block_count

    begin
      Smalang::MatchLowerer.new.lower(
        fixture.function,
        source_block_id || fixture.entry,
        join_block_id || fixture.join,
        expression
      )
    rescue error : Smalang::MatchLoweringFailure
      error.kind.should eq(kind)
      error.message.not_nil!.should eq(message)
      fixture.function.instruction_count.should eq(instruction_count)
      fixture.function.value_count.should eq(value_count)
      fixture.function.block_count.should eq(block_count)
      return
    end

    fail "expected MatchLoweringFailure with #{kind}"
  end
end

describe Smalang::MatchLowerer do
  it "retains ordered scrutinees and per-clause pattern bundles" do
    expression = Smalang::MatchExpression.new(
      [3, 5],
      Smalang::IrType::Isize,
      [Smalang::MatchClause.new([
        Smalang::BooleanLiteralPattern.new(true),
        Smalang::BooleanLiteralPattern.new(false),
      ], 7, 11)]
    )

    expression.scrutinee_ids.should eq([3, 5])
    expression.clauses.first.patterns.map(&.boolean_literal_value).should eq([true, false])
  end

  it "selects true and false cases independently of clause order" do
    [
      {true, 42},
      {false, 7},
    ].each do |condition, expected|
      fixture = MatchCoreFixture.new(condition_value: condition)
      clauses = fixture.default_clauses.reverse
      expression = fixture.expression(clauses: clauses)

      result = Smalang::MatchLowerer.new.lower(fixture.function, fixture.entry, fixture.join, expression)
      fixture.function.emit_return(fixture.join, result)

      fixture.ir.verify.should be_empty
      BackendSpecHelpers.link_and_run(fixture.ir).should eq(expected)
    end
  end

  it "lowers a final wildcard to the missing boolean outcome" do
    [
      {true, 42},
      {false, 7},
    ].each do |condition, expected|
      fixture = MatchCoreFixture.new(condition_value: condition)
      true_clause = fixture.default_clauses.first
      false_clause = fixture.default_clauses.last
      clauses = [
        true_clause,
        Smalang::MatchClause.new(
          [Smalang::WildcardPattern.new],
          false_clause.body_block_id,
          false_clause.result_value_id
        ),
      ] of Smalang::MatchClause

      result = Smalang::MatchLowerer.new.lower(
        fixture.function,
        fixture.entry,
        fixture.join,
        fixture.expression(clauses: clauses)
      )
      fixture.function.emit_return(fixture.join, result)

      fixture.ir.verify.should be_empty
      BackendSpecHelpers.link_and_run(fixture.ir).should eq(expected)
    end
  end

  it "accepts false followed by a wildcard as exhaustive" do
    fixture = MatchCoreFixture.new(condition_value: true)
    true_clause = fixture.default_clauses.first
    false_clause = fixture.default_clauses.last
    clauses = [
      false_clause,
      Smalang::MatchClause.new(
        [Smalang::WildcardPattern.new],
        true_clause.body_block_id,
        true_clause.result_value_id
      ),
    ] of Smalang::MatchClause

    result = Smalang::MatchLowerer.new.lower(
      fixture.function,
      fixture.entry,
      fixture.join,
      fixture.expression(clauses: clauses)
    )
    fixture.function.emit_return(fixture.join, result)

    fixture.ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(fixture.ir).should eq(42)
  end

  it "matches a bool parameter passed through a function call" do
    ir = Smalang::IrModule.new
    choose = ir.add_function("choose", [Smalang::IrType::Bool], Smalang::IrType::Isize)
    truth = choose.add_block("truth")
    falsity = choose.add_block("falsity")
    join = choose.add_block("join")
    true_result = choose.emit_constant(truth, Smalang::IrType::Isize, 42)
    false_result = choose.emit_constant(falsity, Smalang::IrType::Isize, 7)
    choose.emit_jump(truth, join)
    choose.emit_jump(falsity, join)
    expression = Smalang::MatchExpression.new(
      [choose.parameters.first.value_id],
      Smalang::IrType::Isize,
      [
        Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(false)], falsity, false_result),
        Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], truth, true_result),
      ]
    )
    result = Smalang::MatchLowerer.new.lower(choose, choose.entry_block_id, join, expression)
    choose.emit_return(join, result)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    argument = main.emit_constant(main.entry_block_id, Smalang::IrType::Bool, 0)
    normal = main.add_block("normal")
    unwind = main.add_block("unwind")
    target = ir.internal_call_target(choose.id).not_nil!
    call = main.emit_invoke_call(main.entry_block_id, target, [argument], normal, unwind)
    main.emit_return(normal, call.value_id)
    main.emit_resume_exception(unwind, call.exception_id)

    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(7)
  end

  it "accepts an entry-defined scrutinee that dominates a nested source block" do
    fixture = MatchCoreFixture.new(condition_value: false)
    source = fixture.function.add_block("nested_source")
    fixture.function.emit_jump(fixture.entry, source)
    expression = fixture.expression

    result = Smalang::MatchLowerer.new.lower(fixture.function, source, fixture.join, expression)
    fixture.function.emit_return(fixture.join, result)

    fixture.ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(fixture.ir).should eq(7)
  end

  it "preserves bool results through phi" do
    fixture = MatchCoreFixture.new(result_type: Smalang::IrType::Bool)
    result = Smalang::MatchLowerer.new.lower(
      fixture.function,
      fixture.entry,
      fixture.join,
      fixture.expression
    )

    fixture.function.value_type(result).should eq(Smalang::IrType::Bool)
    fixture.function.emit_return(fixture.join, result)
    fixture.ir.verify.should be_empty
  end

  it "rejects an empty scrutinee bundle" do
    fixture = MatchCoreFixture.new
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression([] of Smalang::ValueId),
      Smalang::MatchDiagnosticKind::ScrutineeCount,
      "current Match lowerer supports one bool scrutinee"
    )
  end

  it "rejects more than one scrutinee" do
    fixture = MatchCoreFixture.new([Smalang::IrType::Bool, Smalang::IrType::Bool])
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::ScrutineeCount,
      "current Match lowerer supports one bool scrutinee"
    )
  end

  it "rejects a non-bool scrutinee with its type in the diagnostic" do
    fixture = MatchCoreFixture.new([Smalang::IrType::Isize])
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::ScrutineeType,
      "bool match scrutinee has type isize"
    )
  end

  it "rejects an undefined scrutinee explicitly" do
    fixture = MatchCoreFixture.new
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression([99]),
      Smalang::MatchDiagnosticKind::UndefinedScrutinee,
      "bool match scrutinee %v99 is not defined"
    )
  end

  it "rejects a defined scrutinee that does not dominate the source block" do
    fixture = MatchCoreFixture.new
    unrelated = fixture.function.add_block("unrelated")
    unavailable_scrutinee = fixture.function.emit_constant(unrelated, Smalang::IrType::Bool, 1)
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression([unavailable_scrutinee]),
      Smalang::MatchDiagnosticKind::ScrutineeUnavailable,
      "Match scrutinee does not dominate the source block"
    )
  end

  it "rejects an entry value when the source block is unreachable" do
    fixture = MatchCoreFixture.new
    unreachable_source = fixture.function.add_block("unreachable_source")
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::ScrutineeUnavailable,
      "Match scrutinee does not dominate the source block",
      unreachable_source
    )
  end

  it "rejects an unknown source block" do
    fixture = MatchCoreFixture.new
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::UnknownSourceBlock,
      "unknown Match source block -1",
      -1
    )
  end

  it "rejects using the join block as the source" do
    fixture = MatchCoreFixture.new
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::SourceJoinAlias,
      "Match source and join blocks must be distinct",
      fixture.join,
      fixture.join
    )
  end

  it "rejects a source block that is already terminated" do
    fixture = MatchCoreFixture.new
    fixture.function.emit_return(fixture.entry, fixture.true_result)
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::SourceTerminated,
      "Match source block is already terminated"
    )
  end

  it "rejects an unknown join block" do
    fixture = MatchCoreFixture.new
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::UnknownJoinBlock,
      "unknown Match join block -1",
      join_block_id: -1
    )
  end

  it "rejects a non-empty join block" do
    fixture = MatchCoreFixture.new
    fixture.function.emit_constant(fixture.join, Smalang::IrType::Isize, 1)
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::JoinBlockNotEmpty,
      "Match join block must be empty before lowering"
    )
  end

  it "reports non-exhaustive matches" do
    fixture = MatchCoreFixture.new
    [
      fixture.default_clauses.first,
      fixture.default_clauses.last,
    ].each do |only_clause|
      MatchCoreSpecHelpers.expect_failure(
        fixture,
        fixture.expression(clauses: [only_clause]),
        Smalang::MatchDiagnosticKind::NonExhaustive,
        "bool match must cover both true and false"
      )
    end
  end

  it "rejects too many clauses" do
    fixture = MatchCoreFixture.new
    clauses = fixture.default_clauses + [fixture.default_clauses.first]
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::ClauseCount,
      "bool match has 3 clauses; expected exactly 2"
    )
  end

  it "rejects patterns whose arity differs from the scrutinee bundle" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new(Array(Smalang::MatchPattern).new, fixture.truth, fixture.true_result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::PatternArity,
      "Match clause pattern count does not match scrutinee count"
    )
  end

  it "rejects pattern arrays with too many patterns" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new([
        Smalang::BooleanLiteralPattern.new(true),
        Smalang::BooleanLiteralPattern.new(false),
      ], fixture.truth, fixture.true_result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::PatternArity,
      "Match clause pattern count does not match scrutinee count"
    )
  end

  it "rejects unsupported pattern kinds" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new([UnsupportedMatchPattern.new], fixture.truth, fixture.true_result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::UnsupportedPattern,
      "current Match lowerer supports bool literal and wildcard patterns only"
    )
  end

  it "rejects values that are not MatchPattern instances at construction" do
    fixture = MatchCoreFixture.new
    error = expect_raises(Smalang::MatchLoweringFailure) do
      Smalang::MatchClause.new(["not a pattern"], fixture.truth, fixture.true_result)
    end

    error.kind.should eq(Smalang::MatchDiagnosticKind::InvalidPatternValue)
    error.message.not_nil!.should eq("Match clause contains a value that is not a pattern")
  end

  it "reports duplicate true patterns" do
    fixture = MatchCoreFixture.new
    clauses = [
      fixture.default_clauses.first,
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], fixture.falsity, fixture.false_result),
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::DuplicateTruePattern,
      "duplicate bool pattern true"
    )
  end

  it "reports duplicate false patterns" do
    fixture = MatchCoreFixture.new
    clauses = [
      fixture.default_clauses.last,
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(false)], fixture.truth, fixture.true_result),
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::DuplicateFalsePattern,
      "duplicate bool pattern false"
    )
  end

  it "rejects clauses that share one body block" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], fixture.truth, fixture.true_result),
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(false)], fixture.truth, fixture.false_result),
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::DuplicateBodyBlock,
      "bool match clauses must have distinct body blocks"
    )
  end

  it "rejects a body block that aliases the source" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], fixture.entry, fixture.true_result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyBlockAlias,
      "Match body block cannot be the source or join block"
    )
  end

  it "rejects a body block that aliases the join" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], fixture.join, fixture.true_result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyBlockAlias,
      "Match body block cannot be the source or join block"
    )
  end

  it "rejects an unknown body block" do
    fixture = MatchCoreFixture.new
    clauses = [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], -1, fixture.true_result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::UnknownBodyBlock,
      "unknown Match body block -1"
    )
  end

  it "rejects a body block that does not jump to the join" do
    fixture = MatchCoreFixture.new
    wrong_join = fixture.function.add_block("wrong_join")
    invalid_body = fixture.function.add_block("invalid_body")
    result = fixture.function.emit_constant(invalid_body, Smalang::IrType::Isize, 5)
    fixture.function.emit_jump(invalid_body, wrong_join)
    clauses = [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], invalid_body, result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyDoesNotJumpToJoin,
      "Match body block must jump to the join block"
    )
  end

  it "rejects an unterminated body block" do
    fixture = MatchCoreFixture.new
    invalid_body = fixture.function.add_block("invalid_body")
    result = fixture.function.emit_constant(invalid_body, Smalang::IrType::Isize, 5)
    clauses = [
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(true)], invalid_body, result),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyDoesNotJumpToJoin,
      "Match body block must jump to the join block"
    )
  end

  it "rejects a join predecessor outside the Match clauses" do
    fixture = MatchCoreFixture.new
    extra_predecessor = fixture.function.add_block("extra_predecessor")
    fixture.function.emit_jump(extra_predecessor, fixture.join)
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::UnexpectedJoinPredecessor,
      "Match join block has predecessors outside the Match clauses"
    )
  end

  it "rejects an external predecessor to a Match body block" do
    fixture = MatchCoreFixture.new
    extra_predecessor = fixture.function.add_block("extra_predecessor")
    fixture.function.emit_jump(extra_predecessor, fixture.truth)
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression,
      Smalang::MatchDiagnosticKind::UnexpectedBodyPredecessor,
      "Match body block has a predecessor outside the Match source"
    )
  end

  it "rejects a result block outside its case body region" do
    fixture = MatchCoreFixture.new
    detached_result_block = fixture.function.add_block("detached_result")
    result = fixture.function.emit_constant(detached_result_block, Smalang::IrType::Isize, 5)
    fixture.function.emit_jump(detached_result_block, fixture.join)
    clauses = [
      Smalang::MatchClause.new(
        [Smalang::BooleanLiteralPattern.new(true)],
        fixture.truth,
        result,
        detached_result_block
      ),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause

    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyDoesNotJumpToJoin,
      "Match result block must be reachable from its case body"
    )
  end

  it "rejects an external predecessor inside a Match case body region" do
    fixture = MatchCoreFixture.new
    case_entry = fixture.function.add_block("case_entry")
    result_block = fixture.function.add_block("case_result")
    external_predecessor = fixture.function.add_block("external_predecessor")
    fixture.function.emit_jump(case_entry, result_block)
    result = fixture.function.emit_constant(result_block, Smalang::IrType::Isize, 5)
    fixture.function.emit_jump(result_block, fixture.join)
    fixture.function.emit_jump(external_predecessor, result_block)
    clauses = [
      Smalang::MatchClause.new(
        [Smalang::BooleanLiteralPattern.new(true)],
        case_entry,
        result,
        result_block
      ),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause

    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::UnexpectedBodyPredecessor,
      "Match body block has a predecessor outside its case body"
    )
  end

  it "rejects an unknown successor inside a Match case body region" do
    fixture = MatchCoreFixture.new
    case_entry = fixture.function.add_block("case_entry")
    result_block = fixture.function.add_block("case_result")
    unknown_block = fixture.function.block_count + 1
    condition = fixture.scrutinees.first
    fixture.function.emit_branch(case_entry, condition, unknown_block, result_block)
    result = fixture.function.emit_constant(result_block, Smalang::IrType::Isize, 5)
    fixture.function.emit_jump(result_block, fixture.join)
    clauses = [
      Smalang::MatchClause.new(
        [Smalang::BooleanLiteralPattern.new(true)],
        case_entry,
        result,
        result_block
      ),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause

    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::UnknownBodyBlock,
      "unknown Match body block #{unknown_block}"
    )
  end

  it "rejects a case body that re-enters the Match source block" do
    fixture = MatchCoreFixture.new
    case_entry = fixture.function.add_block("case_entry")
    result_block = fixture.function.add_block("case_result")
    condition = fixture.scrutinees.first
    fixture.function.emit_branch(case_entry, condition, fixture.entry, result_block)
    result = fixture.function.emit_constant(result_block, Smalang::IrType::Isize, 5)
    fixture.function.emit_jump(result_block, fixture.join)
    clauses = [
      Smalang::MatchClause.new(
        [Smalang::BooleanLiteralPattern.new(true)],
        case_entry,
        result,
        result_block
      ),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause

    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyBlockAlias,
      "Match body region cannot re-enter the source block"
    )
  end

  it "rejects an unterminated block inside a Match case body region" do
    fixture = MatchCoreFixture.new
    case_entry = fixture.function.add_block("case_entry")
    result_block = fixture.function.add_block("case_result")
    unterminated_block = fixture.function.add_block("unterminated_case_path")
    condition = fixture.scrutinees.first
    fixture.function.emit_branch(case_entry, condition, unterminated_block, result_block)
    result = fixture.function.emit_constant(result_block, Smalang::IrType::Isize, 5)
    fixture.function.emit_jump(result_block, fixture.join)
    clauses = [
      Smalang::MatchClause.new(
        [Smalang::BooleanLiteralPattern.new(true)],
        case_entry,
        result,
        result_block
      ),
      fixture.default_clauses.last,
    ] of Smalang::MatchClause

    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::BodyDoesNotJumpToJoin,
      "Match body block must jump to the join block"
    )
  end

  it "rejects mismatched result types" do
    fixture = MatchCoreFixture.new
    wrong_type_result = fixture.function.emit_constant(fixture.entry, Smalang::IrType::Usize, 7)
    clauses = [
      fixture.default_clauses.first,
      Smalang::MatchClause.new(
        [Smalang::BooleanLiteralPattern.new(false)],
        fixture.falsity,
        wrong_type_result
      ),
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::ResultTypeMismatch,
      "Match result has type usize, expected isize"
    )
  end

  it "rejects an undefined result value" do
    fixture = MatchCoreFixture.new
    clauses = [
      fixture.default_clauses.first,
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(false)], fixture.falsity, 999),
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::UndefinedResult,
      "Match result %v999 is not defined"
    )
  end

  it "rejects a result value defined outside the entry, source, and body blocks" do
    fixture = MatchCoreFixture.new
    unrelated = fixture.function.add_block("unrelated")
    unavailable_result = fixture.function.emit_constant(unrelated, Smalang::IrType::Isize, 8)
    clauses = [
      fixture.default_clauses.first,
      Smalang::MatchClause.new([Smalang::BooleanLiteralPattern.new(false)], fixture.falsity, unavailable_result),
    ] of Smalang::MatchClause
    MatchCoreSpecHelpers.expect_failure(
      fixture,
      fixture.expression(clauses: clauses),
      Smalang::MatchDiagnosticKind::ResultUnavailable,
      "Match result does not dominate its body block"
    )
  end
end
