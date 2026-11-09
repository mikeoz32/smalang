require "spec"
require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"
require "./backend_spec_helpers"

describe Smalang::X86_64Backend do
  it "emits a linkable object for typed IR with an internal call" do
    ir = Smalang::IrModule.new
    increment = ir.add_function(
      "increment",
      [Smalang::IrType::Isize],
      Smalang::IrType::Isize
    )
    increment_entry = increment.entry_block_id
    value = increment.parameters[0].value_id
    one = increment.emit_constant(increment_entry, Smalang::IrType::Isize, 1)
    sum = increment.emit_add(increment_entry, Smalang::IrType::Isize, value, one)
    increment.emit_return(increment_entry, sum)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    main_entry = main.entry_block_id
    argument = main.emit_constant(main_entry, Smalang::IrType::Isize, 41)
    target = ir.internal_call_target(increment.id).not_nil!
    normal = main.add_block("call_normal")
    unwind = main.add_block("call_unwind")
    result = main.emit_invoke_call(main_entry, target, [argument], normal, unwind)
    main.emit_return(normal, result.value_id)
    main.emit_resume_exception(unwind, result.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "passes bool values through calls, phi nodes, and true and false branches" do
    [0_i128, 1_i128].each do |input|
      ir = Smalang::IrModule.new
      parameter_types = Array.new(6, Smalang::IrType::Isize)
      parameter_types << Smalang::IrType::Bool
      identity = ir.add_function("identity", parameter_types, Smalang::IrType::Bool)
      identity.emit_return(identity.entry_block_id, identity.parameters.last.value_id)

      main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
      entry = main.entry_block_id
      arguments = Array(Smalang::ValueId).new
      6.times do
        arguments << main.emit_constant(entry, Smalang::IrType::Isize, 0)
      end
      flag = main.emit_constant(entry, Smalang::IrType::Bool, input)
      arguments << flag
      normal = main.add_block("normal")
      unwind = main.add_block("unwind")
      truth = main.add_block("truth")
      falsity = main.add_block("falsity")
      join = main.add_block("join")
      success = main.add_block("success")
      failure = main.add_block("failure")
      target = ir.internal_call_target(identity.id).not_nil!
      result = main.emit_invoke_call(entry, target, arguments, normal, unwind)
      main.emit_branch(normal, result.value_id, truth, falsity)
      true_value = main.emit_constant(truth, Smalang::IrType::Bool, 1)
      main.emit_jump(truth, join)
      false_value = main.emit_constant(falsity, Smalang::IrType::Bool, 0)
      main.emit_jump(falsity, join)
      merged = main.emit_phi(join, Smalang::IrType::Bool, [
        Smalang::IrPhiIncoming.new(truth, true_value),
        Smalang::IrPhiIncoming.new(falsity, false_value),
      ])
      main.emit_branch(join, merged, success, failure)
      success_value = main.emit_constant(success, Smalang::IrType::Isize, 42)
      main.emit_return(success, success_value)
      failure_value = main.emit_constant(failure, Smalang::IrType::Isize, 1)
      main.emit_return(failure, failure_value)
      main.emit_resume_exception(unwind, result.exception_id)

      expected = input == 1 ? 42 : 1
      BackendSpecHelpers.link_and_run(ir).should eq(expected)
    end
  end

  it "allocates and accesses pointer pointees using each scalar's storage width" do
    cases = [
      {Smalang::IrType::Bool, 1_i128, 0_i128, 0_u64},
      {Smalang::IrType::Int8, 42_i128, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt8, 42_i128, 255_i128, 255_u64},
      {Smalang::IrType::Int16, 42_i128, -2_i128, UInt64::MAX - 1_u64},
      {Smalang::IrType::UInt16, 42_i128, 65_535_i128, 65_535_u64},
      {Smalang::IrType::Int32, 42_i128, -3_i128, UInt64::MAX - 2_u64},
      {Smalang::IrType::UInt32, 42_i128, 4_294_967_295_i128, 4_294_967_295_u64},
      {Smalang::IrType::Int64, 42_i128, -4_i128, UInt64::MAX - 3_u64},
      {Smalang::IrType::UInt64, 42_i128, UInt64::MAX.to_i128, UInt64::MAX},
    ]

    cases.each do |type, initial_value, stored_value, expected_value|
      ir = Smalang::IrModule.new
      main = ir.add_function("main", Array(Smalang::IrType).new, type)
      entry = main.entry_block_id
      allocated = main.add_block("allocated")
      failed = main.add_block("failed")
      pointer_type = Smalang::IrPointerType.new(type)
      initial = main.emit_constant(entry, type, initial_value)
      allocation = main.emit_invoke_allocate(entry, initial, pointer_type, allocated, failed)
      replacement = main.emit_constant(allocated, type, stored_value)
      main.emit_store(allocated, allocation.value_id, replacement, pointer_type)
      loaded = main.emit_load(allocated, allocation.value_id, pointer_type)
      main.emit_free(allocated, allocation.value_id, pointer_type)
      main.emit_return(allocated, loaded)
      main.emit_resume_exception(failed, allocation.exception_id)

      ir.verify.should be_empty
      BackendSpecHelpers.link_and_compare_full_width_result(ir, expected_value).should eq(0)
    end
  end

  it "emits 64-bit subtraction" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    fifty = function.emit_constant(entry, Smalang::IrType::Isize, 50)
    eight = function.emit_constant(entry, Smalang::IrType::Isize, 8)
    difference = function.emit_subtract(entry, Smalang::IrType::Isize, fifty, eight)
    function.emit_return(entry, difference)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "emits 64-bit multiplication" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    six = function.emit_constant(entry, Smalang::IrType::Isize, 6)
    seven = function.emit_constant(entry, Smalang::IrType::Isize, 7)
    product = function.emit_multiply(entry, Smalang::IrType::Isize, six, seven)
    function.emit_return(entry, product)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "wraps fixed-width addition at the declared width" do
    cases = [
      {Smalang::IrType::Int8, 127_i128, 1_i128, 0xffff_ffff_ffff_ff80_u64},
      {Smalang::IrType::UInt8, 255_i128, 1_i128, 0_u64},
      {Smalang::IrType::Int16, 32_767_i128, 1_i128, 0xffff_ffff_ffff_8000_u64},
      {Smalang::IrType::UInt16, 65_535_i128, 1_i128, 0_u64},
      {Smalang::IrType::Int32, 2_147_483_647_i128, 1_i128, 0xffff_ffff_8000_0000_u64},
      {Smalang::IrType::UInt32, 4_294_967_295_i128, 1_i128, 0_u64},
      {Smalang::IrType::Int64, Int64::MAX.to_i128, 1_i128, 0x8000_0000_0000_0000_u64},
      {Smalang::IrType::UInt64, UInt64::MAX.to_i128, 1_i128, 0_u64},
    ]

    cases.each do |type, left_value, right_value, expected|
      BackendSpecHelpers.link_binary_and_compare_full_width_result(type, left_value, right_value, expected) do |function, entry, left, right|
        function.emit_add(entry, type, left, right)
      end.should eq(0)
    end
  end

  it "wraps fixed-width subtraction at the declared width" do
    cases = [
      {Smalang::IrType::Int8, -128_i128, 1_i128, 127_u64},
      {Smalang::IrType::UInt8, 0_i128, 1_i128, 255_u64},
      {Smalang::IrType::Int16, -32_768_i128, 1_i128, 32_767_u64},
      {Smalang::IrType::UInt16, 0_i128, 1_i128, 65_535_u64},
      {Smalang::IrType::Int32, -2_147_483_648_i128, 1_i128, 2_147_483_647_u64},
      {Smalang::IrType::UInt32, 0_i128, 1_i128, 4_294_967_295_u64},
      {Smalang::IrType::Int64, Int64::MIN.to_i128, 1_i128, Int64::MAX.to_u64},
      {Smalang::IrType::UInt64, 0_i128, 1_i128, UInt64::MAX},
    ]

    cases.each do |type, left_value, right_value, expected|
      BackendSpecHelpers.link_binary_and_compare_full_width_result(type, left_value, right_value, expected) do |function, entry, left, right|
        function.emit_subtract(entry, type, left, right)
      end.should eq(0)
    end
  end

  it "wraps fixed-width multiplication at the declared width" do
    cases = [
      {Smalang::IrType::Int8, 64_i128, 2_i128, 0xffff_ffff_ffff_ff80_u64},
      {Smalang::IrType::UInt8, 128_i128, 2_i128, 0_u64},
      {Smalang::IrType::Int16, 16_384_i128, 2_i128, 0xffff_ffff_ffff_8000_u64},
      {Smalang::IrType::UInt16, 32_768_i128, 2_i128, 0_u64},
      {Smalang::IrType::Int32, 1_073_741_824_i128, 2_i128, 0xffff_ffff_8000_0000_u64},
      {Smalang::IrType::UInt32, 2_147_483_648_i128, 2_i128, 0_u64},
      {Smalang::IrType::Int64, 4_611_686_018_427_387_904_i128, 2_i128, 0x8000_0000_0000_0000_u64},
      {Smalang::IrType::UInt64, 9_223_372_036_854_775_808_i128, 2_i128, 0_u64},
    ]

    cases.each do |type, left_value, right_value, expected|
      BackendSpecHelpers.link_binary_and_compare_full_width_result(type, left_value, right_value, expected) do |function, entry, left, right|
        function.emit_multiply(entry, type, left, right)
      end.should eq(0)
    end
  end

  it "passes canonical fixed-width values through stack arguments, calls, and returns" do
    cases = [
      {Smalang::IrType::Int8, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt8, 255_i128, 255_u64},
      {Smalang::IrType::Int16, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt16, 65_535_i128, 65_535_u64},
      {Smalang::IrType::Int32, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt32, 4_294_967_295_i128, 4_294_967_295_u64},
      {Smalang::IrType::Int64, -1_i128, UInt64::MAX},
      {Smalang::IrType::UInt64, UInt64::MAX.to_i128, UInt64::MAX},
    ]

    cases.each do |type, value, expected|
      parameter_types = Array.new(6, Smalang::IrType::Isize)
      parameter_types << type
      ir = Smalang::IrModule.new
      callee = ir.add_function("identity", parameter_types, type)
      callee.emit_return(callee.entry_block_id, callee.parameters.last.value_id)

      main = ir.add_function("main", Array(Smalang::IrType).new, type)
      entry = main.entry_block_id
      arguments = Array(Smalang::ValueId).new
      6.times { arguments << main.emit_constant(entry, Smalang::IrType::Isize, 0) }
      arguments << main.emit_constant(entry, type, value)
      normal = main.add_block("normal")
      unwind = main.add_block("unwind")
      target = ir.internal_call_target(callee.id).not_nil!
      result = main.emit_invoke_call(entry, target, arguments, normal, unwind)
      main.emit_return(normal, result.value_id)
      main.emit_resume_exception(unwind, result.exception_id)

      BackendSpecHelpers.link_and_compare_full_width_result(ir, expected).should eq(0)
    end
  end

  it "emits fixed-width signed and unsigned division" do
    cases = [
      {Smalang::IrType::Int8, -23_i128, 5_i128, 0xffff_ffff_ffff_fffc_u64},
      {Smalang::IrType::Int8, -128_i128, -1_i128, 0xffff_ffff_ffff_ff80_u64},
      {Smalang::IrType::UInt8, 255_i128, 2_i128, 127_u64},
      {Smalang::IrType::Int16, -32_768_i128, -1_i128, 0xffff_ffff_ffff_8000_u64},
      {Smalang::IrType::UInt16, 65_535_i128, 2_i128, 32_767_u64},
      {Smalang::IrType::Int32, -2_147_483_648_i128, -1_i128, 0xffff_ffff_8000_0000_u64},
      {Smalang::IrType::UInt32, 4_294_967_295_i128, 2_i128, 2_147_483_647_u64},
      {Smalang::IrType::Int64, Int64::MIN.to_i128, -1_i128, 0x8000_0000_0000_0000_u64},
      {Smalang::IrType::UInt64, UInt64::MAX.to_i128, 2_i128, 9_223_372_036_854_775_807_u64},
    ]

    cases.each do |type, left, right, expected|
      BackendSpecHelpers.link_invoke_binary_and_compare_full_width_result(type, left, right, expected) do |function, entry, dividend, divisor, normal, unwind|
        function.emit_invoke_divide(entry, type, dividend, divisor, normal, unwind)
      end.should eq(0)
    end
  end

  it "emits fixed-width signed and unsigned remainder" do
    cases = [
      {Smalang::IrType::Int8, -23_i128, 5_i128, 0xffff_ffff_ffff_fffd_u64},
      {Smalang::IrType::Int8, -128_i128, -1_i128, 0_u64},
      {Smalang::IrType::UInt8, 255_i128, 2_i128, 1_u64},
      {Smalang::IrType::Int16, -32_768_i128, -1_i128, 0_u64},
      {Smalang::IrType::UInt16, 65_535_i128, 2_i128, 1_u64},
      {Smalang::IrType::Int32, -2_147_483_648_i128, -1_i128, 0_u64},
      {Smalang::IrType::UInt32, 4_294_967_295_i128, 2_i128, 1_u64},
      {Smalang::IrType::Int64, Int64::MIN.to_i128, -1_i128, 0_u64},
      {Smalang::IrType::UInt64, UInt64::MAX.to_i128, 2_i128, 1_u64},
    ]

    cases.each do |type, dividend, divisor, expected|
      BackendSpecHelpers.link_invoke_binary_and_compare_full_width_result(type, dividend, divisor, expected) do |function, entry, dividend, divisor, normal, unwind|
        function.emit_invoke_remainder(entry, type, dividend, divisor, normal, unwind)
      end.should eq(0)
    end
  end

  it "branches on fixed-width zero and nonzero values" do
    [
      {Smalang::IrType::Int8, 0_i128, 1},
      {Smalang::IrType::UInt32, 1_i128, 42},
    ].each do |type, condition_value, expected|
      ir = Smalang::IrModule.new
      function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
      entry = function.entry_block_id
      truth = function.add_block("truth")
      falsity = function.add_block("falsity")
      condition = function.emit_constant(entry, type, condition_value)
      function.emit_branch(entry, condition, truth, falsity)
      true_value = function.emit_constant(truth, Smalang::IrType::Isize, 42)
      function.emit_return(truth, true_value)
      false_value = function.emit_constant(falsity, Smalang::IrType::Isize, 1)
      function.emit_return(falsity, false_value)

      BackendSpecHelpers.link_and_run(ir).should eq(expected)
    end
  end

  it "preserves an int8 phi value from the taken branch" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Int8)
    entry = function.entry_block_id
    negative = function.add_block("negative")
    positive = function.add_block("positive")
    join = function.add_block("join")
    condition = function.emit_constant(entry, Smalang::IrType::Int8, 1)
    function.emit_branch(entry, condition, negative, positive)
    negative_value = function.emit_constant(negative, Smalang::IrType::Int8, -1)
    function.emit_jump(negative, join)
    positive_value = function.emit_constant(positive, Smalang::IrType::Int8, 1)
    function.emit_jump(positive, join)
    merged = function.emit_phi(join, Smalang::IrType::Int8, [
      Smalang::IrPhiIncoming.new(negative, negative_value),
      Smalang::IrPhiIncoming.new(positive, positive_value),
    ])
    function.emit_return(join, merged)

    BackendSpecHelpers.link_and_compare_full_width_result(ir, UInt64::MAX).should eq(0)
  end

  it "raises and catches division by zero for fixed-width integer types" do
    [Smalang::IrType::Int8, Smalang::IrType::UInt64].each do |type|
      ir = Smalang::IrModule.new
      function = ir.add_function("main", Array(Smalang::IrType).new, type)
      entry = function.entry_block_id
      normal = function.add_block("normal")
      dispatch = function.add_block("dispatch")
      caught = function.add_block("caught")
      resume = function.add_block("resume")
      value = function.emit_constant(entry, type, 10)
      zero = function.emit_constant(entry, type, 0)
      result = function.emit_invoke_divide(entry, type, value, zero, normal, dispatch)
      function.emit_return(normal, result.value_id)
      function.emit_exception_dispatch(dispatch, result.exception_id, [
        Smalang::IrExceptionCase.new(Smalang::IrExceptionKind::DivisionByZero, caught),
      ], resume)
      function.emit_exception_release(caught, result.exception_id)
      recovered = function.emit_constant(caught, type, 42)
      function.emit_return(caught, recovered)
      function.emit_resume_exception(resume, result.exception_id)

      BackendSpecHelpers.link_and_compare_full_width_result(ir, 42_u64).should eq(0)
    end
  end

  it "emits conditional control flow and merges values through phi" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    left = function.add_block("left")
    right = function.add_block("right")
    join = function.add_block("join")
    condition = function.emit_constant(entry, Smalang::IrType::Isize, 0)
    function.emit_branch(entry, condition, left, right)
    left_value = function.emit_constant(left, Smalang::IrType::Isize, 11)
    function.emit_jump(left, join)
    right_value = function.emit_constant(right, Smalang::IrType::Isize, 42)
    function.emit_jump(right, join)
    merged = function.emit_phi(join, Smalang::IrType::Isize, [
      Smalang::IrPhiIncoming.new(left, left_value),
      Smalang::IrPhiIncoming.new(right, right_value),
    ])
    function.emit_return(join, merged)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "emits DWARF call frame information for generated functions" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    value = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, 42)
    function.emit_return(function.entry_block_id, value)
    object_path = File.join(Dir.tempdir, "smalang-eh-frame-#{Process.pid}.o")

    begin
      object_bytes = Smalang::X86_64Backend.new.emit(ir)
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run("readelf", ["--debug-dump=frames", object_path], output: output, error: error)

      status.success?.should eq(true)
      output.to_s.should contain("CIE")
      output.to_s.should contain("FDE")
      output.to_s.should contain("DW_CFA_def_cfa: r7 (rsp) ofs 8")
      output.to_s.should contain("DW_CFA_def_cfa_register: r6 (rbp)")
      output.to_s.should contain("DW_CFA_def_cfa_offset: 8")

      relocation_output = IO::Memory.new
      relocation_error = IO::Memory.new
      relocation_status = Process.run("readelf", ["-r", object_path], output: relocation_output, error: relocation_error)
      relocation_status.success?.should eq(true)
      relocation_output.to_s.should contain(".rela.eh_frame")
      relocation_output.to_s.should contain("R_X86_64_PC32")
    ensure
      File.delete(object_path) if File.exists?(object_path)
    end
  end

  it "preserves the full 64-bit multiplication result" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    left = function.emit_constant(entry, Smalang::IrType::Isize, 4_294_967_297_i64)
    right = function.emit_constant(entry, Smalang::IrType::Isize, 4_294_967_297_i64)
    product = function.emit_multiply(entry, Smalang::IrType::Isize, left, right)
    function.emit_return(entry, product)

    BackendSpecHelpers.link_and_compare_full_width_result(ir, 8_589_934_593_u64).should eq(0)
  end

  it "wraps signed runtime addition at 64 bits" do
    BackendSpecHelpers.link_binary_and_compare_full_width_result(
      Smalang::IrType::Isize,
      Int64::MAX,
      1_i64,
      0x8000_0000_0000_0000_u64
    ) do |function, entry, left, right|
      function.emit_add(entry, Smalang::IrType::Isize, left, right)
    end.should eq(0)
  end

  it "wraps signed runtime subtraction at 64 bits" do
    BackendSpecHelpers.link_binary_and_compare_full_width_result(
      Smalang::IrType::Isize,
      Int64::MIN,
      1_i64,
      0x7fff_ffff_ffff_ffff_u64
    ) do |function, entry, left, right|
      function.emit_subtract(entry, Smalang::IrType::Isize, left, right)
    end.should eq(0)
  end

  it "wraps signed runtime multiplication at 64 bits" do
    BackendSpecHelpers.link_binary_and_compare_full_width_result(
      Smalang::IrType::Isize,
      Int64::MAX,
      2_i64,
      0xffff_ffff_ffff_fffe_u64
    ) do |function, entry, left, right|
      function.emit_multiply(entry, Smalang::IrType::Isize, left, right)
    end.should eq(0)
  end

  it "wraps unsigned runtime addition at 64 bits" do
    BackendSpecHelpers.link_binary_and_compare_full_width_result(
      Smalang::IrType::Usize,
      UInt64::MAX.to_i128,
      1_i128,
      0_u64
    ) do |function, entry, left, right|
      function.emit_add(entry, Smalang::IrType::Usize, left, right)
    end.should eq(0)
  end

  it "wraps unsigned runtime subtraction at 64 bits" do
    BackendSpecHelpers.link_binary_and_compare_full_width_result(
      Smalang::IrType::Usize,
      0_i64,
      1_i64,
      UInt64::MAX
    ) do |function, entry, left, right|
      function.emit_subtract(entry, Smalang::IrType::Usize, left, right)
    end.should eq(0)
  end

  it "wraps unsigned runtime multiplication at 64 bits" do
    BackendSpecHelpers.link_binary_and_compare_full_width_result(
      Smalang::IrType::Usize,
      9_223_372_036_854_775_808_i128,
      2_i128,
      0_u64
    ) do |function, entry, left, right|
      function.emit_multiply(entry, Smalang::IrType::Usize, left, right)
    end.should eq(0)
  end

  it "preserves signed overflow results under register pressure" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    values = [] of Smalang::ValueId
    values << function.emit_constant(entry, Smalang::IrType::Isize, Int64::MAX)
    values << function.emit_constant(entry, Smalang::IrType::Isize, 2)
    (1..10).each do |value|
      values << function.emit_constant(entry, Smalang::IrType::Isize, value)
    end

    product = function.emit_multiply(entry, Smalang::IrType::Isize, values[0], values[1])
    retained_values = values[2, values.size - 2]
    increased = retained_values.reduce(product) do |result, value|
      function.emit_add(entry, Smalang::IrType::Isize, result, value)
    end
    restored = retained_values.reduce(increased) do |result, value|
      function.emit_subtract(entry, Smalang::IrType::Isize, result, value)
    end
    function.emit_return(entry, restored)

    BackendSpecHelpers.link_and_compare_full_width_result(ir, 0xffff_ffff_ffff_fffe_u64).should eq(0)
  end

  it "multiplies a value spilled under register pressure" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    values = (1..10).map do |value|
      function.emit_constant(entry, Smalang::IrType::Isize, value)
    end
    product = function.emit_multiply(entry, Smalang::IrType::Isize, values.first, values.last)
    result = values.reduce(product) do |sum, value|
      function.emit_add(entry, Smalang::IrType::Isize, sum, value)
    end
    function.emit_return(entry, result)

    BackendSpecHelpers.link_and_run(ir).should eq(65)
  end

  it "preserves signed 64-bit constants" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    negative = function.emit_constant(function.entry_block_id, Smalang::IrType::Isize, -42)
    function.emit_return(function.entry_block_id, negative)

    BackendSpecHelpers.link_and_run(ir).should eq(214)
  end

  it "preserves values that remain live across a call" do
    ir = Smalang::IrModule.new
    increment = ir.add_function("increment", [Smalang::IrType::Isize], Smalang::IrType::Isize)
    increment_entry = increment.entry_block_id
    one = increment.emit_constant(increment_entry, Smalang::IrType::Isize, 1)
    incremented = increment.emit_add(increment_entry, Smalang::IrType::Isize, increment.parameters[0].value_id, one)
    increment.emit_return(increment_entry, incremented)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    live_value = main.emit_constant(entry, Smalang::IrType::Isize, 40)
    argument = main.emit_constant(entry, Smalang::IrType::Isize, 1)
    target = ir.internal_call_target(increment.id).not_nil!
    normal = main.add_block("call_normal")
    unwind = main.add_block("call_unwind")
    call_result = main.emit_invoke_call(entry, target, [argument], normal, unwind)
    result = main.emit_add(normal, Smalang::IrType::Isize, live_value, call_result.value_id)
    main.emit_return(normal, result)
    main.emit_resume_exception(unwind, call_result.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "spills values when register pressure exceeds the available registers" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = function.entry_block_id
    values = (1..12).map do |value|
      function.emit_constant(entry, Smalang::IrType::Isize, value)
    end
    result = values.first
    values.each_with_index do |value, index|
      next if index == 0
      result = function.emit_add(entry, Smalang::IrType::Isize, result, value)
    end
    function.emit_return(entry, result)

    BackendSpecHelpers.link_and_run(ir).should eq(78)
  end

  it "passes integer arguments beyond the six ABI registers on the stack" do
    ir = Smalang::IrModule.new
    parameter_types = Array.new(7, Smalang::IrType::Isize)
    sum_function = ir.add_function("sum_seven", parameter_types, Smalang::IrType::Isize)
    sum_entry = sum_function.entry_block_id
    parameters = sum_function.parameters
    result = parameters.first.value_id
    parameters.each_with_index do |parameter, index|
      next if index == 0
      result = sum_function.emit_add(sum_entry, Smalang::IrType::Isize, result, parameter.value_id)
    end
    sum_function.emit_return(sum_entry, result)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    main_entry = main.entry_block_id
    arguments = (1..7).map do |value|
      main.emit_constant(main_entry, Smalang::IrType::Isize, value)
    end
    target = ir.internal_call_target(sum_function.id).not_nil!
    normal = main.add_block("call_normal")
    unwind = main.add_block("call_unwind")
    sum = main.emit_invoke_call(main_entry, target, arguments, normal, unwind)
    main.emit_return(normal, sum.value_id)
    main.emit_resume_exception(unwind, sum.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(28)
  end

  it "rejects invalid IR before emitting an object" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    unsigned = function.emit_constant(function.entry_block_id, Smalang::IrType::Usize, 1)
    function.emit_return(function.entry_block_id, unsigned)

    expect_raises(Smalang::X86_64BackendFailure, /cannot emit invalid IR/) do
      Smalang::X86_64Backend.new.emit(ir)
    end
  end

  it "rejects constants outside the target integer width" do
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Usize)
    negative = function.emit_constant(function.entry_block_id, Smalang::IrType::Usize, -1)
    function.emit_return(function.entry_block_id, negative)

    expect_raises(Smalang::X86_64BackendFailure, /does not fit usize on x86_64/) do
      Smalang::X86_64Backend.new.emit(ir)
    end
  end
end
