require "./semantic"

module Smalang
  class AstPassDiagnostic
    getter span : SourceSpan
    getter description : String

    def initialize(@span : SourceSpan, @description : String)
    end
  end

  class AstPassResult
    getter parsed_module : ParsedModule?
    getter diagnostic : AstPassDiagnostic?

    def initialize(@parsed_module : ParsedModule?, @diagnostic : AstPassDiagnostic?)
    end

    def self.success(parsed_module : ParsedModule) : AstPassResult
      new(parsed_module, nil)
    end

    def self.failure(span : SourceSpan, description : String) : AstPassResult
      new(nil, AstPassDiagnostic.new(span, description))
    end

    def success? : Bool
      !@parsed_module.nil? && @diagnostic.nil?
    end
  end

  abstract class AstPass
    abstract def label : String
    abstract def run(input : SemanticModule) : AstPassResult
  end
end
