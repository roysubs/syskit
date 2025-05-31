#!/usr/bin/env python3
# Author: Roy Wiseman 2025-05
# web-file-forensic-search-enhanced.py

import argparse
import fnmatch
import hashlib
import os
import re
import shutil
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse, unquote, urljoin
from urllib.robotparser import RobotFileParser
import requests
from bs4 import BeautifulSoup
from duckduckgo_search import DDGS
import json

# --- Configuration ---
REQUEST_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebCore/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}
DOWNLOAD_TIMEOUT_SECONDS = 60
REQUEST_TIMEOUT_SECONDS = 15
HEAD_REQUEST_TIMEOUT = 10
TEMP_DOWNLOAD_DIR_BASE = "/tmp/web_file_downloads"
MAX_WORKERS = 5  # For concurrent processing
MAX_FILE_SIZE_MB = 500  # Skip files larger than this

# Common file extensions that are likely actual files (not web pages)
DOWNLOADABLE_EXTENSIONS = {
    '.zip', '.rar', '.tar', '.gz', '.tgz', '.7z', '.bz2', '.xz',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.mobi', '.epub', '.azw', '.azw3', '.fb2',
    '.iso', '.img', '.dmg', '.exe', '.msi', '.deb', '.rpm', '.pkg',
    '.mp3', '.mp4', '.avi', '.mkv', '.mov', '.flv', '.wmv', '.webm',
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.svg', '.webp',
    '.txt', '.log', '.csv', '.json', '.xml', '.sql', '.db', '.sqlite',
    '.bin', '.dat', '.dump', '.backup', '.bak', '.old',
    '.apk', '.ipa', '.jar', '.war', '.ear',
    '.torrent', '.magnet'
}

# Domains known to host files
FILE_HOSTING_DOMAINS = {
    'github.com', 'gitlab.com', 'bitbucket.org',
    'sourceforge.net', 'archive.org', 'mega.nz',
    'dropbox.com', 'drive.google.com', 'onedrive.live.com',
    'mediafire.com', '4shared.com', 'rapidshare.com',
    'fileshare.com', 'uploadfiles.io', 'wetransfer.com'
}

class FileCandidate:
    def __init__(self, url, filename, source_engine, confidence=0.5):
        self.url = url
        self.filename = filename
        self.source_engine = source_engine
        self.confidence = confidence
        self.verified = False
        self.file_size = None
        self.content_type = None
        self.status_code = None
        
    def __hash__(self):
        return hash(self.normalized_url())
        
    def __eq__(self, other):
        return self.normalized_url() == other.normalized_url()
        
    def normalized_url(self):
        """Normalize URL for duplicate detection"""
        parsed = urlparse(self.url.lower())
        # Remove common tracking parameters
        query_parts = []
        if parsed.query:
            for param in parsed.query.split('&'):
                if not any(tracker in param.lower() for tracker in 
                          ['utm_', 'ref=', 'source=', 'campaign=', 'medium=']):
                    query_parts.append(param)
        
        normalized_query = '&'.join(sorted(query_parts))
        return f"{parsed.scheme}://{parsed.netloc}{parsed.path}" + (f"?{normalized_query}" if normalized_query else "")

def sanitize_filename(filename):
    """Remove or replace characters that are problematic in filenames."""
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', filename).strip()

def extract_filename_from_url(url):
    """Extracts a potential filename from a URL."""
    try:
        path = urlparse(url).path
        filename = unquote(os.path.basename(path))
        # Remove query parameters from filename
        filename = filename.split('?')[0].split('#')[0]
        return filename if filename and '.' in filename else None
    except:
        return None

def check_robots_txt(url):
    """Check if we're allowed to access this URL according to robots.txt"""
    try:
        parsed = urlparse(url)
        robots_url = f"{parsed.scheme}://{parsed.netloc}/robots.txt"
        rp = RobotFileParser()
        rp.set_url(robots_url)
        rp.read()
        return rp.can_fetch(REQUEST_HEADERS['User-Agent'], url)
    except:
        return True  # If we can't check, assume it's okay

def verify_file_candidate(candidate, session):
    """Verify that a URL actually points to a downloadable file."""
    try:
        # Check robots.txt
        if not check_robots_txt(candidate.url):
            return False
            
        # Perform HEAD request to check file properties
        response = session.head(
            candidate.url, 
            timeout=HEAD_REQUEST_TIMEOUT, 
            allow_redirects=True,
            headers=REQUEST_HEADERS
        )
        
        candidate.status_code = response.status_code
        candidate.content_type = response.headers.get('Content-Type', '').lower()
        
        # Check if it's likely an HTML page
        if 'text/html' in candidate.content_type and not response.headers.get('Content-Disposition'):
            return False
            
        # Check file size
        content_length = response.headers.get('Content-Length')
        if content_length:
            try:
                size_mb = int(content_length) / (1024 * 1024)
                candidate.file_size = int(content_length)
                if size_mb > MAX_FILE_SIZE_MB:
                    print(f"  [SKIP] File too large: {size_mb:.1f}MB > {MAX_FILE_SIZE_MB}MB")
                    return False
            except ValueError:
                pass
        
        # Success indicators
        success_indicators = [
            response.status_code == 200,
            'attachment' in response.headers.get('Content-Disposition', ''),
            any(ext in candidate.url.lower() for ext in DOWNLOADABLE_EXTENSIONS),
            'application/' in candidate.content_type,
            'image/' in candidate.content_type,
            'audio/' in candidate.content_type,
            'video/' in candidate.content_type
        ]
        
        if any(success_indicators):
            candidate.verified = True
            return True
            
    except requests.RequestException:
        pass
    except Exception as e:
        print(f"  [DEBUG] Verification error for {candidate.url}: {e}")
    
    return False

def search_duckduckgo(query, max_results=50):
    """Search using DuckDuckGo with rate limit handling"""
    candidates = []
    try:
        print(f"  [DDG] Searching: {query}")
        
        # Add longer delay for DDG to avoid rate limits
        time.sleep(2)
        
        with DDGS(headers=REQUEST_HEADERS, timeout=REQUEST_TIMEOUT_SECONDS) as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
            
        for result in results:
            url = result.get('href', '')
            if not url:
                continue
                
            filename = extract_filename_from_url(url)
            if filename:
                confidence = 0.6
                # Boost confidence for known file hosting domains
                if any(domain in url.lower() for domain in FILE_HOSTING_DOMAINS):
                    confidence += 0.2
                
                candidates.append(FileCandidate(url, filename, 'DuckDuckGo', confidence))
        
        # Add delay after successful search
        time.sleep(3)
                
    except Exception as e:
        if "Ratelimit" in str(e) or "429" in str(e) or "202" in str(e):
            print(f"  [WARNING] DuckDuckGo rate limited - skipping this query")
            print(f"  [TIP] Try again in a few minutes, or use more specific search terms")
        else:
            print(f"  [ERROR] DuckDuckGo search failed: {e}")
    
    return candidates

def search_google_custom(query, max_results=50):
    """Search using Google (via web scraping - be careful about rate limits)"""
    candidates = []
    try:
        print(f"  [GOOGLE] Searching: {query}")
        session = requests.Session()
        session.headers.update(REQUEST_HEADERS)
        
        # Use Google search with filetype operator
        search_url = f"https://www.google.com/search?q={query}&num={min(max_results, 100)}"
        
        response = session.get(search_url, timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            print(f"    [WARNING] Google returned status {response.status_code}")
            return candidates
            
        soup = BeautifulSoup(response.content, 'html.parser')
        
        # Extract URLs from search results
        for link in soup.find_all('a', href=True):
            href = link['href']
            if href.startswith('/url?q='):
                # Extract actual URL from Google's redirect
                actual_url = href.split('/url?q=')[1].split('&')[0]
                try:
                    actual_url = unquote(actual_url)
                    filename = extract_filename_from_url(actual_url)
                    if filename and actual_url.startswith(('http://', 'https://')):
                        candidates.append(FileCandidate(actual_url, filename, 'Google', 0.7))
                except:
                    continue
                    
        # Add a delay to be respectful to Google
        time.sleep(1)
        
    except Exception as e:
        print(f"  [ERROR] Google search failed: {e}")
    
    return candidates

def search_bing(query, max_results=50):
    """Search using Bing"""
    candidates = []
    try:
        print(f"  [BING] Searching: {query}")
        session = requests.Session()
        session.headers.update(REQUEST_HEADERS)
        
        search_url = f"https://www.bing.com/search?q={query}&count={min(max_results, 50)}"
        
        response = session.get(search_url, timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            return candidates
            
        soup = BeautifulSoup(response.content, 'html.parser')
        
        # Extract URLs from Bing results
        for link in soup.find_all('a', href=True):
            href = link['href']
            if href.startswith('http'):
                filename = extract_filename_from_url(href)
                if filename:
                    candidates.append(FileCandidate(href, filename, 'Bing', 0.6))
                    
        time.sleep(1)  # Be respectful
        
    except Exception as e:
        print(f"  [ERROR] Bing search failed: {e}")
    
    return candidates

def search_for_files_multi_engine(filename_pattern, max_results_per_engine=30):
    """Search for files using multiple search engines."""
    print(f"[INFO] Multi-engine search for files matching: {filename_pattern}")
    
    # Check if pattern is too broad
    if filename_pattern.count('*') > 2 or len(filename_pattern.replace('*', '').replace('?', '')) < 3:
        print("[WARNING] Your search pattern might be too broad and could return millions of results!")
        print(f"[TIP] Current pattern: '{filename_pattern}' - consider being more specific")
        print("Examples of better patterns:")
        print("  - 'tolkien*.pdf' (Tolkien PDFs)")
        print("  - 'hobbit*.epub' (Hobbit ebooks)")
        print("  - '*tolkien*fellowship*.pdf' (Fellowship PDFs)")
        
        user_continue = input("Continue with this broad search? (yes/no): ").strip().lower()
        if user_continue not in ['yes', 'y']:
            print("[INFO] Search cancelled. Try a more specific pattern.")
            return []
    
    # Prepare search queries
    base_parts = [part for part in re.split(r'[\*\?]+', filename_pattern) if part.strip()]
    base_query = " ".join(base_parts)
    
    if not base_query.strip():
        print("[WARNING] Pattern resulted in empty query.")
        return []
    
    # Determine file extension for targeted searches
    ext_match = re.search(r'\.([a-zA-Z0-9]+)(?:\*|\?|$)', filename_pattern)
    file_ext = ext_match.group(1) if ext_match else None
    
    # Prepare multiple search strategies - FEWER queries to avoid rate limits
    search_queries = [base_query]
    
    if file_ext:
        # Only add the most effective filetype search
        search_queries.append(f"{base_query} filetype:{file_ext}")
    else:
        # If no extension specified, try common document formats
        search_queries.extend([
            f"{base_query} filetype:pdf",
            f"{base_query} filetype:epub"
        ])
    
    # Only add ONE index search to avoid rate limits
    search_queries.append(f'{base_query} intitle:"index of"')
    
    # Remove duplicates while preserving order
    seen = set()
    unique_queries = []
    for query in search_queries:
        if query not in seen:
            seen.add(query)
            unique_queries.append(query)
    
    # Limit to max 3 queries total to avoid rate limits
    unique_queries = unique_queries[:3]
    
    all_candidates = []
    
    # Search each engine with each query - with delays
    search_functions = [
        search_duckduckgo,
        search_google_custom,
        search_bing,
    ]
    
    for i, query in enumerate(unique_queries):
        print(f"\n[INFO] Query {i+1}/{len(unique_queries)}: '{query}'")
        
        for j, search_func in enumerate(search_functions):
            try:
                candidates = search_func(query, max_results_per_engine)
                all_candidates.extend(candidates)
                
                # Longer pause between different engines to avoid rate limits
                if j < len(search_functions) - 1:  # Don't delay after last engine
                    print(f"    [INFO] Pausing to avoid rate limits...")
                    time.sleep(5)  # Increased delay
                
            except Exception as e:
                print(f"  [ERROR] Search function {search_func.__name__} failed: {e}")
        
        # Pause between different queries
        if i < len(unique_queries) - 1:
            print(f"  [INFO] Pausing before next query...")
            time.sleep(3)
    
    # Remove duplicates and filter by pattern
    unique_candidates = {}
    for candidate in all_candidates:
        if fnmatch.fnmatch(candidate.filename.lower(), filename_pattern.lower()):
            key = candidate.normalized_url()
            if key not in unique_candidates or candidate.confidence > unique_candidates[key].confidence:
                unique_candidates[key] = candidate
    
    final_candidates = list(unique_candidates.values())
    print(f"\n[INFO] Found {len(final_candidates)} unique candidates after deduplication")
    
    return final_candidates

def verify_candidates_concurrent(candidates, max_workers=MAX_WORKERS):
    """Verify file candidates concurrently."""
    if not candidates:
        return []
    
    print(f"[INFO] Verifying {len(candidates)} candidates...")
    verified_candidates = []
    
    session = requests.Session()
    session.headers.update(REQUEST_HEADERS)
    
    def verify_single(candidate):
        try:
            if verify_file_candidate(candidate, session):
                return candidate
        except Exception as e:
            print(f"  [DEBUG] Verification failed for {candidate.url}: {e}")
        return None
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_candidate = {executor.submit(verify_single, candidate): candidate 
                             for candidate in candidates}
        
        for i, future in enumerate(as_completed(future_to_candidate)):
            candidate = future_to_candidate[future]
            sys.stdout.write(f"\r  Progress: {i+1}/{len(candidates)} - Checking {candidate.filename[:30]}...")
            sys.stdout.flush()
            
            try:
                result = future.result()
                if result:
                    verified_candidates.append(result)
            except Exception as e:
                print(f"\n  [ERROR] Failed to verify {candidate.url}: {e}")
    
    sys.stdout.write("\r" + " " * 80 + "\r")
    sys.stdout.flush()
    print(f"[INFO] Verified {len(verified_candidates)} downloadable files")
    
    return verified_candidates

def download_file(candidate, target_dir, prefix_num):
    """Downloads a single file."""
    try:
        safe_filename = sanitize_filename(candidate.filename)
        download_filename = f"{prefix_num:03d}-{safe_filename}"
        filepath = os.path.join(target_dir, download_filename)
        
        print(f"  Downloading {candidate.filename} from {candidate.source_engine}...")
        print(f"    URL: {candidate.url}")
        
        response = requests.get(
            candidate.url, 
            stream=True, 
            headers=REQUEST_HEADERS, 
            timeout=DOWNLOAD_TIMEOUT_SECONDS, 
            allow_redirects=True
        )
        response.raise_for_status()
        
        total_size = 0
        with open(filepath, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    total_size += len(chunk)
        
        print(f"    Downloaded {download_filename} ({total_size:,} bytes)")
        return filepath, total_size
        
    except requests.exceptions.RequestException as e:
        print(f"    [ERROR] Network error: {e}")
    except IOError as e:
        print(f"    [ERROR] File I/O error: {e}")
    except Exception as e:
        print(f"    [ERROR] Unexpected error: {e}")
    
    # Cleanup failed download
    if 'filepath' in locals() and os.path.exists(filepath):
        try:
            os.remove(filepath)
        except OSError:
            pass
    
    return None, 0

def main():
    parser = argparse.ArgumentParser(
        description="Enhanced Web File Forensic Search: Find and download files from multiple search engines.",
        epilog="Example: python script.py \"report_*.pdf\" -n 10 --verify-all"
    )
    parser.add_argument(
        "filename_pattern",
        help="Filename pattern with wildcards (* and ?) - e.g., 'document.pdf', 'archive_??.zip'"
    )
    parser.add_argument(
        "-n", "--num_downloads",
        type=int,
        default=10,
        help="Maximum number of files to download (default: 10)"
    )
    parser.add_argument(
        "--max_search_results",
        type=int,
        default=30,
        help="Max results per search engine (default: 30)"
    )
    parser.add_argument(
        "--verify-all",
        action="store_true",
        help="Verify all candidates before showing results (slower but more accurate)"
    )
    parser.add_argument(
        "--list-only",
        action="store_true",
        help="Only list found URLs without downloading"
    )
    
    args = parser.parse_args()
    
    print("=== Enhanced Web File Forensic Search ===")
    print("DISCLAIMER: This tool searches publicly available files via search engines.")
    print("Use responsibly and respect copyrights, robots.txt, and website terms of service.")
    print("This tool does NOT access private or paywalled content.\n")
    
    # Search phase
    candidates = search_for_files_multi_engine(
        args.filename_pattern, 
        max_results_per_engine=args.max_search_results
    )
    
    if not candidates:
        print("[INFO] No file candidates found matching your pattern.")
        return
    
    # Verification phase
    if args.verify_all:
        verified_candidates = verify_candidates_concurrent(candidates)
    else:
        # Quick verification of top candidates
        print(f"[INFO] Quick verification of top {min(20, len(candidates))} candidates...")
        verified_candidates = verify_candidates_concurrent(candidates[:20])
        if len(candidates) > 20:
            print(f"[INFO] Use --verify-all to check all {len(candidates)} candidates")
    
    if not verified_candidates:
        print("[INFO] No verified downloadable files found.")
        return
    
    # Sort by confidence score
    verified_candidates.sort(key=lambda x: x.confidence, reverse=True)
    
    # Display results
    print(f"\n=== Found {len(verified_candidates)} Verified Downloadable Files ===")
    for i, candidate in enumerate(verified_candidates, 1):
        size_info = f" ({candidate.file_size:,} bytes)" if candidate.file_size else ""
        print(f"{i:2d}. {candidate.filename}{size_info}")
        print(f"     URL: {candidate.url}")
        print(f"     Source: {candidate.source_engine} | Confidence: {candidate.confidence:.1f}")
        print()
    
    if args.list_only:
        return
    
    # Download phase
    if not verified_candidates:
        return
        
    download_count = min(args.num_downloads, len(verified_candidates))
    user_choice = input(f"Download {download_count} file(s)? (yes/no): ").strip().lower()
    
    if user_choice not in ['yes', 'y']:
        print("[INFO] Download skipped by user.")
        return
    
    # Create download directory
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    download_subdir = sanitize_filename(f"{args.filename_pattern}_{timestamp}")
    download_dir = os.path.join(TEMP_DOWNLOAD_DIR_BASE, download_subdir)
    
    try:
        os.makedirs(download_dir, exist_ok=True)
        print(f"[INFO] Downloads will be saved to: {download_dir}")
    except OSError as e:
        print(f"[ERROR] Could not create download directory: {e}")
        return
    
    # Download files
    successful_downloads = []
    candidates_to_download = verified_candidates[:download_count]
    
    for i, candidate in enumerate(candidates_to_download):
        print(f"\n--- Download {i+1}/{len(candidates_to_download)} ---")
        filepath, filesize = download_file(candidate, download_dir, i)
        
        if filepath and filesize > 0:
            successful_downloads.append({
                'path': filepath,
                'size': filesize,
                'url': candidate.url,
                'source': candidate.source_engine
            })
        elif filepath and filesize == 0:
            print(f"    [INFO] Removing zero-byte file")
            try:
                os.remove(filepath)
            except OSError:
                pass
    
    # Final summary
    print(f"\n=== Download Summary ===")
    if successful_downloads:
        print(f"Successfully downloaded {len(successful_downloads)} file(s):")
        for item in successful_downloads:
            filename = os.path.basename(item['path'])
            print(f"  ✓ {filename} ({item['size']:,} bytes) via {item['source']}")
        print(f"\nFiles saved to: {download_dir}")
    else:
        print("No files were successfully downloaded.")
        # Clean up empty directory
        try:
            os.rmdir(download_dir)
            if not os.listdir(TEMP_DOWNLOAD_DIR_BASE):
                os.rmdir(TEMP_DOWNLOAD_DIR_BASE)
        except OSError:
            pass

def check_and_install_dependencies():
    """Check for required dependencies and provide installation instructions."""
    print("=== Dependency Check ===")
    
    required_modules = {
        'requests': 'requests',
        'bs4': 'beautifulsoup4', 
        'duckduckgo_search': 'duckduckgo_search',
        'concurrent.futures': None,  # Built-in module (Python 3.2+)
        'urllib.parse': None,        # Built-in module
        'urllib.robotparser': None,  # Built-in module
        'threading': None,           # Built-in module
        'hashlib': None,            # Built-in module
        'json': None                # Built-in module
    }
    
    missing_modules = []
    available_modules = []
    
    for module, pip_name in required_modules.items():
        try:
            __import__(module)
            available_modules.append(module)
        except ImportError:
            if pip_name:  # Only add to missing if it's installable via pip
                missing_modules.append(pip_name)
    
    print(f"✓ Available modules: {len(available_modules)}/{len(required_modules)}")
    
    if missing_modules:
        print(f"\n❌ Missing required modules: {', '.join(missing_modules)}")
        print("\n=== SETUP INSTRUCTIONS ===")
        print("1. Create a virtual environment (recommended):")
        print("   python -m venv forensic_search_env")
        print("   # On Linux/Mac:")
        print("   source forensic_search_env/bin/activate")
        print("   # On Windows:")
        print("   forensic_search_env\\Scripts\\activate")
        print()
        print("2. Install required packages:")
        print(f"   pip install {' '.join(missing_modules)}")
        print()
        print("3. Run the script again:")
        print("   python web-file-forensic-search-enhanced.py \"your_pattern.*\"")
        print()
        print("=== Alternative: One-line install ===")
        print(f"pip install {' '.join(missing_modules)}")
        print()
        
        # Check Python version
        python_version = sys.version_info
        if python_version < (3, 7):
            print("⚠️  WARNING: This script requires Python 3.7+")
            print(f"   Current version: {python_version.major}.{python_version.minor}")
        else:
            print(f"✓ Python version: {python_version.major}.{python_version.minor} (compatible)")
        
        return False
    
    print("✓ All dependencies satisfied!")
    
    # Version check for key modules
    try:
        import requests
        import duckduckgo_search
        import bs4
        print(f"✓ requests: {requests.__version__}")
        print(f"✓ duckduckgo_search: {duckduckgo_search.__version__}")
        print(f"✓ beautifulsoup4: {bs4.__version__}")
    except AttributeError:
        pass  # Some modules don't have __version__
    
    return True

if __name__ == "__main__":
    if not check_and_install_dependencies():
        sys.exit(1)
    
    print()  # Add some spacing
    main()
