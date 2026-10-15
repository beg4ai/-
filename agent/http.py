"""Bounded JSON HTTP transport; redact network errors and never follow redirects with keys."""
import json
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from .tools import ToolFailure


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class JSONHTTP:
    def __init__(self, timeout=20, retries=1):
        self.timeout, self.retries = timeout, retries
        self.opener = build_opener(NoRedirect())

    def request(self, url, *, body=None, headers=None):
        parsed = urlsplit(url)
        if parsed.username or parsed.password or parsed.fragment:
            raise ToolFailure("invalid_endpoint", "Endpoint 不允许包含凭据或 fragment")
        if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}):
            raise ToolFailure("insecure_endpoint", "远端 API 必须使用 HTTPS；HTTP 仅允许 loopback")
        data = json.dumps(body, ensure_ascii=False, allow_nan=False).encode() if body is not None else None
        request = Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
        for attempt in range(self.retries + 1):
            try:
                with self.opener.open(request, timeout=self.timeout) as response:
                    raw = response.read(1_048_577)
                    if len(raw) > 1_048_576:
                        raise ToolFailure("response_too_large", "API 响应超过 1 MiB")
                    try:
                        return json.loads(raw.decode("utf-8"), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                    except (ValueError, UnicodeError, RecursionError):
                        raise ToolFailure("invalid_json", "API 未返回有效 JSON")
            except HTTPError as error:
                retryable = error.code == 429 or error.code >= 500
                if attempt < self.retries and retryable:
                    time.sleep(0.2 * (attempt + 1))
                    continue
                raise ToolFailure("http_error", f"API HTTP {error.code}；未记录含凭据 URL 或响应内容", retryable) from None
            except (URLError, TimeoutError, OSError):
                if attempt < self.retries:
                    time.sleep(0.2 * (attempt + 1))
                    continue
                raise ToolFailure("network_unavailable", "网络不可用；本地数据保留，可稍后重试", True) from None
