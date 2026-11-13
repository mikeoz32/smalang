def read(index: uint) -> int:
    values: array[int, 2] = [10, 20]
    return values[index]

def main() -> int:
    return read(18446744073709551615)
