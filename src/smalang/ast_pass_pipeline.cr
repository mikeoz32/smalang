require "./ast_pass"

module Smalang
  class AstPassPipelineResult
    getter semantic_module : SemanticModule?
    getter diagnostic : AstPassDiagnostic?

    def initialize(@semantic_module : SemanticModule?, @diagnostic : AstPassDiagnostic?)
    end

    def self.success(semantic_module : SemanticModule) : AstPassPipelineResult
      new(semantic_module, nil)
    end

    def self.failure(span : SourceSpan, description : String) : AstPassPipelineResult
      new(nil, AstPassDiagnostic.new(span, description))
    end

    def success? : Bool
      !@semantic_module.nil? && @diagnostic.nil?
    end
  end

  class AstPassPipeline
    @passes : Array(AstPass)

    def initialize(passes : Array(AstPass))
      @passes = passes.dup
    end

    def run(input : SemanticModule) : AstPassPipelineResult
      current = input
      @passes.each do |pass|
        pass_result = pass.run(current)
        if diagnostic = pass_result.diagnostic
          return AstPassPipelineResult.new(nil, diagnostic)
        end

        parsed_module = pass_result.parsed_module
        unless parsed_module
          span = current.parsed_module.arena.node(current.parsed_module.root_id).span
          return AstPassPipelineResult.failure(span, "#{pass.label} did not produce an AST")
        end

        semantic_result = SemanticAnalyzer.new(parsed_module).analyze
        unless semantic_module = semantic_result.semantic_module
          diagnostic = semantic_result.diagnostic
          span = diagnostic.try(&.span) || parsed_module.arena.node(parsed_module.root_id).span
          description = diagnostic.try(&.description) || "generated AST failed semantic analysis"
          return AstPassPipelineResult.failure(span, "#{pass.label} generated invalid AST: #{description}")
        end

        current = semantic_module
      end

      AstPassPipelineResult.success(current)
    end
  end
end
