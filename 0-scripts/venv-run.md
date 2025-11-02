# Debian Python "Externally Managed Environment" Guide

## The Problem

Debian Bookworm (12+) and Ubuntu 23.04+ have implemented a policy that prevents system-wide `pip install` commands. This makes running Python scripts significantly more complicated.

### Before (pre-Bookworm):
```bash
pip install requests
python my_script.py  # Just works
```

### Now (Bookworm+):
```bash
pip install requests
# ERROR: externally-managed-environment
# 🤬 Can't install packages system-wide anymore
```

---

## Why Debian Did This

**Their reasoning:** Prevent users from accidentally breaking system packages with `pip install`. 

In the past, people would do `pip install numpy` and it would upgrade/replace Debian's `apt`-installed numpy, breaking system tools that depended on specific versions.

**The reality:** It's now a huge pain for normal Python development and script usage.

---

## Your Options (All Have Trade-offs)

### 1. **Virtual Environments (venv) - Recommended for Projects**

Create an isolated environment for each project:

```bash
# Create venv
python3 -m venv ~/myproject/venv

# Activate it
source ~/myproject/venv/bin/activate

# Install packages
pip install requests

# Use Python normally
python my_script.py

# Deactivate when done
deactivate
```

**Pros:**
- Clean isolation per project
- No system pollution
- Debian-approved method

**Cons:**
- Manual activation/deactivation
- Need to remember which venv to use
- Slower workflow for quick scripts

---

### 2. **User Installation (`--user`) - Quick & Dirty**

Install packages to your user directory instead of system-wide:

```bash
pip install --user requests
python my_script.py
```

Packages go to `~/.local/lib/python3.x/site-packages`

**Pros:**
- No venv needed
- Works immediately
- Packages available everywhere for your user

**Cons:**
- Pollutes your user Python environment
- Version conflicts between projects
- Hard to track what's installed where

---

### 3. **Break System Packages Flag - Not Recommended**

Override Debian's protection (dangerous):

```bash
# Temporary bypass
PIP_BREAK_SYSTEM_PACKAGES=1 pip install requests

# Or permanently (adds to ~/.bashrc)
echo 'export PIP_BREAK_SYSTEM_PACKAGES=1' >> ~/.bashrc
source ~/.bashrc
pip install requests
```

**Pros:**
- Works like "the old days"

**Cons:**
- Can break system packages
- Defeats Debian's safety mechanism
- May cause system instability
- Updates via `apt` might conflict

---

### 4. **Remove the Lock File - EXTREME (Not Recommended)**

```bash
sudo rm /usr/lib/python3*/EXTERNALLY-MANAGED
```

**WARNING:** This may break Debian's package management!

---

### 5. **Use venv-run.sh - Best for Ad-Hoc Scripts**

Automated temporary venv creation and execution:

```bash
# Run a package once
venv-run.sh httpie https://api.example.com

# Keep venv for multiple uses
venv-run.sh -k -p ~/myvenv python my_script.py

# Just create/activate a venv
venv-run.sh -p ~/project-venv
```

**Pros:**
- Automatic venv management
- Clean isolation
- Easy cleanup
- Great for one-off package usage

**Cons:**
- Slower first run (package installation)
- Another tool to learn

---

### 6. **Rewrite Scripts to Auto-Install Dependencies**

Make scripts self-sufficient:

```python
#!/usr/bin/env python3
import subprocess
import sys

def ensure_package(package):
    """Install package if not already available"""
    try:
        __import__(package)
    except ImportError:
        print(f"Installing {package}...")
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", "--user", package
        ])

# Ensure dependencies
ensure_package("requests")

# Now use normally
import requests
response = requests.get("https://api.example.com")
print(response.json())
```

**Pros:**
- Script handles its own dependencies
- Easy for end users

**Cons:**
- More complex scripts
- Still pollutes user space with --user
- Slower first run

---

## Python Dependency Management Tools

### **pipenv** - Project Dependency Manager

`pipenv` combines `pip` and `virtualenv` into one tool.

**What it does:**
- Creates venvs automatically per project
- Manages dependencies in `Pipfile` and `Pipfile.lock`
- Ensures reproducible builds (exact versions)

**Usage:**
```bash
# Install
pip install --user pipenv  # or: pipx install pipenv

# In your project directory
pipenv install requests     # Creates venv + installs
pipenv shell               # Activate venv
python my_script.py
exit                       # Deactivate

# Or run directly
pipenv run python my_script.py
```

**When to use:**
- Professional projects
- Team collaboration
- When you need reproducible environments

---

### **poetry** - Modern Dependency & Project Manager

`poetry` is like `pipenv` but more opinionated and feature-rich.

**What it does:**
- Dependency management (like pipenv)
- Package building and publishing
- Virtual environment management
- Lock file for exact reproducibility

**Usage:**
```bash
# Install
pip install --user poetry  # or: pipx install poetry

# Create new project
poetry new myproject
cd myproject

# Add dependencies
poetry add requests

# Run commands in venv
poetry run python my_script.py

# Or activate shell
poetry shell
python my_script.py
exit
```

**When to use:**
- Modern Python projects
- When publishing packages to PyPI
- When you want the "best practices" approach

---

### **pipx** - Install CLI Tools System-Wide (Isolated)

`pipx` installs command-line Python applications in isolated environments but makes them available system-wide.

**What it does:**
- Installs each app in its own venv
- Adds executables to your PATH
- Prevents dependency conflicts between apps

**Usage:**
```bash
# Install pipx itself
sudo apt install pipx
pipx ensurepath

# Install CLI tools
pipx install httpie        # HTTP client
pipx install black         # Code formatter
pipx install youtube-dl    # Video downloader

# Use them anywhere
httpie https://api.example.com
black my_code.py

# Update
pipx upgrade httpie

# Remove
pipx uninstall httpie
```

**When to use:**
- Installing CLI tools you want available everywhere
- Tools like: black, flake8, httpie, youtube-dl, awscli, etc.
- NOT for libraries (use venv/pipenv/poetry for those)

---

### **direnv** - Auto-Activate Venvs Per Directory

`direnv` automatically loads/unloads environment variables when you enter/leave directories.

**What it does:**
- Detects `.envrc` files in directories
- Auto-activates venvs when you `cd` into project
- Auto-deactivates when you leave
- Can set environment variables per project

**Setup:**
```bash
# Install
sudo apt install direnv

# Add to ~/.bashrc
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
source ~/.bashrc
```

**Usage:**
```bash
# In your project directory
echo 'layout python' > .envrc
direnv allow

# Now whenever you cd into this directory:
cd ~/myproject
# direnv: loading ~/myproject/.envrc
# (venv automatically activated!)

cd ~
# direnv: unloading
# (venv automatically deactivated!)
```

**When to use:**
- You work on multiple Python projects
- Tired of manually activating venvs
- Want seamless environment switching

---

## Recommended Workflows

### For Quick Scripts / One-Off Tasks
```bash
# Use venv-run.sh
venv-run.sh httpie https://api.example.com
venv-run.sh -p ~/scratch python test.py
```

### For Personal Projects
```bash
# Simple venv
cd ~/myproject
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
# ... work ...
deactivate

# Or with direnv (auto-activation)
cd ~/myproject
echo 'layout python' > .envrc
direnv allow
# venv auto-activates when you cd here!
```

### For Professional / Team Projects
```bash
# Use poetry (modern) or pipenv (established)
cd ~/work-project
poetry install
poetry run python main.py

# Or
pipenv install
pipenv run python main.py
```

### For CLI Tools You Use Often
```bash
# Use pipx
pipx install httpie
pipx install black
pipx install yt-dlp

# Now available everywhere
httpie GET https://httpbin.org/get
```

---

## Quick Reference Table

| Method | Speed | Isolation | System Risk | Best For |
|--------|-------|-----------|-------------|----------|
| `venv` | Medium | ✅ High | ✅ Safe | Projects |
| `--user` | ✅ Fast | ⚠️ Low | ✅ Safe | Quick scripts |
| `--break-system-packages` | ✅ Fast | ❌ None | ⚠️ Risky | Not recommended |
| `pipx` | Medium | ✅ High | ✅ Safe | CLI tools |
| `pipenv` | Slow | ✅ High | ✅ Safe | Professional projects |
| `poetry` | Slow | ✅ High | ✅ Safe | Modern projects |
| `venv-run.sh` | Medium | ✅ High | ✅ Safe | Ad-hoc usage |

---

## The Bottom Line

**Yes, Debian has made Python scripting harder.** You now need to think about environments instead of just running scripts.

**The Python community is divided:**
- Some say Debian is being "responsible"
- Others say it's "user-hostile"

**You're not wrong to be annoyed** - it IS more complicated now.

**Best practices going forward:**
1. **Projects:** Use venvs (or poetry/pipenv)
2. **CLI tools:** Use pipx
3. **Quick tests:** Use venv-run.sh or --user
4. **Never:** Use --break-system-packages or remove EXTERNALLY-MANAGED

The good news: Once you get used to venvs, they actually make projects cleaner and more reproducible. But yes, the transition is painful! 😤

---

## Additional Resources

- **Debian Python Policy:** https://wiki.debian.org/Python
- **Python venv documentation:** https://docs.python.org/3/library/venv.html
- **pipx documentation:** https://pipx.pypa.io/
- **poetry documentation:** https://python-poetry.org/
- **pipenv documentation:** https://pipenv.pypa.io/
- **direnv documentation:** https://direnv.net/
