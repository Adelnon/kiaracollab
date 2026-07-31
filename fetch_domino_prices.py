#!/usr/bin/env python3
"""Look up Domino's Pizza menu prices for the store nearest a given ZIP code.

Uses Domino's own public ordering API (the same one order.dominos.com's
website calls) — no API key needed, just the stdlib for HTTP.

Run it with:

    python3 fetch_domino_prices.py 90210
    python3 fetch_domino_prices.py 90210 --filter pizza
    python3 fetch_domino_prices.py 90210 --limit 10
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

STORE_LOCATOR_URL = "https://order.dominos.com/power/store-locator"
MENU_URL_TEMPLATE = "https://order.dominos.com/power/store/{store_id}/menu"

# Domino's API rejects requests that don't look like they came from a browser.
HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; fetch_domino_prices/1.0)",
    "Referer": "https://order.dominos.com/en/pages/order/",
    "Accept": "application/json",
}


def _get_json(url, params):
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(f"{url}?{query}", headers=HEADERS)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def find_nearest_store(zip_code):
    data = _get_json(STORE_LOCATOR_URL, {"type": "Delivery", "s": "", "c": zip_code})
    stores = data.get("Stores") or []
    if not stores:
        raise ValueError(f"No Domino's stores found near {zip_code!r}")
    return min(stores, key=lambda store: store.get("MinDistance", float("inf")))


def fetch_menu_prices(store_id):
    menu = _get_json(MENU_URL_TEMPLATE.format(store_id=store_id), {"lang": "en", "structured": "true"})
    products = menu.get("Products", {})
    variants = menu.get("Variants", {})

    prices = []
    for variant_code, variant in variants.items():
        price = variant.get("Price")
        if price in (None, "", "0.00"):
            continue
        product = products.get(variant.get("ProductCode"), {})
        name = product.get("Name") or variant_code
        size = variant.get("Name") or ""
        label = f"{name} ({size})" if size and size != name else name
        prices.append((label, float(price)))

    prices.sort(key=lambda item: item[0])
    return prices


def main():
    parser = argparse.ArgumentParser(description="Fetch Domino's menu prices for the nearest store to a ZIP code.")
    parser.add_argument("zip_code", help="ZIP/postal code to search near")
    parser.add_argument("--filter", default=None, help="Only show items whose name contains this text (case-insensitive)")
    parser.add_argument("--limit", type=int, default=None, help="Show at most this many items")
    args = parser.parse_args()

    try:
        store = find_nearest_store(args.zip_code)
        prices = fetch_menu_prices(store["StoreID"])
    except (urllib.error.URLError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    if args.filter:
        needle = args.filter.lower()
        prices = [item for item in prices if needle in item[0].lower()]

    if args.limit:
        prices = prices[: args.limit]

    address = store.get("AddressDescription", "").strip().replace("\n", ", ")
    print(f"Nearest store: {address} (Store #{store['StoreID']})")
    print()

    if not prices:
        print("No matching menu items found.")
        return

    name_width = max(len(name) for name, _ in prices)
    for name, price in prices:
        print(f"{name:<{name_width}}  ${price:.2f}")


if __name__ == "__main__":
    main()
