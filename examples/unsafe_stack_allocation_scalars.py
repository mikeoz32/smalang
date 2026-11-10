def round_trip_bool(initial: bool, replacement: bool) -> bool:
    unsafe:
        address: ptr[bool] = alloc_stack(initial)
        store(address, replacement)
        result: bool = load(address)
    return result

def round_trip_int(initial: int, replacement: int) -> int:
    unsafe:
        address: ptr[int] = alloc_stack(initial)
        store(address, replacement)
        result: int = load(address)
    return result

def round_trip_uint(initial: uint, replacement: uint) -> uint:
    unsafe:
        address: ptr[uint] = alloc_stack(initial)
        store(address, replacement)
        result: uint = load(address)
    return result

def round_trip_int8(initial: int8, replacement: int8) -> int8:
    unsafe:
        address: ptr[int8] = alloc_stack(initial)
        store(address, replacement)
        result: int8 = load(address)
    return result

def round_trip_uint8(initial: uint8, replacement: uint8) -> uint8:
    unsafe:
        address: ptr[uint8] = alloc_stack(initial)
        store(address, replacement)
        result: uint8 = load(address)
    return result

def round_trip_int16(initial: int16, replacement: int16) -> int16:
    unsafe:
        address: ptr[int16] = alloc_stack(initial)
        store(address, replacement)
        result: int16 = load(address)
    return result

def round_trip_uint16(initial: uint16, replacement: uint16) -> uint16:
    unsafe:
        address: ptr[uint16] = alloc_stack(initial)
        store(address, replacement)
        result: uint16 = load(address)
    return result

def round_trip_int32(initial: int32, replacement: int32) -> int32:
    unsafe:
        address: ptr[int32] = alloc_stack(initial)
        store(address, replacement)
        result: int32 = load(address)
    return result

def round_trip_uint32(initial: uint32, replacement: uint32) -> uint32:
    unsafe:
        address: ptr[uint32] = alloc_stack(initial)
        store(address, replacement)
        result: uint32 = load(address)
    return result

def round_trip_int64(initial: int64, replacement: int64) -> int64:
    unsafe:
        address: ptr[int64] = alloc_stack(initial)
        store(address, replacement)
        result: int64 = load(address)
    return result

def round_trip_uint64(initial: uint64, replacement: uint64) -> uint64:
    unsafe:
        address: ptr[uint64] = alloc_stack(initial)
        store(address, replacement)
        result: uint64 = load(address)
    return result

def main() -> int:
    unsafe:
        flag: bool = round_trip_bool(False, True)
        signed: int = round_trip_int(40, 42)
        unsigned: uint = round_trip_uint(10, 11)
        byte: int8 = round_trip_int8(10, 11)
        unsigned_byte: uint8 = round_trip_uint8(10, 11)
        half: int16 = round_trip_int16(10, 11)
        unsigned_half: uint16 = round_trip_uint16(10, 11)
        word: int32 = round_trip_int32(10, 11)
        unsigned_word: uint32 = round_trip_uint32(10, 11)
        wide: int64 = round_trip_int64(10, 11)
        unsigned_wide: uint64 = round_trip_uint64(10, 11)
    return match flag:
        case True: signed
        case False: 0
