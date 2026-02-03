# ---------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ---------------------------------------------------------

import sys
import os

from generate_invoice import render_pdf
from flask import Flask, jsonify, request

binary_path = '';

app = Flask(__name__)

@app.route('/render', methods=['POST'])
def render():
    data = request.get_json()
    template_str = data.get("template")
    args = data.get("data", {})
    return jsonify({ 'base64': render_pdf(template_str, args, binary_path) })

if __name__ == '__main__':
    binary_path = sys.argv[1]
    
    app.run(debug=True, port=5000)


