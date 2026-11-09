def allocate(value: int) -> ptr[int]:
    unsafe:
        address: ptr[int] = alloc(value)
    return address

def read_and_free(address: ptr[int]) -> int:
    unsafe:
        value: int = load(address)
        free(address)
    return value

def bool_as_int(value: bool) -> int:
    return match value:
        case True: 1
        case False: 0

def ignore_byte(value: int8) -> int:
    return 0

def main() -> int:
    address: ptr[int] = allocate(41)
    unsafe:
        store(address, 42)
        flag_address: ptr[bool] = alloc(True)
        store(flag_address, False)
        flag: bool = load(flag_address)
        free(flag_address)
        byte_address: ptr[int8] = alloc(1)
        store(byte_address, 127)
        byte: int8 = load(byte_address)
        free(byte_address)
    value: int = read_and_free(address)
    return value + bool_as_int(flag) + ignore_byte(byte)
