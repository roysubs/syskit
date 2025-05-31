#!/bin/bash
# Author: Roy Wiseman 2025-02

set -e
echo "This script will step through the installation of various package managers."
echo "- yarn (JS)"
echo "- For pipx, we create a Python virtual environment in the user's home directory (isolated from system Python)"
echo "- pipx (Isolated Python tools)"
echo "- cargo (Rust)"
echo "- Composer (PHP)"
echo "- Maven (Java)"
echo "- Gradle (Java)"
echo "- CPAN (Perl)"
echo "- Homebrew (Linuxbrew)"
echo "- Miniconda (Python/R)"
echo "- cabal (Haskell)"
echo "- Go (Golang)"
echo
read -p "Would you like to continue? [Y/n] " choice
[[ "$choice" =~ ^[Yy]$ ]] || { echo "Exiting."; exit 1; }

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if [ -e /var/cache/apt/pkgcache.bin ]; then
    if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then
        sudo apt update && sudo apt upgrade -y
    fi
else
    echo "Cache file not found, running update anyway..."
    sudo apt update && sudo apt upgrade -y
fi

confirm() {
    read -p "Install $1? [Y/n] " choice
    case "$choice" in
        n|N ) return 1 ;;
        * ) return 0 ;;
    esac
}

# Node.js & npm
echo -e "\033[1;33m\n### 💻 Node.js & npm\033[0m"
if confirm "Node.js and npm"; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
fi

# yarn (JS)
echo -e "\033[1;33m\n### 🧶 Yarn (JS)\033[0m"
if confirm "Yarn (JS)"; then
    sudo npm install -g yarn
fi

# For pipx, we create a Python virtual environment in the user's home directory (isolated from system Python)
create_python_venv() {
    VENV_DIR="$HOME/.local/python_env"
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating Python virtual environment at $VENV_DIR..."
        python3 -m venv "$VENV_DIR"
        echo "Virtual environment created! To activate it, run: source $VENV_DIR/bin/activate"
    else
        echo "Python virtual environment already exists at $VENV_DIR."
    fi
}
# Activate virtual environment
activate_venv() {
    source "$HOME/.local/python_env/bin/activate"
}
# pipx (Isolated Python tools)
echo -e "\033[1;33m\n### 🐍 pipx (Isolated Python CLI tools)\033[0m"
if confirm "pipx (Isolated Python CLI tools)"; then
    echo "Step 1: Create and activate virtual environment"
    create_python_venv
    activate_venv

    echo "Step 2: Ensure pip is up-to-date in the virtual environment"
    pip install --upgrade pip

    echo "Step 3: Install pipx inside the virtual environment"
    pip install pipx

    echo "Step 4: Add pipx to the path"
    pipx ensurepath

    echo "pipx has been installed in your virtual environment. To use it, activate the environment first by running: source $HOME/.local/python_env/bin/activate"
    echo "You can also add 'source $HOME/.local/python_env/bin/activate' to your ~/.bashrc for automatic activation on terminal start."

    echo "You may need to restart your terminal or run 'source ~/.profile'"

    # Inform user about venv and pipx
    echo -e "\n### What is a virtual environment (venv)?"
    echo "A virtual environment is a self-contained directory where Python projects can have their own dependencies, independent of system-wide packages."
    echo "This ensures that different projects can use different versions of Python packages without interfering with each other."
    echo "For example, you can install `pipx` here to manage isolated Python CLI tools."

    echo -e "\n### How to use this venv:"
    echo "1. To activate the virtual environment, run:"
    echo "   source ~/.venvs/python_tools/bin/activate"
    echo "2. To install a tool using pipx inside the venv, run:"
    echo "   pipx install <tool_name>  # Example: pipx install httpie"
    echo "3. Once you're done, you can deactivate the venv with:"
    echo "   deactivate"

    echo -e "\n### Why use a virtual environment?"
    echo "Using a venv ensures that your Python packages are isolated from your system installation."
    echo "This helps prevent conflicts between different Python projects and ensures that each project gets the specific dependencies it needs."
    echo "For example, you don't want to accidentally update or break a system tool by installing a Python package globally."

    echo -e "\n### Example: Using pipx in the virtual environment"
    echo "Let's install a Python tool called `httpie` using pipx in this isolated environment."
    echo "Run the following command after activating the virtual environment:"
    echo "   pipx install httpie"
    echo "You can use this same approach to install other Python tools."

    # Optionally provide a reminder about activating venv
    echo -e "\n### Reminder:"
    echo "Whenever you want to use the tools installed in this virtual environment, remember to activate it first:"
    echo "   source ~/.venvs/python_tools/bin/activate"
fi

# Optional: mkvenv helper for creating venvs
echo -e "\033[1;33m\n### 🛠️ mkvenv helper\033[0m"
if confirm "Add a 'mkvenv' helper script for creating venvs"; then
    cat << 'EOF' > ~/bin/mkvenv
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: mkvenv <env-name>"
    exit 1
fi
mkdir -p ~/.venvs
cd ~/.venvs
python3 -m venv "$1"
echo "To activate: source ~/.venvs/$1/bin/activate"
EOF
    chmod +x ~/bin/mkvenv
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    echo "Helper script installed as 'mkvenv'. Restart shell or run 'source ~/.bashrc'"
fi

# cargo (Rust)
echo -e "\033[1;33m\n### 🦀 cargo (Rust)\033[0m"
if confirm "cargo (Rust)"; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source $HOME/.cargo/env
fi

# Composer (PHP)
echo -e "\033[1;33m\n### 📝 Composer (PHP)\033[0m"
if confirm "Composer (PHP)"; then
    sudo apt install -y curl php-cli php-mbstring unzip
    curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer
fi

# Maven (Java)
echo -e "\033[1;33m\n### ☕ Maven (Java)\033[0m"
if confirm "Maven (Java)"; then
    sudo apt install -y maven
fi

# Gradle (Java)
echo -e "\033[1;33m\n### ⚙️ Gradle (Java)\033[0m"
if confirm "Gradle (Java)"; then
    sudo apt install -y gradle
fi

# CPAN (Perl)
echo -e "\033[1;33m\n### 🦠 CPAN (Perl)\033[0m"
if confirm "CPAN (Perl)"; then
    sudo apt install -y perl
fi

# Homebrew (Linuxbrew)
echo -e "\033[1;33m\n### 🍻 Homebrew (Linuxbrew)\033[0m"
if confirm "Homebrew (Linuxbrew)"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.profile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Miniconda (Python/R)
echo -e "\033[1;33m\n### 🐍🔬 Miniconda (Python/R)\033[0m"
if confirm "Miniconda (Python/R)"; then
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash Miniconda3-latest-Linux-x86_64.sh
fi

# cabal (Haskell)
echo -e "\033[1;33m\n### ⚡ cabal (Haskell)\033[0m"
if confirm "cabal (Haskell)"; then
    sudo apt install -y cabal-install
fi

# Go (Golang)
echo -e "\033[1;33m\n### 🐹 Go (Golang)\033[0m"
if confirm "Go (Golang)"; then
    sudo apt install -y golang
fi

echo -e "\033[1;32m✅ All selected tools installed.\033[0m"

