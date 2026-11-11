def main() -> int:
    bytes: uint = 13
    unsafe:
        first: ptr[uint8] = heap_storage(bytes, 8192)
        first_value: ptr[int] = cast[int](first)
        store(first_value, 42)
        first_result: int = load(first_value)
        heap_free(first, bytes, 8192)

        second: ptr[uint8] = heap_storage(8, 8)
        second_value: ptr[int] = cast[int](second)
        store(second_value, first_result)
        result: int = load(second_value)
        heap_free(second, 8, 8)
    return result
