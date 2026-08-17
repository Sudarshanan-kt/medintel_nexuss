import os
import sys
import time
import re
import requests

def verify_deployment():
    # 1. Fetch BASE_URL from env or default
    base_url = os.getenv("BASE_URL", "").strip()
    if not base_url:
        print("Error: BASE_URL environment variable is not set.")
        return 1

    # Ensure trailing slash
    if not base_url.endswith("/"):
        base_url += "/"

    print(f"Starting deployment verification for target: {base_url}")
    
    # 2. Retry loop for main page load (up to 30 attempts, 5s sleep, total 150s)
    max_attempts = 30
    response = None
    
    for attempt in range(1, max_attempts + 1):
        try:
            print(f"Checking target URL (attempt {attempt}/{max_attempts})...")
            response = requests.get(base_url, timeout=10)
            if response.status_code == 200:
                print("Successfully loaded deployment main page (HTTP 200).")
                break
        except Exception as exc:
            print(f"Attempt {attempt} failed with exception: {exc}")
        
        time.sleep(5)
    
    if not response or response.status_code != 200:
        print("::error::Live deployment URL is not reachable or did not return HTTP 200.")
        if response:
            print(f"Status Code: {response.status_code}")
            print("--- RESPONSE HEADERS ---")
            print(response.headers)
            print("--- RESPONSE BODY (First 1000 chars) ---")
            print(response.text[:1000])
        return 1

    # 3. Verify main page renders successfully (check common tags)
    html_content = response.text
    
    # Search for Flutter Web markers: flt-glass-pane, flutter.js, main.dart.js, etc.
    flutter_markers = ["flutter.js", "main.dart.js", "manifest.json", "canvas", "flt-glass-pane", "viewport"]
    found_markers = [marker for marker in flutter_markers if marker in html_content]
    
    print(f"Found HTML structure markers: {found_markers}")
    if not found_markers:
        print("::warning::HTML does not contain typical Flutter Web bootstrap elements.")
    else:
        print("Main page structure validation passed.")

    # 4. Extract and verify CSS/JS assets from HTML
    # We find src="..." and href="..." references in index.html
    asset_urls = []
    
    # Simple regex to find relative scripts and stylesheets
    links = re.findall(r'href=["\']([^"\']+\.(?:css|json|png|ico))["\']', html_content)
    scripts = re.findall(r'src=["\']([^"\']+\.(?:js|png))["\']', html_content)
    
    raw_assets = list(set(links + scripts))
    for asset in raw_assets:
        # Ignore external HTTP/HTTPS assets
        if asset.startswith("http://") or asset.startswith("https://"):
            continue
        
        # Build absolute URL
        # Remove leading slash or relative prefix
        clean_asset = asset.lstrip("/")
        asset_url = base_url + clean_asset
        asset_urls.append((asset, asset_url))

    # Add standard Flutter scripts to check if not found
    standard_checks = [
        ("flutter.js", base_url + "flutter.js"),
        ("manifest.json", base_url + "manifest.json")
    ]
    for name, url in standard_checks:
        if url not in [x[1] for x in asset_urls]:
            asset_urls.append((name, url))

    print(f"Discovered {len(asset_urls)} assets to verify:")
    failed_assets = 0
    
    for name, url in asset_urls:
        try:
            asset_res = requests.head(url, timeout=5)
            # Accept 200, or 304, or 301/302 redirects
            if asset_res.status_code in [200, 304, 301, 302]:
                print(f"  ✓ {name} -> HTTP {asset_res.status_code}")
            else:
                # Retry with GET in case HEAD is not allowed
                get_res = requests.get(url, timeout=5)
                if get_res.status_code == 200:
                    print(f"  ✓ {name} -> HTTP 200 (GET)")
                else:
                    print(f"  ✗ {name} -> HTTP {get_res.status_code} (FAILED)")
                    failed_assets += 1
        except Exception as exc:
            print(f"  ✗ {name} -> Failed with error: {exc}")
            failed_assets += 1

    if failed_assets > 0:
        print(f"::error::{failed_assets} deployment assets failed to load.")
        return 1

    print("All deployment and asset checks PASSED successfully.")
    return 0

if __name__ == "__main__":
    sys.exit(verify_deployment())
