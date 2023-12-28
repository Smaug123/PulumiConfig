from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess
import os
from datetime import datetime, timedelta
from typing import AnyStr, Callable
from urllib.parse import urlparse, parse_qs
from collections import defaultdict


class MyHandler(BaseHTTPRequestHandler):
    _cache_result_by_id = {}
    _cache_result_by_name = {}
    _last_accessed_by_id = defaultdict(lambda: datetime.min)
    _last_accessed_by_name = defaultdict(lambda: datetime.min)

    def _bad_request(self, text: str, code: int = 400) -> None:
        self.send_response(code)
        self.send_header('Content-type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(text.encode('utf-8'))

    def get_fullness(self, query: dict[AnyStr, list[AnyStr]]) -> None:
        desired_gym_name = None
        query_gym = query.get("gym_name", None)
        if query_gym is not None:
            if not len(query_gym) == 1:
                self._bad_request('Send only one gym_name')
                return
            desired_gym_name = query_gym[0]

        query_gym = query.get("gym_id", None)
        if query_gym is not None:
            if desired_gym_name is not None:
                self._bad_request('Cannot supply both gym_id and gym_name')
                return
            if not len(query_gym) == 1:
                self._bad_request('Send only one gym_id')
                return
            try:
                desired_gym_id = int(query_gym[0])
            except ValueError:
                self._bad_request('gym_id did not parse as an int')
                return
        elif desired_gym_name is None:
            # London Oval
            desired_gym_id = 19
        else:
            desired_gym_id = None

        if desired_gym_id is not None:
            if abs(datetime.now() - self._last_accessed_by_id[desired_gym_id]) > timedelta(seconds=30):
                token = subprocess.check_output(['cat', '/tmp/puregym_token']).strip()
                output = subprocess.check_output(
                    [puregym, 'fullness', '--bearer-token', token, '--gym-id', str(desired_gym_id)], text=True,
                    encoding='utf-8')
                output = output.encode('utf-8')
                self._cache_result_by_id[desired_gym_id] = output
                self._last_accessed_by_id[desired_gym_id] = datetime.now()
            else:
                output = self._cache_result_by_id[desired_gym_id]
        elif desired_gym_name is not None:
            if abs(datetime.now() - self._last_accessed_by_name[desired_gym_name]) > timedelta(seconds=30):
                token = subprocess.check_output(['cat', '/tmp/puregym_token']).strip()
                completed_process = subprocess.run(
                    [puregym, 'fullness', '--bearer-token', token, '--gym-name', desired_gym_name], text=True,
                    encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
                output = completed_process.stderr + '\n' + completed_process.stdout
                output = output.encode('utf-8')
                self._cache_result_by_name[desired_gym_name] = output
                self._last_accessed_by_id[desired_gym_name] = datetime.now()
            else:
                output = self._cache_result_by_name[desired_gym_name]
        else:
            self._bad_request('Logic error: server reached impossible flow', 500)
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(output)

    _handlers: dict[str, Callable[["MyHandler", dict[AnyStr, list[AnyStr]]], None]] = {
        "/fullness": get_fullness
    }

    def do_GET(self):
        parsed_path = urlparse(self.path)
        handler = self._handlers.get(str(parsed_path.path), None)
        if handler is None:
            self._bad_request(f"Unrecognised endpoint. Available: {' '.join(self._handlers.keys())}")
        else:
            params = parse_qs(parsed_path.query)
            handler(self, params)


if __name__ == '__main__':
    puregym = os.environ["PUREGYM_CLIENT"]
    port = int(os.environ["PUREGYM_PORT"])
    server = HTTPServer(('localhost', port), MyHandler)
    server.serve_forever()
