import json
import unittest
from unittest.mock import patch
from urllib.request import Request

import ionos_ddns_update as updater


class JsonResponse:
    def __init__(self, value):
        self.body = json.dumps(value).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self.body


class IonosUpdateTests(unittest.TestCase):
    def test_updates_only_the_www_a_record(self):
        zone = {
            "records": [
                {"id": "www-id", "name": "www.ridewood.co.uk", "type": "A", "content": "198.51.100.2"},
                {"id": "network-id", "name": "network.ridewood.co.uk", "type": "A", "content": "198.51.100.2"},
                {"id": "mail-id", "name": "mail.ridewood.co.uk", "type": "A", "content": "198.51.100.3"},
            ]
        }
        replies = [
            JsonResponse([{"id": "zone-id", "name": "ridewood.co.uk"}]),
            JsonResponse(zone),
            JsonResponse({"id": "www-id"}),
        ]

        with patch.object(updater.urllib.request, "urlopen", side_effect=replies) as urlopen:
            updater.update_records("test-prefix.test-secret", "203.0.113.10")

        requests = [call.args[0] for call in urlopen.call_args_list]
        updates = [request for request in requests if request.get_method() == "PUT"]
        self.assertEqual(len(updates), 1)
        self.assertEqual(
            [request.full_url.rsplit("/", 1)[-1] for request in updates],
            ["www-id"],
        )
        self.assertEqual(
            [json.loads(request.data) for request in updates],
            [{"content": "203.0.113.10"}],
        )
        self.assertTrue(all(isinstance(request, Request) for request in requests))

    def test_does_not_write_when_records_already_match(self):
        zone = {
            "records": [
                {"id": "www-id", "name": "www.ridewood.co.uk", "type": "A", "content": "203.0.113.10"},
                {"id": "network-id", "name": "network.ridewood.co.uk", "type": "A", "content": "198.51.100.3"},
            ]
        }
        replies = [
            JsonResponse([{"id": "zone-id", "name": "ridewood.co.uk"}]),
            JsonResponse(zone),
        ]

        with patch.object(updater.urllib.request, "urlopen", side_effect=replies) as urlopen:
            updater.update_records("test-prefix.test-secret", "203.0.113.10")

        self.assertEqual(urlopen.call_count, 2)


if __name__ == "__main__":
    unittest.main()