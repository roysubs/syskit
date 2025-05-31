#!/usr/bin/env python3
# Author: Roy Wiseman 2025-04
"""
GitHub Project Downloader

This script downloads the latest release of a GitHub project, extracts it,
and installs the binary to a suitable location.

Usage:
    python github_downloader.py <github_url>

Example:
    python github_downloader.py https://github.com/cli/cli
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

def get_github_repo_info(url):
    """Extract the owner and repo name from a GitHub URL."""
    parsed_url = urlparse(url)
    if "github.com" not in parsed_url.netloc:
        raise ValueError("Not a GitHub URL")
    
    path_parts = [part for part in parsed_url.path.split('/') if part]
    if len(path_parts) < 2:
        raise ValueError("Invalid GitHub repository URL")
    
    return path_parts[0], path_parts[1]

def create_github_api_request(endpoint):
    """Create a request with appropriate GitHub API headers."""
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "GitHub-Project-Downloader/1.0"
    }
    return Request(f"https://api.github.com/{endpoint}", headers=headers)

def get_latest_release(owner, repo):
    """Get the latest release information from GitHub API."""
    try:
        request = create_github_api_request(f"repos/{owner}/{repo}/releases/latest")
        with urlopen(request) as response:
            return json.loads(response.read().decode('utf-8'))
    except HTTPError as e:
        if e.code == 404:
            print(f"No releases found for {owner}/{repo} using GitHub API")
            return None
        raise

def get_all_releases(owner, repo):
    """Get all releases information from GitHub API."""
    try:
        request = create_github_api_request(f"repos/{owner}/{repo}/releases")
        with urlopen(request) as response:
            return json.loads(response.read().decode('utf-8'))
    except HTTPError as e:
        if e.code == 404:
            print(f"No releases found for {owner}/{repo} using GitHub API")
            return []
        raise

def get_latest_tag(owner, repo):
    """Get the latest tag information from GitHub API."""
    try:
        request = create_github_api_request(f"repos/{owner}/{repo}/tags")
        with urlopen(request) as response:
            tags = json.loads(response.read().decode('utf-8'))
            return tags[0] if tags else None
    except HTTPError:
        print(f"No tags found for {owner}/{repo}")
        return None

def get_latest_version_from_html(url):
    """Try to scrape the latest version from the GitHub repository page."""
    try:
        request = Request(url, headers={"User-Agent": "GitHub-Project-Downloader/1.0"})
        with urlopen(request) as response:
            html = response.read().decode('utf-8')
            
            # Look for release links
            release_patterns = [
                r'href="/' + url.split('github.com/')[1] + r'/releases/tag/([^"]+)"',
                r'href="/' + url.split('github.com/')[1] + r'/releases/download/([^/]+)',
                r'data-tag="([^"]+)"'
            ]
            
            for pattern in release_patterns:
                matches = re.findall(pattern, html)
                if matches:
                    return matches[0]
                    
            return None
    except Exception as e:
        print(f"Error scraping repository page: {e}")
        return None

def determine_system_info():
    """Determine the current system's architecture and OS."""
    system = platform.system().lower()
    machine = platform.machine().lower()
    
    arch = None
    if "x86_64" in machine or "amd64" in machine:
        arch = "x86_64"
    elif "aarch64" in machine or "arm64" in machine:
        arch = "arm64"
    elif "arm" in machine:
        arch = "arm"
    elif "386" in machine or "x86" in machine or "i686" in machine:
        arch = "386"
    else:
        arch = machine
    
    return system, arch

def select_asset(assets, system, arch):
    """Select the most appropriate asset for the current system."""
    # Create a prioritized list of keywords
    system_keywords = [system]
    if system == "darwin":
        system_keywords.extend(["mac", "macos", "osx", "apple"])
    elif system == "windows":
        system_keywords.append("win")

    arch_keywords = []
    if arch == "x86_64":
        arch_keywords.extend(["x86_64", "amd64", "x64", "64"])
    elif arch == "arm64":
        arch_keywords.extend(["arm64", "aarch64"])
    elif arch == "386":
        arch_keywords.extend(["386", "i386", "x86", "32"])
    
    # Score each asset based on filename
    best_asset = None
    best_score = -1
    
    for asset in assets:
        filename = asset["name"].lower()
        score = 0
        
        # Only consider common binary or archive formats
        if not (filename.endswith('.zip') or 
                filename.endswith('.tar.gz') or 
                filename.endswith('.tgz') or 
                filename.endswith('.exe') or 
                filename.endswith('.dmg') or 
                filename.endswith('.deb') or 
                filename.endswith('.rpm')):
            continue
            
        # Skip source code archives
        if "source" in filename or "src" in filename:
            continue
        
        # Check for system match
        for keyword in system_keywords:
            if keyword in filename:
                score += 10
                break
        
        # Check for architecture match
        for keyword in arch_keywords:
            if keyword in filename:
                score += 5
                break
        
        if score > best_score:
            best_score = score
            best_asset = asset
    
    # If no matching asset found but assets exist, take the first one that looks like a binary
    if best_asset is None and assets:
        for asset in assets:
            filename = asset["name"].lower()
            if (filename.endswith('.zip') or 
                filename.endswith('.tar.gz') or 
                filename.endswith('.tgz') or 
                filename.endswith('.exe') or 
                filename.endswith('.dmg')):
                return asset
    
    return best_asset

def download_file(url, dest_path):
    """Download a file from a URL to the specified path."""
    request = Request(url, headers={"User-Agent": "GitHub-Project-Downloader/1.0"})
    with urlopen(request) as response, open(dest_path, 'wb') as out_file:
        shutil.copyfileobj(response, out_file)
    return dest_path

def extract_archive(archive_path, extract_dir):
    """Extract an archive file to the specified directory."""
    file_name = os.path.basename(archive_path).lower()
    
    if file_name.endswith('.zip'):
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
    elif file_name.endswith('.tar.gz') or file_name.endswith('.tgz'):
        with tarfile.open(archive_path, 'r:gz') as tar_ref:
            tar_ref.extractall(extract_dir)
    else:
        # If it's a standalone binary, just copy it
        dest_file = os.path.join(extract_dir, os.path.basename(archive_path))
        shutil.copy2(archive_path, dest_file)
        os.chmod(dest_file, 0o755)  # Make executable
        return [dest_file]
    
    return None  # Return None to indicate we need to find binaries

def find_binaries(directory):
    """Find potential binary files in the extracted directory."""
    binaries = []
    
    # Extensions that are likely to be binaries on different platforms
    binary_extensions = set(['', '.exe'])
    
    for root, _, files in os.walk(directory):
        for file in files:
            file_path = os.path.join(root, file)
            
            # Check if it's already executable or has a binary extension
            _, ext = os.path.splitext(file)
            if (os.access(file_path, os.X_OK) or ext in binary_extensions) and not os.path.islink(file_path):
                try:
                    # Additional check: try to determine if it's a binary file
                    with open(file_path, 'rb') as f:
                        header = f.read(4)
                        # Check for common executable headers
                        if (header.startswith(b'MZ') or  # Windows executable
                            header.startswith(b'\x7fELF') or  # Linux executable
                            header.startswith(b'\xca\xfe\xba\xbe') or  # Mach-O Fat Binary
                            header.startswith(b'\xcf\xfa\xed\xfe') or  # Mach-O 64-bit
                            header.startswith(b'\xce\xfa\xed\xfe')):  # Mach-O 32-bit
                            binaries.append(file_path)
                except:
                    # If we can't read the file or it's too small, skip it
                    pass
    
    return binaries

def select_best_binary(binaries, repo_name):
    """Select the most likely binary to be the main executable."""
    if not binaries:
        return None
    
    # If only one binary, return it
    if len(binaries) == 1:
        return binaries[0]
    
    # Try to find a binary with the same name as the repository
    repo_name_lower = repo_name.lower()
    for binary in binaries:
        binary_name = os.path.basename(binary).lower()
        name_without_ext = os.path.splitext(binary_name)[0]
        
        if name_without_ext == repo_name_lower:
            return binary
    
    # Look for binaries in a bin directory
    bin_binaries = [b for b in binaries if '/bin/' in b.replace('\\', '/')]
    if bin_binaries:
        return bin_binaries[0]
    
    # If we can't find a match, take the first binary
    return binaries[0]

def install_binary(binary_path, repo_name):
    """Install the binary to an appropriate location."""
    system = platform.system().lower()
    
    if system == "windows":
        install_dir = os.path.join(os.environ.get('LOCALAPPDATA', os.path.expanduser('~')), 'Programs')
    else:  # Unix-like systems (Linux, macOS)
        # Try using /usr/local/bin if we have write access, otherwise use ~/.local/bin
        if os.access('/usr/local/bin', os.W_OK):
            install_dir = '/usr/local/bin'
        else:
            install_dir = os.path.expanduser('~/.local/bin')
            os.makedirs(install_dir, exist_ok=True)
    
    # Create destination path
    binary_name = os.path.basename(binary_path)
    name_without_ext, ext = os.path.splitext(binary_name)
    
    # If the binary doesn't have the repo name, rename it to the repo name
    if repo_name.lower() not in name_without_ext.lower():
        dest_name = repo_name + ext if ext else repo_name
    else:
        dest_name = binary_name
    
    dest_path = os.path.join(install_dir, dest_name)
    
    # Copy and make executable
    shutil.copy2(binary_path, dest_path)
    os.chmod(dest_path, 0o755)
    
    return dest_path

def main():
    parser = argparse.ArgumentParser(description="Download and install the latest release of a GitHub project")
    parser.add_argument("url", help="GitHub repository URL")
    args = parser.parse_args()
    
    # Extract owner and repo information
    try:
        owner, repo = get_github_repo_info(args.url)
        print(f"Downloading project: {owner}/{repo}")
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    # Try multiple methods to find the latest release
    latest_release = get_latest_release(owner, repo)
    latest_version = None
    assets = []
    
    if latest_release:
        latest_version = latest_release["tag_name"]
        assets = latest_release["assets"]
        print(f"Found latest release: {latest_version}")
    else:
        # Try getting all releases
        releases = get_all_releases(owner, repo)
        if releases:
            latest_release = releases[0]
            latest_version = latest_release["tag_name"]
            assets = latest_release["assets"]
            print(f"Found latest release: {latest_version}")
        else:
            # Try getting latest tag
            latest_tag = get_latest_tag(owner, repo)
            if latest_tag:
                latest_version = latest_tag["name"]
                print(f"Found latest tag: {latest_version}")
            else:
                # Try scraping the HTML
                latest_version = get_latest_version_from_html(args.url)
                if latest_version:
                    print(f"Found version from webpage: {latest_version}")
                else:
                    print("Could not find any release information. Attempting to clone repository...")
                    # Clone the repository as a last resort
                    try:
                        with tempfile.TemporaryDirectory() as temp_dir:
                            subprocess.run(["git", "clone", "--depth", "1", args.url, temp_dir], check=True)
                            # Let's see if we can find a binary file in the repository
                            binaries = find_binaries(temp_dir)
                            if binaries:
                                best_binary = select_best_binary(binaries, repo)
                                install_path = install_binary(best_binary, repo)
                                print(f"Successfully installed {os.path.basename(install_path)} to {install_path}")
                                print(f"To run, use: {install_path}")
                                return
                            else:
                                print("No binary files found in the repository.")
                                print("This might be a source-only repository that needs compilation.")
                                print(f"Clone it manually with: git clone {args.url}")
                                return
                    except Exception as e:
                        print(f"Git clone failed: {e}")
                        print("Could not determine the latest version or find any releases.")
                        return
    
    # If we have assets from a release, choose the best one for our system
    system, arch = determine_system_info()
    print(f"System: {system}, Architecture: {arch}")
    
    if not assets and latest_version:
        # If we have a tag/version but no assets, try to construct a download URL
        release_url = f"https://github.com/{owner}/{repo}/releases/tag/{latest_version}"
        try:
            request = Request(release_url, headers={"User-Agent": "GitHub-Project-Downloader/1.0"})
            with urlopen(request) as response:
                html = response.read().decode('utf-8')
                download_links = re.findall(r'href="(/'+owner+'/'+repo+'/releases/download/[^"]+)"', html)
                
                if download_links:
                    assets = [{"name": link.split('/')[-1], 
                               "browser_download_url": "https://github.com" + link} 
                              for link in download_links]
        except Exception as e:
            print(f"Error getting release assets: {e}")
    
    # Select the appropriate asset for our system
    if assets:
        best_asset = select_asset(assets, system, arch)
        if best_asset:
            print(f"Selected asset: {best_asset['name']}")
            
            # Create temporary directory for download and extraction
            with tempfile.TemporaryDirectory() as temp_dir:
                # Download the asset
                download_path = os.path.join(temp_dir, best_asset['name'])
                print(f"Downloading to {download_path}...")
                download_file(best_asset['browser_download_url'], download_path)
                
                # Extract the archive
                print("Extracting archive...")
                extract_dir = os.path.join(temp_dir, "extracted")
                os.makedirs(extract_dir, exist_ok=True)
                
                extracted_files = extract_archive(download_path, extract_dir)
                
                # Find binaries if we extracted an archive
                if not extracted_files:
                    print("Looking for binary files...")
                    binaries = find_binaries(extract_dir)
                    
                    if not binaries:
                        print("No binary files found in the archive.")
                        return
                    
                    # Select the best binary
                    best_binary = select_best_binary(binaries, repo)
                    print(f"Selected binary: {os.path.basename(best_binary)}")
                else:
                    # We have a standalone binary
                    best_binary = extracted_files[0]
                
                # Install the binary
                install_path = install_binary(best_binary, repo)
                print(f"\nSuccessfully installed {os.path.basename(install_path)} to {install_path}")
                
                # Add instructions for adding to PATH if it's not already there
                if system != "windows" and install_path.startswith(os.path.expanduser('~')):
                    path_dir = os.path.dirname(install_path)
                    if path_dir not in os.environ.get('PATH', '').split(os.pathsep):
                        print(f"\nNOTE: To make this executable available system-wide, add this to your shell profile:")
                        if "zsh" in os.environ.get('SHELL', ''):
                            print(f'echo \'export PATH="{path_dir}:$PATH"\' >> ~/.zshrc')
                        else:
                            print(f'echo \'export PATH="{path_dir}:$PATH"\' >> ~/.bashrc')
                
                print(f"\nTo run, use: {os.path.basename(install_path)}")
        else:
            print("Could not find a suitable asset for your system.")
    else:
        print("No downloadable assets found for this release.")

if __name__ == "__main__":
    main()
