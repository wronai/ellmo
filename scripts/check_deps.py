#!/usr/bin/env python3
import sys

def check_dependencies():
    modules = ['speech_recognition', 'pyttsx3', 'requests', 'json']
    for module in modules:
        try:
            __import__(module)
            print(f'✓ {module}')
        except ImportError:
            print(f'✗ {module}')

if __name__ == '__main__':
    check_dependencies()
