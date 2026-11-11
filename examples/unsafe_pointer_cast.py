def main() -> int:
    unsafe:
        address: ptr[int] = alloc_stack(1)
        unsigned_address: ptr[uint] = cast[uint](address)
        store(unsigned_address, 42)
        result: int = load(address)
    return result
