def code_for(value: bool) -> int:
    return match value:
        case true: 17
        case false: 29

def main() -> int:
    return code_for(true) + code_for(false)
