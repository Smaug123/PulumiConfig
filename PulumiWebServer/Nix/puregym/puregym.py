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

    _all_gyms = {}
    _last_refreshed_gyms = datetime.min

    def _bad_request(self, text: str, code: int = 400) -> None:
        self.send_response(code)
        self.send_header('Content-type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(text.encode('utf-8'))

    def _get_fullness(self, gym_id: int) -> bytes:
        if abs(datetime.now() - self._last_accessed_by_id[gym_id]) > timedelta(seconds=30):
            token = subprocess.check_output(['cat', '/tmp/puregym_token']).strip()
            output = subprocess.check_output(
                [puregym, 'fullness', '--bearer-token', token, '--gym-id', str(gym_id)], text=True,
                encoding='utf-8')
            output = output.encode('utf-8')
            self._cache_result_by_id[gym_id] = output
            self._last_accessed_by_id[gym_id] = datetime.now()
        else:
            output = self._cache_result_by_id[gym_id]
        return output

    def _refresh_gyms(self) -> None:
        if self._last_refreshed_gyms < datetime.now() - timedelta(days=1):
            token = subprocess.check_output(['cat', '/tmp/puregym_token']).strip()
            output = subprocess.check_output(
                [puregym, 'all-gyms', '--bearer-token', token, '--terse', 'true'], text=True,
                encoding='utf-8')
            new_gyms = {}
            for line in output.splitlines():
                gym_id, gym_name = line.split(',')
                new_gyms[int(gym_id)] = gym_name
            self._all_gyms = new_gyms
            self._last_refreshed_gyms = datetime.now()

    def get_all_gyms(self, _query: dict[AnyStr, list[AnyStr]]) -> None:
        self._refresh_gyms()
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        for gym_id, gym_name in self._all_gyms.items():
            self.wfile.write(f'{gym_id}: {gym_name}\n'.encode())

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
            output = self._get_fullness(desired_gym_id)
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

    def get_prometheus(self, query: dict[AnyStr, list[AnyStr]]) -> None:
        query_gym = query.get("gym_id", None)
        if query_gym is None:
            self._bad_request('Must supply gym_id')
            return
        try:
            gym_id = [int(i) for i in query_gym]
        except ValueError:
            self._bad_request('at least one gym_id did not parse as an int')
            return

        if not gym_id:
            self._bad_request('supply at least one gym_id')
            return

        try:
            fullness = [(i, int(self._get_fullness(i).split(b' ')[0])) for i in gym_id]
        except ValueError:
            self._bad_request('at least one fullness did not yield an int', 500)
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self._refresh_gyms()
        for gym_id, fullness in fullness:
            gym_name = ''.join(c for c in self._all_gyms[gym_id] if c == ' ' or str.isalnum(c))
            self.wfile.write(f'fullness{{label="{gym_name}"}} {fullness}\n'.encode())

    _handlers: dict[str, Callable[["MyHandler", dict[AnyStr, list[AnyStr]]], None]] = {
        "/fullness": get_fullness,
        "/fullness-prometheus": get_prometheus,
        "/gym-mapping": get_all_gyms,
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
