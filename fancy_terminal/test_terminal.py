"""
Simple test script for the PySide6 terminal emulator.
Tests basic input/output functionality.
"""

import sys
import time

print("=" * 50)
print("PySide6 Terminal Test Script")
print("=" * 50)
print()

# Test stdout
print("This is standard output (stdout)")
print("Testing multiple lines...")
for i in range(5):
    print(f"Line {i + 1}")
    time.sleep(0.2)

print()

# Test stderr
print("Now testing stderr output...", file=sys.stderr)
sys.stderr.write("This is an error message!\n")
sys.stderr.flush()

print()

# Test input
name = input("What is your name? ")
print(f"Hello, {name}!")

age = input("How old are you? ")
print(f"You are {age} years old.")

print()

# Test long output
print("Testing long output (scroll test):")
for i in range(20):
    print(f"Long line {i + 1}: " + "x" * 80)

print()
print("Test completed successfully!")
print("You can now test the terminal features:")
print("  - Try typing commands")
print("  - Use Up/Down arrows for history")
print("  - Try Ctrl+F to search")
print("  - Try Ctrl+Scroll to zoom")
print("  - Type 'exit' to close")
print()

# Keep running for interactive testing
while True:
    try:
        user_input = input(">>> ")
        if user_input.lower() == "quit":
            break
        print(f"You entered: {user_input}")
    except EOFError:
        break

print("Goodbye!")
