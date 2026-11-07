require "./ir"

module Smalang
  enum MatchDiagnosticKind : UInt8
    ScrutineeCount
    ScrutineeType
    UndefinedScrutinee
    ScrutineeUnavailable
    UnknownSourceBlock
    SourceJoinAlias
    SourceTerminated
    UnknownJoinBlock
    JoinBlockNotEmpty
    NonExhaustive
    ClauseCount
    PatternArity
    UnsupportedPattern
    DuplicateTruePattern
    DuplicateFalsePattern
    DuplicateBodyBlock
    UnexpectedBodyPredecessor
    BodyBlockAlias
    UnknownBodyBlock
    BodyDoesNotJumpToJoin
    UnexpectedJoinPredecessor
    ResultTypeMismatch
    UndefinedResult
    ResultUnavailable
    InvalidPatternValue
  end

  abstract class MatchPattern
    def boolean_literal_value : Bool?
      nil
    end
  end

  class BooleanLiteralPattern < MatchPattern
    getter value : Bool

    def initialize(@value : Bool)
    end

    def boolean_literal_value : Bool?
      @value
    end
  end

  class MatchClause
    @patterns : Array(MatchPattern)

    getter body_block_id : BlockId
    getter result_value_id : ValueId

    def initialize(patterns : Array(T), @body_block_id : BlockId, @result_value_id : ValueId) forall T
      @patterns = patterns.map do |pattern|
        pattern.as?(MatchPattern) || raise MatchLoweringFailure.new(
          MatchDiagnosticKind::InvalidPatternValue,
          "Match clause contains a value that is not a pattern"
        )
      end
    end

    def patterns : Array(MatchPattern)
      @patterns.dup
    end
  end

  class MatchExpression
    @scrutinee_ids : Array(ValueId)
    @clauses : Array(MatchClause)

    getter result_type : IrType

    def initialize(scrutinee_ids : Array(ValueId), @result_type : IrType, clauses : Array(MatchClause))
      @scrutinee_ids = scrutinee_ids.dup
      @clauses = clauses.dup
    end

    def scrutinee_ids : Array(ValueId)
      @scrutinee_ids.dup
    end

    def clauses : Array(MatchClause)
      @clauses.dup
    end
  end

  class MatchLoweringFailure < Exception
    getter kind : MatchDiagnosticKind

    def initialize(@kind : MatchDiagnosticKind, message : String)
      super(message)
    end
  end

  class MatchLowerer
    def lower(
      function : IrFunction,
      source_block_id : BlockId,
      join_block_id : BlockId,
      expression : MatchExpression,
    ) : ValueId
      true_clause, false_clause = validate(function, source_block_id, join_block_id, expression)
      condition_id = expression.scrutinee_ids.first

      function.emit_branch(
        source_block_id,
        condition_id,
        true_clause.body_block_id,
        false_clause.body_block_id
      )

      function.emit_phi(join_block_id, expression.result_type, [
        IrPhiIncoming.new(true_clause.body_block_id, true_clause.result_value_id),
        IrPhiIncoming.new(false_clause.body_block_id, false_clause.result_value_id),
      ])
    end

    private def validate(
      function : IrFunction,
      source_block_id : BlockId,
      join_block_id : BlockId,
      expression : MatchExpression,
    ) : Tuple(MatchClause, MatchClause)
      scrutinees = expression.scrutinee_ids
      condition_id = validate_scrutinee(function, scrutinees)
      validate_source_block(function, source_block_id, join_block_id)
      unless value_available_at_block_end?(function, condition_id, source_block_id)
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::ScrutineeUnavailable,
          "Match scrutinee does not dominate the source block"
        )
      end
      validate_join_block(function, join_block_id)

      true_clause, false_clause = validate_bool_clauses(scrutinees, expression.clauses)
      validate_body_blocks(function, source_block_id, join_block_id, true_clause, false_clause)
      validate_join_predecessors(function, join_block_id, true_clause, false_clause)
      validate_result_values(function, source_block_id, expression, true_clause, false_clause)

      {true_clause, false_clause}
    end

    private def validate_scrutinee(function : IrFunction, scrutinees : Array(ValueId)) : ValueId
      unless scrutinees.size == 1
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::ScrutineeCount,
          "current Match lowerer supports one bool scrutinee"
        )
      end

      scrutinee_id = scrutinees.first
      actual_type = function.value_type(scrutinee_id)
      unless actual_type
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::UndefinedScrutinee,
          "bool match scrutinee %v#{scrutinee_id} is not defined"
        )
      end
      unless actual_type == IrType::Bool
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::ScrutineeType,
          "bool match scrutinee has type #{actual_type.label}"
        )
      end

      scrutinee_id
    end

    private def validate_source_block(function : IrFunction, source_block_id : BlockId, join_block_id : BlockId) : Nil
      source_block = function.block(source_block_id)
      unless source_block
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::UnknownSourceBlock,
          "unknown Match source block #{source_block_id}"
        )
      end
      if source_block_id == join_block_id
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::SourceJoinAlias,
          "Match source and join blocks must be distinct"
        )
      end
      unless source_block.instruction_ids.all? { |instruction_id| !function.instruction(instruction_id).try(&.terminator?) }
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::SourceTerminated,
          "Match source block is already terminated"
        )
      end
    end

    private def validate_join_block(function : IrFunction, join_block_id : BlockId) : Nil
      join_block = function.block(join_block_id)
      unless join_block
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::UnknownJoinBlock,
          "unknown Match join block #{join_block_id}"
        )
      end
      unless join_block.instruction_ids.empty?
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::JoinBlockNotEmpty,
          "Match join block must be empty before lowering"
        )
      end
    end

    private def validate_bool_clauses(
      scrutinees : Array(ValueId),
      clauses : Array(MatchClause),
    ) : Tuple(MatchClause, MatchClause)
      if clauses.size < 2
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::NonExhaustive,
          "bool match must cover both true and false"
        )
      elsif clauses.size > 2
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::ClauseCount,
          "bool match has #{clauses.size} clauses; expected exactly 2"
        )
      end

      true_clause : MatchClause? = nil
      false_clause : MatchClause? = nil
      clauses.each do |clause|
        validate_clause_arity(clause, scrutinees.size)
        case clause.patterns.first.boolean_literal_value
        when true
          true_clause = unique_clause(true_clause, clause, MatchDiagnosticKind::DuplicateTruePattern, "duplicate bool pattern true")
        when false
          false_clause = unique_clause(false_clause, clause, MatchDiagnosticKind::DuplicateFalsePattern, "duplicate bool pattern false")
        else
          raise MatchLoweringFailure.new(
            MatchDiagnosticKind::UnsupportedPattern,
            "current Match lowerer supports bool literal patterns only"
          )
        end
      end

      true_case = true_clause
      false_case = false_clause
      unless true_case && false_case
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::NonExhaustive,
          "bool match must cover both true and false"
        )
      end

      {true_case, false_case}
    end

    private def validate_clause_arity(clause : MatchClause, scrutinee_count : Int32) : Nil
      return if clause.patterns.size == scrutinee_count
      raise MatchLoweringFailure.new(
        MatchDiagnosticKind::PatternArity,
        "Match clause pattern count does not match scrutinee count"
      )
    end

    private def unique_clause(
      previous_clause : MatchClause?,
      clause : MatchClause,
      diagnostic_kind : MatchDiagnosticKind,
      description : String,
    ) : MatchClause
      raise MatchLoweringFailure.new(diagnostic_kind, description) if previous_clause
      clause
    end

    private def validate_body_blocks(
      function : IrFunction,
      source_block_id : BlockId,
      join_block_id : BlockId,
      true_clause : MatchClause,
      false_clause : MatchClause,
    ) : Nil
      body_block_ids = [true_clause.body_block_id, false_clause.body_block_id]
      if body_block_ids.uniq.size != body_block_ids.size
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::DuplicateBodyBlock,
          "bool match clauses must have distinct body blocks"
        )
      end

      body_block_ids.each do |block_id|
        validate_body_block(function, block_id, source_block_id, join_block_id)
      end
    end

    private def validate_body_block(
      function : IrFunction,
      block_id : BlockId,
      source_block_id : BlockId,
      join_block_id : BlockId,
    ) : Nil
      if block_id == source_block_id || block_id == join_block_id
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::BodyBlockAlias,
          "Match body block cannot be the source or join block"
        )
      end

      body_block = function.block(block_id)
      unless body_block
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::UnknownBodyBlock,
          "unknown Match body block #{block_id}"
        )
      end
      unless predecessor_block_ids(function, block_id).empty?
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::UnexpectedBodyPredecessor,
          "Match body block has a predecessor outside the Match source"
        )
      end

      terminator = body_block.instruction_ids.last?.try { |instruction_id| function.instruction(instruction_id) }
      unless terminator.is_a?(IrJumpInstruction) && terminator.target_block_id == join_block_id
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::BodyDoesNotJumpToJoin,
          "Match body block must jump to the join block"
        )
      end
    end

    private def validate_join_predecessors(
      function : IrFunction,
      join_block_id : BlockId,
      true_clause : MatchClause,
      false_clause : MatchClause,
    ) : Nil
      expected_predecessors = [true_clause.body_block_id, false_clause.body_block_id].sort
      return if predecessor_block_ids(function, join_block_id).sort == expected_predecessors
      raise MatchLoweringFailure.new(
        MatchDiagnosticKind::UnexpectedJoinPredecessor,
        "Match join block has predecessors outside the Match clauses"
      )
    end

    private def validate_result_values(
      function : IrFunction,
      source_block_id : BlockId,
      expression : MatchExpression,
      true_clause : MatchClause,
      false_clause : MatchClause,
    ) : Nil
      [true_clause, false_clause].each do |clause|
        validate_result_value(function, source_block_id, expression.result_type, clause)
      end
    end

    private def validate_result_value(
      function : IrFunction,
      source_block_id : BlockId,
      expected_type : IrType,
      clause : MatchClause,
    ) : Nil
      result_type = function.value_type(clause.result_value_id)
      unless result_type
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::UndefinedResult,
          "Match result %v#{clause.result_value_id} is not defined"
        )
      end
      unless result_type == expected_type
        raise MatchLoweringFailure.new(
          MatchDiagnosticKind::ResultTypeMismatch,
          "Match result has type #{result_type.label}, expected #{expected_type.label}"
        )
      end

      return if value_available_on_match_body_edge?(function, clause.result_value_id, source_block_id, clause.body_block_id)
      raise MatchLoweringFailure.new(
        MatchDiagnosticKind::ResultUnavailable,
        "Match result does not dominate its body block"
      )
    end

    private def predecessor_block_ids(function : IrFunction, target_block_id : BlockId) : Array(BlockId)
      predecessors = [] of BlockId
      function.each_block do |block|
        instruction_id = block.instruction_ids.last?
        next unless instruction_id

        instruction = function.instruction(instruction_id)
        next unless instruction && instruction.successor_block_ids.includes?(target_block_id)
        predecessors << block.id
      end
      predecessors
    end

    private def value_available_at_block_end?(
      function : IrFunction,
      value_id : ValueId,
      use_block_id : BlockId,
    ) : Bool
      definition = function.value_info(value_id)
      return false unless definition
      defining_block_id = definition.defining_block_id
      return false unless defining_block_id

      if definition.edge_defined?
        edge_source_block_id = definition.edge_source_block_id.not_nil!
        definition_predecessors = predecessor_block_ids(function, defining_block_id)
        unless definition_predecessors.size == 1 && definition_predecessors.first == edge_source_block_id
          return false
        end
      end

      unless block_dominates?(function, defining_block_id, use_block_id)
        return false
      end

      return true if definition.edge_defined? || defining_block_id != use_block_id || definition.defining_instruction_id.nil?

      definition_instruction_id = definition.defining_instruction_id
      return false unless definition_instruction_id
      use_block = function.block(use_block_id)
      return false unless use_block
      definition_index = use_block.instruction_ids.index(definition_instruction_id)
      !definition_index.nil? && definition_index < use_block.instruction_ids.size
    end

    private def value_available_on_match_body_edge?(
      function : IrFunction,
      value_id : ValueId,
      source_block_id : BlockId,
      body_block_id : BlockId,
    ) : Bool
      definition = function.value_info(value_id)
      return false unless definition
      return value_available_at_block_end?(function, value_id, body_block_id) if definition.defining_block_id == body_block_id

      value_available_at_block_end?(function, value_id, source_block_id)
    end

    private def block_dominates?(function : IrFunction, definition_block_id : BlockId, use_block_id : BlockId) : Bool
      return false unless function.block(definition_block_id) && function.block(use_block_id)
      return true if definition_block_id == use_block_id
      return false unless reachable_from_entry?(function, use_block_id)
      !reachable_from_entry?(function, use_block_id, definition_block_id)
    end

    private def reachable_from_entry?(function : IrFunction, target_block_id : BlockId, skipped_block_id : BlockId? = nil) : Bool
      entry_block_id = function.entry_block_id
      return false if entry_block_id == skipped_block_id

      reachable_block_ids = [entry_block_id]
      index = 0
      while index < reachable_block_ids.size
        block_id = reachable_block_ids[index]
        index += 1
        return true if block_id == target_block_id

        block = function.block(block_id)
        next unless block
        instruction_id = block.instruction_ids.last?
        next unless instruction_id
        instruction = function.instruction(instruction_id)
        next unless instruction

        instruction.successor_block_ids.each do |successor_block_id|
          next if successor_block_id == skipped_block_id
          next unless function.block(successor_block_id)
          reachable_block_ids << successor_block_id unless reachable_block_ids.includes?(successor_block_id)
        end
      end

      false
    end
  end
end
