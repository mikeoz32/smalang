module Smalang
  enum TokenKind : UInt8
    Def
    Return
    Match
    Case
    IntType
    UIntType
    BoolType
    Int8Type
    UInt8Type
    Int16Type
    UInt16Type
    Int32Type
    UInt32Type
    Int64Type
    UInt64Type
    Identifier
    IntegerLiteral
    TrueLiteral
    FalseLiteral
    Plus
    Minus
    LeftParen
    RightParen
    Colon
    Comma
    Arrow
    Newline
    Indent
    Dedent
    Eof
  end

  struct SourceSpan
    getter start : Int32
    getter length : Int32

    def initialize(@start : Int32, @length : Int32)
    end

    def end_offset : Int32
      @start + @length
    end
  end

  struct SourcePosition
    getter line : Int32
    getter column : Int32

    def initialize(@line : Int32, @column : Int32)
    end
  end

  struct Token
    getter kind : TokenKind
    getter span : SourceSpan

    def initialize(@kind : TokenKind, @span : SourceSpan)
    end
  end

  class SourceFile
    getter name : String
    getter source : String

    def initialize(@name : String, @source : String)
      capacity = source.bytesize // 32
      capacity = 1 if capacity < 1
      @line_start_offsets = Array(Int32).new(capacity)
      @line_start_offsets << 0
    end

    def record_line_start(offset : Int32) : Nil
      @line_start_offsets << offset
    end

    def position_at(offset : Int32) : SourcePosition
      lower = 0
      upper = @line_start_offsets.size

      while lower < upper
        middle = lower + (upper - lower) // 2
        if @line_start_offsets[middle] <= offset
          lower = middle + 1
        else
          upper = middle
        end
      end

      line_index = lower - 1
      line_start = @line_start_offsets[line_index]
      SourcePosition.new(line_index + 1, offset - line_start + 1)
    end

    def slice(span : SourceSpan) : String
      @source.byte_slice(span.start...span.end_offset)
    end
  end

  class TokenStream
    getter source_file : SourceFile
    getter tokens : Array(Token)

    def initialize(@source_file : SourceFile, @tokens : Array(Token))
    end
  end

  class LexicalError < Exception
    getter source_file : SourceFile
    getter offset : Int32
    getter position : SourcePosition
    getter description : String

    def initialize(@source_file : SourceFile, @offset : Int32, @description : String)
      @position = source_file.position_at(offset)
      super("#{source_file.name}:#{@position.line}:#{@position.column}: #{@description}")
    end
  end

  class Lexer
    def tokenize(source : String, name : String = "<memory>") : TokenStream
      Scanner.new(source, name).scan
    end
  end

  class Scanner
    INDENT_WIDTH = 4

    SPACE      =  32_u8
    TAB        =   9_u8
    LF         =  10_u8
    CR         =  13_u8
    UNDERSCORE =  95_u8
    ZERO       =  48_u8
    NINE       =  57_u8
    LOWER_A    =  97_u8
    LOWER_Z    = 122_u8
    UPPER_A    =  65_u8
    UPPER_Z    =  90_u8

    PLUS        = 43_u8
    MINUS       = 45_u8
    LEFT_PAREN  = 40_u8
    RIGHT_PAREN = 41_u8
    COLON       = 58_u8
    COMMA       = 44_u8
    GREATER     = 62_u8

    def initialize(source : String, name : String)
      @source_file = SourceFile.new(name, source)
      @bytes = source.to_slice
      capacity = source.bytesize // 4
      capacity = 1 if capacity < 1
      @tokens = Array(Token).new(capacity)
      @cursor = 0
      @indent_depth = 0
      @at_line_start = true
      @line_has_content = false
    end

    def scan : TokenStream
      while @cursor < @bytes.size
        if @at_line_start
          scan_line_start
        else
          scan_token
        end
      end

      finish
    end

    private def scan_line_start : Nil
      indentation_start = @cursor
      indentation_spaces = 0

      while current_byte == SPACE
        @cursor += 1
        indentation_spaces += 1
      end

      reject_tab if current_byte == TAB

      newline_length = line_ending_length
      if newline_length > 0
        consume_newline(false, newline_length)
        return
      end

      return unless current_byte

      if indentation_spaces % INDENT_WIDTH != 0
        error_offset = indentation_start + (indentation_spaces // INDENT_WIDTH) * INDENT_WIDTH
        raise_lexical_error(error_offset, "indentation must use multiples of four spaces")
      end

      target_depth = indentation_spaces // INDENT_WIDTH
      adjust_indentation(target_depth, @cursor)
      @at_line_start = false
    end

    private def scan_token : Nil
      byte = current_byte
      return unless byte

      case byte
      when SPACE
        @cursor += 1
      when TAB
        reject_tab
      when LF, CR
        consume_newline(true, line_ending_length)
      when PLUS
        emit_single(TokenKind::Plus)
      when MINUS
        scan_minus_or_arrow
      when LEFT_PAREN
        emit_single(TokenKind::LeftParen)
      when RIGHT_PAREN
        emit_single(TokenKind::RightParen)
      when COLON
        emit_single(TokenKind::Colon)
      when COMMA
        emit_single(TokenKind::Comma)
      else
        if identifier_start?(byte)
          scan_identifier
        elsif decimal_digit?(byte)
          scan_integer
        else
          raise_lexical_error(@cursor, "unsupported character")
        end
      end
    end

    private def scan_minus_or_arrow : Nil
      start = @cursor
      @cursor += 1

      if current_byte == GREATER
        @cursor += 1
        emit_source_token(TokenKind::Arrow, start, 2)
      else
        emit_source_token(TokenKind::Minus, start, 1)
      end
    end

    private def scan_identifier : Nil
      start = @cursor
      @cursor += 1

      while byte = current_byte
        break unless identifier_continue?(byte)
        @cursor += 1
      end

      length = @cursor - start
      emit_source_token(keyword_kind(start, length), start, length)
    end

    private def scan_integer : Nil
      start = @cursor
      @cursor += 1

      while byte = current_byte
        break unless decimal_digit?(byte)
        @cursor += 1
      end

      emit_source_token(TokenKind::IntegerLiteral, start, @cursor - start)
    end

    private def keyword_kind(start : Int32, length : Int32) : TokenKind
      case length
      when 3
        return TokenKind::Def if matches_keyword?(start, "def")
        return TokenKind::IntType if matches_keyword?(start, "int")
      when 4
        return TokenKind::Case if matches_keyword?(start, "case")
        return TokenKind::UIntType if matches_keyword?(start, "uint")
        return TokenKind::BoolType if matches_keyword?(start, "bool")
        return TokenKind::TrueLiteral if matches_keyword?(start, "true")
        return TokenKind::Int8Type if matches_keyword?(start, "int8")
      when 5
        return TokenKind::Match if matches_keyword?(start, "match")
        return TokenKind::FalseLiteral if matches_keyword?(start, "false")
        return TokenKind::UInt8Type if matches_keyword?(start, "uint8")
        return TokenKind::Int16Type if matches_keyword?(start, "int16")
        return TokenKind::Int32Type if matches_keyword?(start, "int32")
        return TokenKind::Int64Type if matches_keyword?(start, "int64")
      when 6
        return TokenKind::Return if matches_keyword?(start, "return")
        return TokenKind::UInt16Type if matches_keyword?(start, "uint16")
        return TokenKind::UInt32Type if matches_keyword?(start, "uint32")
        return TokenKind::UInt64Type if matches_keyword?(start, "uint64")
      end

      TokenKind::Identifier
    end

    private def matches_keyword?(start : Int32, keyword : String) : Bool
      keyword_bytes = keyword.to_slice
      return false unless keyword_bytes.size == @cursor - start

      index = 0
      while index < keyword_bytes.size
        return false unless @bytes[start + index] == keyword_bytes[index]
        index += 1
      end

      true
    end

    private def adjust_indentation(target_depth : Int32, offset : Int32) : Nil
      if target_depth > @indent_depth + 1
        raise_lexical_error(offset - INDENT_WIDTH, "indentation cannot skip a level")
      end

      while @indent_depth < target_depth
        @indent_depth += 1
        emit(TokenKind::Indent, offset, 0)
      end

      while @indent_depth > target_depth
        @indent_depth -= 1
        emit(TokenKind::Dedent, offset, 0)
      end
    end

    private def emit_single(kind : TokenKind) : Nil
      start = @cursor
      @cursor += 1
      emit_source_token(kind, start, 1)
    end

    private def emit_source_token(kind : TokenKind, start : Int32, length : Int32) : Nil
      emit(kind, start, length)
      @line_has_content = true
    end

    private def emit(kind : TokenKind, start : Int32, length : Int32) : Nil
      @tokens << Token.new(kind, SourceSpan.new(start, length))
    end

    private def consume_newline(emit_token : Bool, length : Int32) : Nil
      start = @cursor
      emit(TokenKind::Newline, start, length) if emit_token && @line_has_content
      @cursor += length
      @source_file.record_line_start(@cursor)
      @at_line_start = true
      @line_has_content = false
    end

    private def line_ending_length : Int32
      case current_byte
      when LF
        1
      when CR
        if peek_byte(1) == LF
          2
        else
          raise_lexical_error(@cursor, "expected LF after CR")
        end
      else
        0
      end
    end

    private def finish : TokenStream
      emit(TokenKind::Newline, @cursor, 0) if @line_has_content

      while @indent_depth > 0
        @indent_depth -= 1
        emit(TokenKind::Dedent, @cursor, 0)
      end

      emit(TokenKind::Eof, @cursor, 0)
      TokenStream.new(@source_file, @tokens)
    end

    private def current_byte : UInt8?
      return if @cursor >= @bytes.size
      @bytes[@cursor]
    end

    private def peek_byte(distance : Int32) : UInt8?
      offset = @cursor + distance
      return if offset >= @bytes.size
      @bytes[offset]
    end

    private def identifier_start?(byte : UInt8) : Bool
      byte == UNDERSCORE || lowercase_letter?(byte) || uppercase_letter?(byte)
    end

    private def identifier_continue?(byte : UInt8) : Bool
      identifier_start?(byte) || decimal_digit?(byte)
    end

    private def decimal_digit?(byte : UInt8) : Bool
      ZERO <= byte <= NINE
    end

    private def lowercase_letter?(byte : UInt8) : Bool
      LOWER_A <= byte <= LOWER_Z
    end

    private def uppercase_letter?(byte : UInt8) : Bool
      UPPER_A <= byte <= UPPER_Z
    end

    private def reject_tab : Nil
      raise_lexical_error(@cursor, "tabs are not supported")
    end

    private def raise_lexical_error(offset : Int32, description : String) : NoReturn
      raise LexicalError.new(@source_file, offset, description)
    end
  end
end
