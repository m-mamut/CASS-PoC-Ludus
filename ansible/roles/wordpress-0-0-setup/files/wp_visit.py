#!/usr/bin/env python3
# wp_visit.py — Firefox headless admin simulator for WordPress
# Visits blog posts and executes JS (XSS-friendly), logs alerts/console.

import os
import time
from urllib.parse import urljoin, urlparse
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

# --- Config via env -----------------------------------------------------------
BASE_URL  = os.getenv("BASE_URL", "http://localhost")
WP_USER   = os.getenv("WP_USER",  "admin")
WP_PASS   = os.getenv("WP_PASS",  "admin123")
BLOG_IDX  = os.getenv("BLOG_INDEX", f"{BASE_URL}/blog/")
INTERVAL  = int(os.getenv("INTERVAL_SECS", "10"))
HEADLESS  = os.getenv("HEADLESS", "1") != "0"  # HEADLESS=0 to see UI (outside Docker)

# --- Helpers ------------------------------------------------------------------
def ts() -> str:
    return time.strftime("%a %b %d %H:%M:%S %Z %Y", time.gmtime())

def is_wp_post_path(path: str) -> bool:
    """
    Accept:
      - /slug
      - /blog/slug
      - /YYYY/MM/slug  (classic WP date permalinks)
    Reject common non-post paths.
    """
    if not path or path == "/":
        return False

    bad_bits = (
        "/wp-", "/wp-admin", "/wp-json", "/feed", "/category", "/tag",
        "/page/", "/comments", "/author", "/search", "xmlrpc.php"
    )
    if any(b in path for b in bad_bits):
        return False

    segs = [s for s in path.split("/") if s]  # remove empty
    # /slug
    if len(segs) == 1:
        return True
    # /blog/slug
    if len(segs) == 2 and segs[0].lower() == "blog":
        return True
    # /YYYY/MM/slug
    if len(segs) >= 3 and segs[0].isdigit() and segs[1].isdigit():
        return True

    return False

def extract_post_links(base_url: str, hrefs: list[str]) -> list[str]:
    """Normalize hrefs, keep only same-host post-like URLs, dedup."""
    out = []
    base = urlparse(base_url)
    for h in hrefs:
        if not h:
            continue
        u = urljoin(base_url, h)  # handles relative -> absolute
        pu = urlparse(u)
        if pu.netloc != base.netloc:
            continue
        if is_wp_post_path(pu.path):
            # normalize: drop query/fragment
            out.append(f"{pu.scheme}://{pu.netloc}{pu.path}")
    return sorted(set(out))

def collect_posts(page) -> list[str]:
    """Try a few selector strategies, then fallback to all <a>."""
    # Theme-friendly selectors first (common in WP themes)
    selectors = [
        "article a[rel='bookmark']",
        ".entry-title a",
        "h2.entry-title a",
        "article .post-title a",
    ]
    for sel in selectors:
        try:
            hrefs = page.eval_on_selector_all(sel, "els => els.map(e => e.getAttribute('href'))")
            posts = extract_post_links(BASE_URL, hrefs)
            if posts:
                return posts
        except Exception:
            pass

    # Fallback: all anchors on the page
    hrefs = page.eval_on_selector_all("a", "els => els.map(e => e.getAttribute('href'))")
    return extract_post_links(BASE_URL, hrefs)

# --- Main ---------------------------------------------------------------------
def main():
    print(f"=== Visiting WordPress at {ts()} ===")
    print("Logging in (Firefox/Playwright)...")

    with sync_playwright() as p:
        browser = p.firefox.launch(headless=HEADLESS, args=["--no-sandbox"])
        ctx = browser.new_context()
        page = ctx.new_page()

        # Log browser console & JS dialogs (alerts often used in XSS demos)
        def on_console(m):
            try:
                print(f"[{ts()}] console.{m.type}: {m.text}")
            except Exception as e:
                print(f"[{ts()}] [console-handler error] {e}")
        page.on("console", on_console)

        def on_dialog(d):
            try:
                print(f"[{ts()}] JS dialog: {d.message}")
            finally:
                d.dismiss()
        page.on("dialog", on_dialog)

        # --- Robust login ------------------------------------------------------
        for _ in range(30):
            try:
                page.goto(f"{BASE_URL}/wp-login.php", wait_until="domcontentloaded", timeout=5000)
                break
            except PWTimeout:
                time.sleep(1)

        page.wait_for_selector("#user_login", timeout=15000)
        page.fill("#user_login", WP_USER)
        page.fill("#user_pass", WP_PASS)
        try:
            page.check("#rememberme")
        except Exception:
            pass
        page.click("#wp-submit")
        page.wait_for_url("**/wp-admin/**", timeout=15000)
        print("Login OK")

        # --- First collect from /blog/ ----------------------------------------
        print(f"Fetching blog index: {BLOG_IDX}")
        page.goto(BLOG_IDX, wait_until="domcontentloaded")
        posts = collect_posts(page)
        print(f"Found {len(posts)} posts (supports /slug, /blog/slug, /YYYY/MM/slug):")
        for u in posts:
            print(" -", u)
        if not posts:
            print("No posts found yet; will keep checking the index.")

        # --- Visit loop --------------------------------------------------------
        while True:
            # Visit each post (executes JS on the page)
            for u in posts:
                print(f"[{ts()}] ADMIN (FF) visiting: {u}")
                try:
                    page.goto(u, wait_until="networkidle")
                    page.wait_for_timeout(800)  # let JS/XSS run
                except Exception as e:
                    print(f"[{ts()}] Visit error for {u}: {e}")

            # Re-scan index every round to catch new posts
            try:
                page.goto(BLOG_IDX, wait_until="domcontentloaded")
                new_posts = collect_posts(page)
                if set(new_posts) != set(posts):
                    added = [u for u in new_posts if u not in posts]
                    removed = [u for u in posts if u not in new_posts]
                    posts = new_posts
                    print(f"[{ts()}] Updated posts list: {len(posts)} total.")
                    if added:
                        print("  + added:")
                        for u in added: print("    -", u)
                    if removed:
                        print("  - removed:")
                        for u in removed: print("    -", u)
            except Exception as e:
                print(f"[{ts()}] Error while refreshing posts: {e}")

            time.sleep(INTERVAL)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

