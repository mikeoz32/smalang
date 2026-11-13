def identity(values: array[int, 0]) -> array[int, 0]:
    return values

def nested_identity(values: array[array[int, 0], 2]) -> array[array[int, 0], 2]:
    return values

def consume(values: array[array[int, 0], 2]) -> int:
    return 42

def main() -> int:
    empty: array[int, 0] = []
    returned: array[int, 0] = identity(empty)
    nested: array[array[int, 0], 2] = [[], []]
    nested_returned: array[array[int, 0], 2] = nested_identity(nested)
    copied: array[array[int, 0], 2] = nested_returned
    return consume(copied)
