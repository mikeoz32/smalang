def main() -> int:
    unsafe:
        source_storage: ptr[uint8] = stack_storage(size_of(int), align_of(int))
        destination_storage: ptr[uint8] = stack_storage(size_of(int), align_of(int))
        source: ptr[int] = cast[int](source_storage)
        destination: ptr[int] = cast[int](destination_storage)
        store(source, 42)
        copy_memory(destination_storage, source_storage, size_of(int))
        result: int = load(destination)
    return result
