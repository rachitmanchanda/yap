import json
import tempfile
import unittest
import urllib.error
from pathlib import Path

from hinglish_eval.backend import BackendConfiguration, YAPBackendClient


class BackendTests(unittest.TestCase):
    def test_pipeline_uses_translit_and_enhancement_contract(self) -> None:
        requests = []
        timeouts = []

        def transport(request, timeout):
            requests.append(request)
            timeouts.append(timeout)
            if request.full_url.endswith("/transcribe"):
                body = request.data
                self.assertIn(b'name="mode"', body)
                self.assertIn(b"translit", body)
                self.assertIn(b'name="language_code"', body)
                self.assertIn(b'name="provider"', body)
                self.assertIn(b"sarvam", body)
                return 200, json.dumps({"transcript": "kal meeting hai", "provider": "sarvam"}).encode()
            payload = json.loads(request.data)
            self.assertEqual(payload["operation"], "enhance")
            self.assertEqual(payload["text"], "kal meeting hai")
            return 200, json.dumps({"text": "Kal meeting hai.", "provider": "deepseek"}).encode()

        with tempfile.TemporaryDirectory() as temporary:
            audio = Path(temporary) / "clip.m4a"
            audio.write_bytes(b"recorded-audio")
            client = YAPBackendClient(
                BackendConfiguration("https://example.invalid", "public-key"),
                transport=transport,
            )
            result = client.run_pipeline(audio, provider="sarvam", known_terms=["Rachit"])

        self.assertEqual(len(requests), 2)
        self.assertEqual(timeouts, [8.0, 2.5])
        self.assertEqual(result.raw_asr, "kal meeting hai")
        self.assertEqual(result.final_text, "Kal meeting hai.")

    def test_retries_transient_failures_without_jitter(self) -> None:
        attempts = 0
        sleeps = []

        def transport(request, timeout):
            nonlocal attempts
            attempts += 1
            if attempts < 3:
                raise urllib.error.HTTPError(request.full_url, 503, "unavailable", {}, None)
            return 200, b'{"text":"done"}'

        client = YAPBackendClient(
            BackendConfiguration("https://example.invalid", "public-key"),
            retries=2,
            transport=transport,
            sleep=sleeps.append,
        )
        result = client.transcribe(Path(__file__), provider="sarvam", known_terms=[])
        self.assertEqual(result["text"], "done")
        self.assertEqual(sleeps, [1, 2])

    def test_does_not_retry_client_error(self) -> None:
        attempts = 0

        def transport(request, timeout):
            nonlocal attempts
            attempts += 1
            raise urllib.error.HTTPError(request.full_url, 400, "bad request", {}, None)

        client = YAPBackendClient(
            BackendConfiguration("https://example.invalid", "public-key"),
            retries=2,
            transport=transport,
            sleep=lambda _: None,
        )
        with self.assertRaisesRegex(RuntimeError, "request failed"):
            client.enhance("test", known_terms=[])
        self.assertEqual(attempts, 1)

    def test_rejects_malformed_json(self) -> None:
        client = YAPBackendClient(
            BackendConfiguration("https://example.invalid", "public-key"),
            transport=lambda request, timeout: (200, b"not-json"),
        )
        with self.assertRaisesRegex(RuntimeError, "malformed JSON"):
            client.enhance("test", known_terms=[])

    def test_pipeline_falls_back_to_raw_when_enhancement_fails(self) -> None:
        def transport(request, timeout):
            if request.full_url.endswith("/transcribe"):
                return 200, b'{"transcript":"kal meeting hai","provider":"sarvam"}'
            raise TimeoutError("rewrite exceeded budget")

        with tempfile.TemporaryDirectory() as temporary:
            audio = Path(temporary) / "clip.m4a"
            audio.write_bytes(b"recorded-audio")
            client = YAPBackendClient(
                BackendConfiguration("https://example.invalid", "public-key"),
                transport=transport,
                sleep=lambda _: None,
            )
            result = client.run_pipeline(audio, provider="sarvam")
        self.assertEqual(result.final_text, "kal meeting hai")
        self.assertIn("rewrite request failed", result.enhancement_error)

    def test_rejects_silent_provider_fallback(self) -> None:
        def transport(request, timeout):
            return 200, b'{"transcript":"kal meeting hai","provider":"sarvam"}'

        with tempfile.TemporaryDirectory() as temporary:
            audio = Path(temporary) / "clip.m4a"
            audio.write_bytes(b"recorded-audio")
            client = YAPBackendClient(
                BackendConfiguration("https://example.invalid", "public-key"),
                transport=transport,
            )
            with self.assertRaisesRegex(RuntimeError, "deploy provider routing"):
                client.run_pipeline(audio, provider="whisper")

    def test_apple_provider_uses_local_bridge_then_enhancement(self) -> None:
        class Bridge:
            def transcribe(self, audio_file):
                return "kal meeting hai"

            def normalize(self, text):
                return text

        requests = []

        def transport(request, timeout):
            requests.append(request)
            return 200, b'{"text":"Kal meeting hai.","provider":"deepseek"}'

        with tempfile.TemporaryDirectory() as temporary:
            audio = Path(temporary) / "clip.m4a"
            audio.write_bytes(b"recorded-audio")
            client = YAPBackendClient(
                BackendConfiguration("https://example.invalid", "public-key"),
                transport=transport,
                apple_bridge=Bridge(),
            )
            result = client.run_pipeline(audio, provider="apple")
        self.assertEqual(len(requests), 1)
        self.assertTrue(requests[0].full_url.endswith("/rewrite"))
        self.assertEqual(result.asr_provider, "apple")


if __name__ == "__main__":
    unittest.main()
