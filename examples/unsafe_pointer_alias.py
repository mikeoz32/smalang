def main() -> int:
    unsafe:
        address: ptr[int] = alloc(1)
        alias: ptr[int] = address
        store(alias, 42)
        result: int = load(address)
        free(address)
    return result
