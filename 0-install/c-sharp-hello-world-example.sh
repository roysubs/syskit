#!/bin/bash
# Author: Roy Wiseman 2025-02
# Ensure the script is run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

PROJECT_DIR="HelloWorldConsole"
dotnet new console -o "$PROJECT_DIR" --framework net8.0
cd "$PROJECT_DIR" || exit

dotnet run

# Overwrite Program.cs with a simple Hello World
cat > Program.cs << 'EOF'
using System;

class Program
{
    static void Main(string[] args)
    {
        Console.WriteLine("Hello, World!");
    }
}
EOF

# Build and run the application
dotnet run

