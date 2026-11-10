def accept(address: ptr[int]) -> int:
    return 1

def main() -> int:
    unsafe:
        first: ptr[int] = alloc_stack(41)
        same: ptr[int] = offset(first, 0)
        value: int = load(same)
        one_past: ptr[int] = offset(first, 1)
    return value + accept(one_past)
