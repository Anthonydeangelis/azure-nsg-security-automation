"""Reference VM proxy for the private dashboard; configure its two environment values."""

import logging
import os

import requests
from azure.identity import ManagedIdentityCredential
from flask import Flask, jsonify

app = Flask(__name__)
credential = ManagedIdentityCredential()

FUNCTION_URL = os.environ["FINDINGS_FUNCTION_URL"]
SCOPE = os.environ["FINDINGS_API_SCOPE"]


@app.get("/api/findings")
def get_findings():
    try:
        token = credential.get_token(SCOPE)
        response = requests.get(
            FUNCTION_URL,
            headers={"Authorization": f"Bearer {token.token}"},
            timeout=20,
            allow_redirects=False,
        )

        if response.status_code != 200:
            logging.error("Function returned HTTP %s", response.status_code)
            return jsonify(error="Could not retrieve findings."), 502

        return jsonify(response.json())

    except Exception:
        logging.exception("Could not retrieve findings.")
        return jsonify(error="Could not retrieve findings."), 502
