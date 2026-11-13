def next_index(counter: ptr[uint]) -> uint:
    unsafe:
        value: uint = load(counter)
        store(counter, value + 1)
    return value

def rhs(counter: ptr[uint]) -> int:
    unsafe:
        value: uint = load(counter)
        store(counter, value + 1)
    return 42

def main() -> int:
    unsafe:
        counter: ptr[uint] = alloc(0)
    matrix: mut[array[array[int, 3], 2]] = [[1, 2, 3], [4, 5, 6]]
    matrix[next_index(counter)][next_index(counter)] = rhs(counter)
    unsafe:
        count: int = load(cast[int](counter))
        free(counter)
    return matrix[1][2] + count
