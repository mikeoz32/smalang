def main() -> int:
    unsafe:
        left: ptr[int] = alloc_stack(10)
        right: ptr[int] = alloc_stack(20)
        initial_total: int = load(left) + load(right)
        store(left, 15)
        store(right, 27)
        final_total: int = load(left) + load(right)
    return initial_total + final_total
