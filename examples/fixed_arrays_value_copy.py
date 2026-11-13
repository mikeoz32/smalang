def main() -> int:
    original: array[int, 2] = [1, 2]
    replacement: array[int, 2] = [3, 4]
    target: mut[array[int, 2]] = original
    target = replacement
    target[0] = 42

    matrix: mut[array[array[int, 2], 2]] = [[1, 2], [3, 4]]
    row: mut[array[int, 2]] = matrix[0]
    row[0] = 42
    matrix[1] = row
    row[1] = 99

    return original[0] + replacement[0] + target[0] + matrix[1][0] + matrix[1][1] + matrix[0][0]
