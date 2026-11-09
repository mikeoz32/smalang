def allocate(value: int) -> ptr[int]:
    unsafe:
        address: ptr[int] = alloc(value)
    return address

def increment(address: ptr[int]) -> ptr[int]:
    unsafe:
        current: int = load(address)
        updated: int = current + 1
        store(address, updated)
    return address

def read_and_free(address: ptr[int]) -> int:
    unsafe:
        value: int = load(address)
        free(address)
    return value

def main() -> int:
    address: ptr[int] = allocate(41)
    updated_address: ptr[int] = increment(address)
    return read_and_free(updated_address)
