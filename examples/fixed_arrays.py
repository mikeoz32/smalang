def update_first(values: mut[array[int, 3]], replacement: int) -> array[int, 3]:
    values[0] = replacement
    return values

def lookup(values: array[int, 3], index: uint) -> int:
    return values[index]

def main() -> int:
    original: array[int, 3] = [10, 20, 30]
    copied: array[int, 3] = update_first(original, 42)
    matrix: array[array[int, 2], 2] = [[1, 2], [3, 4]]
    return lookup(original, 0) + lookup(copied, 0) + matrix[1][1]
