def main() -> int:
    unsafe:
        storage: ptr[uint8] = stack_storage(8, 64)
        value_address: ptr[int] = cast[int](storage)
        store(value_address, 42)
        result: int = load(value_address)
    return result
