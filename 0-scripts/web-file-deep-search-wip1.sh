#!/usr/bin/env python3
# Author: Roy Wiseman 2025-05
# web-file-forensic-search.py

import argparse
import fnmatch
import os
import re
import shutil
import sys
import time
from urllib.parse import urlparse, unquote
import requests
from bs4 import BeautifulSoup # For better title/link extraction if needed, or parsing "Index of" pages
from duckduckgo_search import DDGS

# --- Configuration ---
# Set a realistic User-Agent
REQUEST_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
}
DOWNLOAD_TIMEOUT_SECONDS = 30  # Timeout for each download
REQUEST_TIMEOUT_SECONDS = 10   # Timeout for HEAD requests or initial search requests
TEMP_DOWNLOAD_DIR_BASE = "/tmp/web_file_downloads"

def sanitize_filename(filename):
    """Remove or replace characters that are problematic in filenames."""
    return re.sub(r'[<>:"/\\|?*]', '_', filename)

def extract_filename_from_url(url):
    """Extracts a potential filename from a URL."""
    path = urlparse(url).path
    filename = unquote(os.path.basename(path))
    return filename if filename else None

def is_likely_download_link(url, filename_pattern, session):
    """
    Checks if a URL is likely a direct download link for the given pattern.
    Uses HEAD request to check Content-Type and Content-Disposition.
    """
    # Basic check: does the extracted filename from URL match the pattern?
    extracted_fn = extract_filename_from_url(url)
    if not extracted_fn or not fnmatch.fnmatch(extracted_fn.lower(), filename_pattern.lower()):
        return False

    # More advanced check: HEAD request
    # This part can be slow if checking many URLs
    # For now, we'll rely on the filename match and URL structure
    # A simple heuristic: common file extensions
    common_extensions = [
        '.zip', '.rar', '.tar', '.gz', '.tgz', '.7z', '.pdf', '.doc', '.docx',
        '.xls', '.xlsx', '.ppt', '.pptx', '.mobi', '.epub', '.iso', '.img',
        '.exe', '.msi', '.dmg', '.pkg', '.deb', '.rpm', '.mp3', '.mp4', '.avi',
        '.mkv', '.jpg', '.jpeg', '.png', '.gif', '.txt', '.log', '.csv', '.json',
        '.xml', '.sql', '.db', '.sqlite'
    ]
    if any(extracted_fn.lower().endswith(ext) for ext in common_extensions):
        try:
            # Optional: Perform a HEAD request to check headers
            # This makes the script slower but more accurate
            # response = session.head(url, timeout=REQUEST_TIMEOUT_SECONDS, allow_redirects=True)
            # content_type = response.headers.get('Content-Type', '').lower()
            # content_disposition = response.headers.get('Content-Disposition', '').lower()

            # if 'text/html' in content_type and not content_disposition: # Likely an HTML page
            #     return False
            # if response.status_code == 200: # or other success codes
            #     return True
            return True # For now, if filename matches and has common extension, assume it's a candidate
        except requests.RequestException:
            return False # Could not verify with HEAD request
    return False


def search_for_files(filename_pattern, max_results=50):
    """
    Searches for files using DuckDuckGo.
    `filename_pattern` can include wildcards like * and ?.
    """
    print(f"[INFO] Searching for files matching: {filename_pattern}")
    print(f"[INFO] This may take a moment...")

    # Construct a search query.
    # For wildcards, it's better to search for parts of the name and filter locally.
    # Example: "book ??.mobi" -> search for "book mobi"
    query_parts = [part for part in re.split(r'[\*\?]+', filename_pattern) if part]
    search_query = " ".join(query_parts)

    if not search_query.strip():
        print("[WARNING] The search pattern resulted in an empty query. Try a more specific pattern.")
        return []

    # Try to add filetype if a clear extension is in the pattern (heuristic)
    base, ext = os.path.splitext(filename_pattern)
    if ext and len(ext) > 1 and not any(c in ext for c in ['*', '?']):
        search_query += f" filetype:{ext[1:]}"
    
    # Add "intitle:index of" to try and find open directories, can be noisy
    # search_query_opendir = f'{search_query} intitle:"index of"'

    found_urls = []
    session = requests.Session()
    session.headers.update(REQUEST_HEADERS)

    try:
        with DDGS(headers=REQUEST_HEADERS, timeout=REQUEST_TIMEOUT_SECONDS) as ddgs:
            # Search 1: General search
            print(f"[INFO] Performing general search for: \"{search_query}\"")
            ddgs_results = list(ddgs.text(search_query, max_results=max_results))
            
            # Search 2: "Index of" search (optional, can add many irrelevant results)
            # print(f"[INFO] Performing 'index of' search for: \"{search_query_opendir}\"")
            # ddgs_opendir_results = list(ddgs.text(search_query_opendir, max_results=max_results // 2))
            # all_raw_results = ddgs_results + ddgs_opendir_results
            all_raw_results = ddgs_results


        print(f"[INFO] Processing {len(all_raw_results)} potential results from search engine...")
        
        checked_urls = set()
        for i, result in enumerate(all_raw_results):
            url = result.get('href')
            if not url or url in checked_urls:
                continue
            checked_urls.add(url)

            # Display progress
            sys.stdout.write(f"\r[INFO] Checking URL {i+1}/{len(all_raw_results)}: {url[:70]}...")
            sys.stdout.flush()

            extracted_filename = extract_filename_from_url(url)
            if extracted_filename:
                if fnmatch.fnmatch(extracted_filename.lower(), filename_pattern.lower()):
                    # Further check if it's likely a direct download
                    # For performance, we can skip the HEAD request here if too slow,
                    # and rely more on user inspection.
                    # if is_likely_download_link(url, filename_pattern, session):
                    found_urls.append(url)
                    # else:
                    # print(f"\n[DEBUG] URL {url} filename matched but not deemed direct download link.")
            # Optional: If it's an "index of" page, try to parse it
            # title = result.get('title', '').lower()
            # if "index of" in title:
            #     try:
            #         print(f"\n[INFO] Found potential 'Index of' page: {url}. Attempting to parse...")
            #         response = session.get(url, timeout=REQUEST_TIMEOUT_SECONDS)
            #         response.raise_for_status()
            #         soup = BeautifulSoup(response.content, 'html.parser')
            #         for link in soup.find_all('a', href=True):
            #             file_url = link['href']
            #             # Construct absolute URL if relative
            #             if not urlparse(file_url).scheme:
            #                 file_url = requests.compat.urljoin(url, file_url)
                            
            #             sub_extracted_fn = extract_filename_from_url(file_url)
            #             if sub_extracted_fn and fnmatch.fnmatch(sub_extracted_fn.lower(), filename_pattern.lower()):
            #                 if is_likely_download_link(file_url, filename_pattern, session):
            #                     if file_url not in found_urls and file_url not in checked_urls:
            #                         found_urls.append(file_url)
            #                         checked_urls.add(file_url)
            #     except Exception as e:
            #         print(f"\n[WARNING] Could not parse 'Index of' page {url}: {e}")
        sys.stdout.write("\r" + " " * 100 + "\r") # Clear progress line
        sys.stdout.flush()


    except Exception as e:
        print(f"\n[ERROR] An error occurred during search: {e}")
    
    # Deduplicate (though `checked_urls` should handle most of it)
    unique_found_urls = sorted(list(set(found_urls)))
    print(f"[INFO] Found {len(unique_found_urls)} potential direct link(s) after initial filtering.")
    return unique_found_urls

def download_file(url, target_dir, prefix_num, original_filename_pattern):
    """Downloads a single file."""
    try:
        extracted_filename = extract_filename_from_url(url)
        if not extracted_filename:
            print(f"[ERROR] Could not extract filename from URL: {url}")
            return None, 0

        # Sanitize filename to prevent path traversal or invalid characters
        safe_base_filename = sanitize_filename(extracted_filename)
        
        # Use prefix for uniqueness
        download_filename = f"{prefix_num:03d}-{safe_base_filename}"
        filepath = os.path.join(target_dir, download_filename)

        print(f"  Downloading {url} to {filepath} ...")
        response = requests.get(url, stream=True, headers=REQUEST_HEADERS, timeout=DOWNLOAD_TIMEOUT_SECONDS, allow_redirects=True)
        response.raise_for_status()  # Raise an exception for bad status codes

        with open(filepath, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        filesize = os.path.getsize(filepath)
        print(f"  Downloaded {download_filename} ({filesize} bytes)")
        return filepath, filesize

    except requests.exceptions.RequestException as e:
        print(f"  [ERROR] Failed to download {url}: {e}")
    except IOError as e:
        print(f"  [ERROR] Failed to write file for {url}: {e}")
    except Exception as e:
        print(f"  [ERROR] An unexpected error occurred for {url}: {e}")
    
    # Cleanup failed partial download if it exists
    if 'filepath' in locals() and os.path.exists(filepath):
        try:
            os.remove(filepath)
        except OSError:
            pass # Ignore if removal fails
    return None, 0

def main():
    parser = argparse.ArgumentParser(
        description="Web File Forensic Search: Find and download files from the internet.",
        epilog="Example: python web-file-forensic-search.py \"report_final_*.pdf\" -n 5"
    )
    parser.add_argument(
        "filename_pattern", 
        help="Filename pattern to search for (e.g., 'document.pdf', 'archive_??.zip', 'image_*.jpg'). Wildcards * and ? are supported."
    )
    parser.add_argument(
        "-n", "--num_downloads", 
        type=int, 
        default=10,
        help="Maximum number of files to attempt to download (default: 10)."
    )
    parser.add_argument(
        "--max_search_results",
        type=int,
        default=50, # Limit how many results we ask from DDGS to process
        help="Maximum number of search results to fetch from search engine for processing (default: 50)."
    )

    args = parser.parse_args()

    print("--- Web File Forensic Search ---")
    print("DISCLAIMER: This script searches publicly available information via search engines.")
    print("Please use responsibly and ethically. Respect copyrights and website terms of service.")
    print("This script does NOT access paywalled content or private systems.\n")

    found_urls = search_for_files(args.filename_pattern, max_results=args.max_search_results)

    if not found_urls:
        print("[INFO] No direct file URLs matching your criteria were found.")
        return

    print("\n--- Potential File URLs Found ---")
    for i, url_item in enumerate(found_urls):
        print(f"{i+1}. {url_item}")
    
    print(f"\nFound {len(found_urls)} potential URLs.")
    if len(found_urls) == 0:
        return

    user_choice = input(f"Would you like to attempt to download up to {args.num_downloads} of these files? (yes/no): ").strip().lower()

    if user_choice not in ['yes', 'y']:
        print("[INFO] Download process skipped by user.")
        return

    # Create a unique download directory for this session
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    download_subdir_name = sanitize_filename(f"{args.filename_pattern}_{timestamp}")
    download_dir = os.path.join(TEMP_DOWNLOAD_DIR_BASE, download_subdir_name)
    
    try:
        os.makedirs(download_dir, exist_ok=True)
        print(f"[INFO] Files will be downloaded to: {download_dir}")
    except OSError as e:
        print(f"[ERROR] Could not create download directory {download_dir}: {e}")
        return

    downloaded_files_summary = []
    download_count = 0
    
    urls_to_download = found_urls[:args.num_downloads]

    for i, url_to_download in enumerate(urls_to_download):
        if download_count >= args.num_downloads:
            print(f"[INFO] Reached download limit of {args.num_downloads}.")
            break
        
        print(f"\nAttempting download {i+1}/{len(urls_to_download)} (Overall {download_count + 1})")
        filepath, filesize = download_file(url_to_download, download_dir, download_count, args.filename_pattern)
        
        if filepath and filesize > 0:
            downloaded_files_summary.append({'path': filepath, 'size': filesize, 'url': url_to_download})
            download_count += 1
        elif filepath and filesize == 0:
            print(f"  [INFO] Deleting zero-byte file: {filepath}")
            try:
                os.remove(filepath)
            except OSError as e:
                print(f"  [WARNING] Could not delete zero-byte file {filepath}: {e}")
        # If filepath is None, an error already printed by download_file

    print("\n--- Download Summary ---")
    if downloaded_files_summary:
        print(f"Successfully downloaded {len(downloaded_files_summary)} file(s) to {download_dir}:")
        max_path_len = max(len(os.path.basename(f['path'])) for f in downloaded_files_summary) if downloaded_files_summary else 0
        
        for item in downloaded_files_summary:
            filename = os.path.basename(item['path'])
            print(f"  - {filename:<{max_path_len}} ({item['size']:,} bytes) from {item['url']}")
    else:
        print("No files were successfully downloaded.")
    
    # Optional: Clean up empty download directory if nothing was saved
    if not os.listdir(download_dir):
        try:
            print(f"[INFO] Download directory {download_dir} is empty, removing it.")
            shutil.rmtree(download_dir)
            # Also remove base dir if it's now empty
            if not os.listdir(TEMP_DOWNLOAD_DIR_BASE):
                 shutil.rmtree(TEMP_DOWNLOAD_DIR_BASE)
        except OSError as e:
            print(f"[WARNING] Could not remove empty download directory {download_dir}: {e}")


if __name__ == "__main__":
    # Before running, ensure libraries are installed:
    # pip install requests duckduckgo_search beautifulsoup4
    print("Verifying dependencies...")
    try:
        import requests
        import duckduckgo_search
        import bs4
        import fnmatch # Standard library
    except ImportError as e:
        print(f"[FATAL ERROR] Missing required Python library: {e.name}")
        print("Please install the necessary libraries using pip:")
        print("pip install requests duckduckgo_search beautifulsoup4")
        sys.exit(1)
    print("Dependencies OK.\n")
    main()
