"""Provision empty vaults without granting server administration to clients."""

import base64
import configparser
import json
import os
from pathlib import Path
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


def request(base_url, credentials, method, path, body=None, allowed=(200, 201, 202)):
    token = base64.b64encode(
        f"{credentials[0]}:{credentials[1]}".encode()
    ).decode()
    req = Request(
        base_url + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Basic " + token, "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urlopen(req, timeout=10) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code in allowed:
            return None
        # Do not log request headers, passwords or database contents.
        raise RuntimeError(f"{method} {path}: HTTP {error.code}") from None


def provision(base_url, credential_dir, databases):
    admin_ini = configparser.ConfigParser(interpolation=None)
    admin_ini.read(credential_dir / "admin.ini")
    admin = next(iter(admin_ini["admins"].items()))
    client = json.loads((credential_dir / "client.json").read_text())
    username = client["username"]

    for attempt in range(30):
        try:
            request(base_url, admin, "GET", "/_up")
            break
        except (RuntimeError, URLError, TimeoutError):
            if attempt == 29:
                raise
            time.sleep(1)

    for database in ("_users", "_replicator", "_global_changes", *databases):
        request(base_url, admin, "PUT", "/" + quote(database, safe=""), allowed=(412,))

    user_path = "/_users/" + quote("org.couchdb.user:" + username, safe="")
    existing = request(base_url, admin, "GET", user_path, allowed=(404,))
    # Avoid rewriting salted password hashes on every boot. Rotate the password
    # only if the provisioned account cannot authenticate with the desired one.
    authenticated = False
    if existing:
        try:
            session = request(base_url, (username, client["password"]), "GET", "/_session")
            authenticated = session["userCtx"]["name"] == username
        except RuntimeError:
            pass
    if not authenticated or existing.get("roles", []) != []:
        user = {
            "_id": "org.couchdb.user:" + username,
            "name": username,
            "type": "user",
            "roles": [],
            "password": client["password"],
        }
        if existing:
            user["_rev"] = existing["_rev"]
        request(base_url, admin, "PUT", user_path, user)

    for database in databases:
        request(base_url, admin, "PUT", "/" + quote(database, safe="") + "/_security", {
            "admins": {"names": [], "roles": []},
            "members": {"names": [username], "roles": []},
        })
    print("LiveSync account and vault databases ready: " + ", ".join(databases))


if __name__ == "__main__":
    provision("http://127.0.0.1:5984", Path(os.environ["CREDENTIALS_DIRECTORY"]), sys.argv[1:])
