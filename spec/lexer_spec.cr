require "spec"
require "../src/smalang/lexer"

describe Smalang::Lexer do
  it "emits EOF for empty or blank-only source" do
    ["", " \n\n"].each do |source|
      stream = Smalang::Lexer.new.tokenize(source)
      stream.tokens.map(&.kind).should eq([Smalang::TokenKind::Eof])
      stream.tokens.first.span.start.should eq(source.bytesize)
    end
  end

  it "tokenizes the checked-in example" do
    source = File.read("#{__DIR__}/../examples/first_program.py")
    stream = Smalang::Lexer.new.tokenize(source, "first_program.py")

    stream.tokens.map(&.kind).should eq([
      Smalang::TokenKind::Def,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::LeftParen,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::IntType,
      Smalang::TokenKind::RightParen,
      Smalang::TokenKind::Arrow,
      Smalang::TokenKind::IntType,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Return,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::Plus,
      Smalang::TokenKind::IntegerLiteral,
      Smalang::TokenKind::Minus,
      Smalang::TokenKind::IntegerLiteral,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Dedent,
      Smalang::TokenKind::Def,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::LeftParen,
      Smalang::TokenKind::RightParen,
      Smalang::TokenKind::Arrow,
      Smalang::TokenKind::IntType,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Return,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::LeftParen,
      Smalang::TokenKind::IntegerLiteral,
      Smalang::TokenKind::RightParen,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Dedent,
      Smalang::TokenKind::Eof,
    ])
  end

  it "tokenizes the first example and keeps lexemes in source spans" do
    source = "def main() -> int:\n    return 40 + 2\n"
    stream = Smalang::Lexer.new.tokenize(source, "example.py")

    stream.tokens.map(&.kind).should eq([
      Smalang::TokenKind::Def,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::LeftParen,
      Smalang::TokenKind::RightParen,
      Smalang::TokenKind::Arrow,
      Smalang::TokenKind::IntType,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Return,
      Smalang::TokenKind::IntegerLiteral,
      Smalang::TokenKind::Plus,
      Smalang::TokenKind::IntegerLiteral,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Dedent,
      Smalang::TokenKind::Eof,
    ])

    stream.source_file.slice(stream.tokens[1].span).should eq("main")
    stream.source_file.slice(stream.tokens[10].span).should eq("40")
    stream.source_file.slice(stream.tokens[7].span).should eq("\n")
    stream.source_file.slice(stream.tokens[8].span).should eq("")
    stream.source_file.slice(stream.tokens[14].span).should eq("")
    stream.tokens[15].span.start.should eq(source.bytesize)
  end

  it "recognizes the remaining operators, types, and whole identifiers" do
    stream = Smalang::Lexer.new.tokenize(
      "def returning(value: uint, amount: int) -> uint:\n    return value - amount\n"
    )

    stream.tokens.map(&.kind).should eq([
      Smalang::TokenKind::Def,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::LeftParen,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::UIntType,
      Smalang::TokenKind::Comma,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::IntType,
      Smalang::TokenKind::RightParen,
      Smalang::TokenKind::Arrow,
      Smalang::TokenKind::UIntType,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Return,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::Minus,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Dedent,
      Smalang::TokenKind::Eof,
    ])
  end

  it "recognizes fixed-width integer type names as whole keywords" do
    stream = Smalang::Lexer.new.tokenize(
      "def values(a: int8, b: uint8, c: int16, d: uint16, e: int32, f: uint32, g: int64, h: uint64, int80: int8) -> int64:\n    return a\n"
    )

    kinds = stream.tokens.map(&.kind)
    kinds.should contain(Smalang::TokenKind::Int8Type)
    kinds.should contain(Smalang::TokenKind::UInt8Type)
    kinds.should contain(Smalang::TokenKind::Int16Type)
    kinds.should contain(Smalang::TokenKind::UInt16Type)
    kinds.should contain(Smalang::TokenKind::Int32Type)
    kinds.should contain(Smalang::TokenKind::UInt32Type)
    kinds.should contain(Smalang::TokenKind::Int64Type)
    kinds.should contain(Smalang::TokenKind::UInt64Type)

    identifiers = stream.tokens.select { |token| token.kind == Smalang::TokenKind::Identifier }
    identifiers.map { |token| stream.source_file.slice(token.span) }.should contain("int80")
  end

  it "ignores blank lines, accepts CRLF, and inserts the final newline" do
    stream = Smalang::Lexer.new.tokenize(
      "\r\n    \r\ndef main() -> int:\r\n    return 1"
    )

    stream.tokens.map(&.kind).should eq([
      Smalang::TokenKind::Def,
      Smalang::TokenKind::Identifier,
      Smalang::TokenKind::LeftParen,
      Smalang::TokenKind::RightParen,
      Smalang::TokenKind::Arrow,
      Smalang::TokenKind::IntType,
      Smalang::TokenKind::Colon,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Return,
      Smalang::TokenKind::IntegerLiteral,
      Smalang::TokenKind::Newline,
      Smalang::TokenKind::Dedent,
      Smalang::TokenKind::Eof,
    ])

    stream.source_file.slice(stream.tokens[7].span).should eq("\r\n")
    stream.source_file.slice(stream.tokens[11].span).should eq("")
  end

  it "emits one indent or dedent for each four-space level" do
    stream = Smalang::Lexer.new.tokenize(
      "def main() -> int:\n    value\n        return 1\n    return value\n"
    )

    stream.tokens.map(&.kind).select { |kind|
      kind == Smalang::TokenKind::Indent || kind == Smalang::TokenKind::Dedent
    }.should eq([
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Indent,
      Smalang::TokenKind::Dedent,
      Smalang::TokenKind::Dedent,
    ])
  end

  it "reports tabs with a source location" do
    error = expect_raises(Smalang::LexicalError) do
      Smalang::Lexer.new.tokenize("\treturn 0\n", "tab.py")
    end

    error.message.not_nil!.should contain("tab.py:1:1: tabs are not supported")

    inline_error = expect_raises(Smalang::LexicalError) do
      Smalang::Lexer.new.tokenize("def main() -> int:\n    return\t0\n", "inline-tab.py")
    end

    inline_error.message.not_nil!.should contain("inline-tab.py:2:11: tabs are not supported")
  end

  it "rejects indentation that is not a multiple of four spaces" do
    error = expect_raises(Smalang::LexicalError) do
      Smalang::Lexer.new.tokenize("def main() -> int:\n      return 0\n", "indent.py")
    end

    error.message.not_nil!.should contain("indent.py:2:5: indentation must use multiples of four spaces")
  end

  it "rejects indentation that skips a level" do
    error = expect_raises(Smalang::LexicalError) do
      Smalang::Lexer.new.tokenize("def main() -> int:\n        return 0\n", "skipped-indent.py")
    end

    error.message.not_nil!.should contain("skipped-indent.py:2:5: indentation cannot skip a level")
  end

  it "rejects unsupported characters at their source location" do
    error = expect_raises(Smalang::LexicalError) do
      Smalang::Lexer.new.tokenize("def main() -> int:\n    return # comment\n", "invalid.py")
    end

    error.message.not_nil!.should contain("invalid.py:2:12: unsupported character")
  end

  it "rejects a carriage return that is not followed by a line feed" do
    error = expect_raises(Smalang::LexicalError) do
      Smalang::Lexer.new.tokenize("return 0\rreturn 1\n", "newline.py")
    end

    error.message.not_nil!.should contain("newline.py:1:9: expected LF after CR")
  end
end
