def update_parameter(value: int) -> int:
    unsafe:
        address: ptr[int] = address_of(value)
        store(address, value + 1)
        updated: int = value
    return updated

def mutate(address: ptr[int]) -> int:
    unsafe:
        store(address, 73)
        updated: int = load(address)
    return updated

def main() -> int:
    value: mut[int] = 40
    unsafe:
        address: ptr[int] = address_of(value)
        store(address, 41)
        after_pointer_write: int = value
        value = 42
        after_binding_write: int = load(address)
        mutated_value: int = mutate(address)
        parameter_value: int = update_parameter(value)
        storage: ptr[uint8] = stack_storage(size_of(ptr[int]), align_of(ptr[bool]))
        typed_storage: ptr[int] = cast[int](storage)
        store(typed_storage, after_pointer_write)
        storage_value: int = load(typed_storage)
        result: int = storage_value + after_binding_write + mutated_value + parameter_value
    return result
