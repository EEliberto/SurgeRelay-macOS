import sys

def check(file_path):
    content = open(file_path).read()
    stack = []
    for i, char in enumerate(content):
        if char == '{':
            stack.append((i, content[:i].count('\n') + 1))
        elif char == '}':
            if not stack:
                c = content[:i].count('\n') + 1
                print(f"Unmatched '}}' at line {c}")
                return
            stack.pop()
    
    if stack:
        print(f"Unmatched '{{' at:")
        for _, line in stack:
            print(f"  Line {line}")
    else:
        print("Braces are balanced.")

check('/Users/allen_miao/Library/Mobile Documents/com~apple~CloudDocs/Development/Surge Relay/SurgeRelay/Views/ModulesView.swift')
