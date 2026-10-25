#!/usr/bin/env python3
import ipaddress
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


API_BASE = "https://api.hosting.ionos.com/dns/v1"
IP_CHECK_URL = "https://api.ipify.org"
ZONE_NAME = "ridewood.co.uk"
TARGET_HOSTS = ("www.ridewood.co.uk",)
REQUEST_TIMEOUT = 20


def ionos_ssl_context():
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.set_ciphers("DEFAULT:@SECLEVEL=2")
    return context


def request_json(path, api_key, method="GET", payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {
        "Accept": "application/json",
        "User-Agent": "ridewood-ionos-ddns/1.0",
        "X-API-Key": api_key,
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{API_BASE}{path}", data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(
            request,
            context=ionos_ssl_context(),
            timeout=REQUEST_TIMEOUT,
        ) as response:
            response_body = response.read()
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"IONOS DNS API returned HTTP {error.code}") from None
    except urllib.error.URLError as error:
        raise RuntimeError(f"Could not reach the IONOS DNS API: {error.reason}") from None

    if not response_body:
        return {}
    try:
        return json.loads(response_body)
    except json.JSONDecodeError as error:
        raise RuntimeError("IONOS DNS API returned invalid JSON") from error


def get_public_ipv4():
    request = urllib.request.Request(
        IP_CHECK_URL,
        headers={"Accept": "text/plain", "User-Agent": "ridewood-ionos-ddns/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            value = response.read().decode("ascii").strip()
    except (urllib.error.URLError, UnicodeDecodeError) as error:
        raise RuntimeError(f"Could not determine the public IPv4 address: {error}") from None

    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as error:
        raise RuntimeError("The public IP service did not return a valid IPv4 address") from error
    if not address.is_global:
        raise RuntimeError("The public IP service returned a non-public address")
    return str(address)


def normalize_name(value):
    return value.rstrip(".").lower() if isinstance(value, str) else ""


def update_records(api_key, address):
    zones = request_json("/zones", api_key)
    matches = [
        zone for zone in zones
        if normalize_name(zone.get("name")) == ZONE_NAME
    ]
    if len(matches) != 1 or not matches[0].get("id"):
        raise RuntimeError("Could not identify exactly one IONOS ridewood.co.uk zone")

    zone_id = urllib.parse.quote(str(matches[0]["id"]), safe="")
    zone = request_json(f"/zones/{zone_id}", api_key)
    records = zone.get("records")
    if not isinstance(records, list):
        raise RuntimeError("IONOS zone response did not include its DNS records")

    for hostname in TARGET_HOSTS:
        matching_records = [
            record for record in records
            if normalize_name(record.get("name")) == hostname
            and record.get("type") == "A"
        ]
        if len(matching_records) != 1:
            raise RuntimeError(f"Expected exactly one A record for {hostname}")

        record = matching_records[0]
        if record.get("disabled"):
            raise RuntimeError(f"The IONOS A record for {hostname} is disabled")
        if record.get("content") == address:
            print(f"{hostname} already points to {address}")
            continue

        record_id = urllib.parse.quote(str(record.get("id", "")), safe="")
        if not record_id:
            raise RuntimeError(f"IONOS did not return a record ID for {hostname}")
        request_json(
            f"/zones/{zone_id}/records/{record_id}",
            api_key,
            method="PUT",
            payload={"content": address},
        )
        print(f"Updated {hostname} to {address}")


def main():
    api_key = os.environ.get("IONOS_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("IONOS_API_KEY is missing from /etc/ionos-ddns.conf")
    update_records(api_key, get_public_ipv4())


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print(error, file=sys.stderr)
        sys.exit(1)