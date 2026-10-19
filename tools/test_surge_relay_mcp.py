import importlib.util
import json
import os
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('surge-relay-mcp.py')
spec = importlib.util.spec_from_file_location('relay_mcp', SCRIPT)
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)

class AdapterTests(unittest.TestCase):
    def test_stdio_initialization_notifications_and_tools(self):
        messages = [
            {'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25'}},
            {'jsonrpc':'2.0','method':'notifications/initialized'},
            {'jsonrpc':'2.0','id':2,'method':'tools/list'},
            {'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'bad','arguments':{}}},
        ]
        process = subprocess.run([sys.executable,str(SCRIPT)], input='\n'.join(map(json.dumps,messages))+'\n', text=True,capture_output=True,check=True)
        replies = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(len(replies),3)
        self.assertEqual(replies[0]['result']['protocolVersion'],'2025-11-25')
        self.assertEqual(len(replies[1]['result']['tools']),11)
        self.assertTrue(replies[2]['result']['isError'])
        self.assertFalse(process.stderr)

    def test_api_uses_local_url_bearer_and_no_proxy(self):
        seen = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append((self.path,self.headers.get('Authorization')))
                self.send_response(200);self.end_headers();self.wfile.write(b'{"ok":true}')
            def log_message(self,*args): pass
        server=HTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            with patch.dict(os.environ,{'SURGE_RELAY_TOKEN':'test-token','SURGE_RELAY_PORT':str(server.server_port),'http_proxy':'http://127.0.0.1:1'}):
                self.assertEqual(mcp.call('relay_search',{'q':'a&b'}),{'ok':True})
            self.assertEqual(seen,[('/api/v1/search?q=a%26b','Bearer test-token')])
        finally: server.shutdown();server.server_close();thread.join()

    def test_redirect_is_not_followed(self):
        self.assertIsNone(mcp.NoRedirect().redirect_request(None,None,302,'',{},'https://example.com'))
        with self.assertRaises(ValueError): mcp.call('relay_apply',{'planID':'../../api/settings'})
        with self.assertRaises(ValueError): mcp.call('relay_plan',{'kind':'module.settings'})
        self.assertEqual(mcp.handle([])['error']['code'],-32600)

if __name__=='__main__':unittest.main()
