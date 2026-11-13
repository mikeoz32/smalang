def transform(first: int, second: int, third: int, fourth: int, values: array[array[int, 2], 2], tail: int) -> array[array[int, 2], 2]:
    result: mut[array[array[int, 2], 2]] = values
    result[0][0] = first + second + third + fourth + tail
    return result

def forward(values: array[array[int, 2], 2]) -> array[array[int, 2], 2]:
    return transform(1, 2, 3, 4, values, 5)

def observe(values: array[array[int, 2], 2]) -> int:
    return values[0][0]

def combine(first: int, values: array[int, 2], second: int, third: int, fourth: int, fifth: int, sixth: int) -> int:
    return first + values[0] + second + third + fourth + fifth + sixth

def main() -> int:
    original: array[array[int, 2], 2] = [[1, 2], [3, 4]]
    changed: array[array[int, 2], 2] = forward(original)
    values: array[int, 2] = [10, 20]
    mixed_arguments: int = combine(1, values, 2, 3, 4, 5, 6)
    return observe(changed) + original[0][0] + mixed_arguments
