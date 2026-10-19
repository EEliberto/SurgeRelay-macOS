#!/usr/bin/env python3
"""Surge Relay MCP stdio adapter. Python 3.9+, standard library only."""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid


def schema(properties=None, required=None):
    return {"type": "object", "properties": properties or {}, "required": required or [], "additionalProperties": False}


STRING = {"type": "string"}
ID = {"type": "string", "format": "uuid"}
TOOLS = [
    ("relay_status", "Read permissions and current diagnostics.", schema(), True),
    ("relay_list_modules", "List modules, sources and refresh failures.", schema(), True),
    ("relay_list_airports", "List airport subscriptions and cache availability.", schema(), True),
    ("relay_read_module", "Read module settings or exact editable content and its revision. Content can include private configuration; do not share it externally.", schema({"id": ID, "content": {"type": "boolean"}}, ["id"]), True),
    ("relay_read_airport", "Read airport settings and revision, or processed node names and filter results.", schema({"id": ID, "nodes": {"type": "boolean"}}, ["id"]), True),
    ("relay_read_configuration", "Read generated airport configuration preview and target/policy-file availability. Preview may contain private proxy credentials.", schema(), True),
    ("relay_search", "Search generated module content with module, section and line provenance.", schema({"q": STRING, "limit": {"type": "integer", "minimum": 1, "maximum": 500}}, ["q"]), True),
    ("relay_plan", "Preview a change without applying it. Read the latest revision first. Show the before/after to the user before applying. Unspecified settings are preserved.", schema({"kind": {"type": "string", "enum": ["module.content", "module.settings", "airport.settings"]}, "id": ID, "baseRevision": STRING, "content": STRING, "changes": {"type": "object"}}, ["kind", "id", "baseRevision"]), True),
    ("relay_apply", "Apply a previously reviewed plan. May synchronize outputs according to App settings. Fails if content changed since preview; never silently overwrite.", schema({"planID": ID}, ["planID"]), False),
    ("relay_start_job", "Start a refresh, publish, or write-airport-configuration task. Poll relay_job until finished. Refresh may automatically publish according to App settings.", schema({"action": {"type": "string", "enum": ["refreshModules", "refreshAirport", "publish", "writeAirports"]}, "id": ID}, ["action"]), False),
    ("relay_job", "Read completion/failure for a job, or list recent jobs.", schema({"id": ID}), True),
]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def api(path, payload=None):
    token = os.environ.get("SURGE_RELAY_TOKEN", "")
    if not token:
        raise ValueError("Set SURGE_RELAY_TOKEN from Surge Relay > Web 管理 > 自动化访问.")
    port = int(os.environ.get("SURGE_RELAY_PORT", "8787"))
    if not 1 <= port <= 65535:
        raise ValueError("SURGE_RELAY_PORT must be 1–65535.")
    request = urllib.request.Request(
        "http://127.0.0.1:%d/api/v1/%s" % (port, path),
        data=None if payload is None else json.dumps(payload).encode("utf-8"),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    # Do not send local credentials through a system proxy or redirects.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            message = json.load(error).get("message", "Request failed")
        except (ValueError, AttributeError):
            message = "Request failed"
        raise ValueError("HTTP %d: %s" % (error.code, message)) from None


def identifier(value):
    return str(uuid.UUID(value))


def call(name, args):
    definitions = {entry[0]: entry for entry in TOOLS}
    if not isinstance(name, str) or name not in definitions:
        raise ValueError("Unknown tool")
    spec = definitions[name][2]
    if not isinstance(args, dict) or set(args) - set(spec["properties"]) or any(k not in args for k in spec["required"]):
        raise ValueError("Invalid tool arguments")
    for key, value in args.items():
        kind = spec["properties"][key]["type"]
        if not {"string": isinstance(value, str), "boolean": isinstance(value, bool), "integer": type(value) is int, "object": isinstance(value, dict)}[kind]:
            raise ValueError("Invalid type for " + key)
    if name == "relay_status":
        return {"capabilities": api("capabilities"), "diagnostics": api("diagnostics")}
    if name == "relay_list_modules": return api("modules")
    if name == "relay_list_airports": return api("airports")
    if name == "relay_read_module": return api("modules/" + identifier(args["id"]) + ("/content" if args.get("content") else ""))
    if name == "relay_read_airport": return api("airports/" + identifier(args["id"]) + ("/nodes" if args.get("nodes") else ""))
    if name == "relay_read_configuration": return api("configuration")
    if name == "relay_search": return api("search?" + urllib.parse.urlencode(args))
    if name == "relay_plan": return api("plans", args)
    if name == "relay_apply": return api("plans/" + identifier(args["planID"]) + "/apply", {})
    if name == "relay_start_job": return api("jobs", args)
    if name == "relay_job": return api("jobs" + ("/" + identifier(args["id"]) if "id" in args else ""))
    raise ValueError("Unknown tool")


def handle(message):
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0" or not isinstance(message.get("method"), str):
        return {"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "Invalid Request"}}
    if "id" not in message: return None
    reply = {"jsonrpc": "2.0", "id": message["id"]}
    method, params = message["method"], message.get("params", {})
    if not isinstance(params, dict):
        reply["error"] = {"code": -32602, "message": "Invalid params"}
    elif method == "initialize":
        supported = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
        version = params.get("protocolVersion")
        reply["result"] = {"protocolVersion": version if version in supported else supported[-1], "capabilities": {"tools": {}}, "serverInfo": {"name": "surge-relay", "version": "261019"}, "instructions": "Read capabilities first. Preview changes with relay_plan and show the diff before relay_apply. Poll asynchronous jobs for the actual outcome."}
    elif method == "ping": reply["result"] = {}
    elif method == "tools/list":
        reply["result"] = {"tools": [{"name": name, "description": description, "inputSchema": spec, "annotations": {"readOnlyHint": readonly, "destructiveHint": not readonly, "openWorldHint": not readonly}} for name, description, spec, readonly in TOOLS]}
    elif method == "tools/call":
        try:
            result = call(params.get("name"), params.get("arguments", {}))
            reply["result"] = {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}], "isError": False}
        except (ValueError, OSError, urllib.error.URLError) as error:
            reply["result"] = {"content": [{"type": "text", "text": str(error)}], "isError": True}
    else: reply["error"] = {"code": -32601, "message": "Method not found"}
    return reply


def main():
    for line in sys.stdin:
        try:
            response = handle(json.loads(line))
        except ValueError:
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}
        if response is not None:
            print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__": main()
