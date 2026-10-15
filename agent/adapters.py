from datetime import datetime
import os
from urllib.parse import urlencode

from .http import JSONHTTP
from .tools import ToolFailure, navigation_action


class OpenMeteo:
    source = "open_meteo"
    is_mock = False

    def __init__(self, http=None):
        self.http = http or JSONHTTP()

    def execute(self, name, args, context):
        location = args["location"]
        if location["coordinate_system"] != "wgs84":
            raise ToolFailure("coordinate_mismatch", "天气接口需要 WGS-84 位置，不能将 GCJ-02 冒充 WGS-84")
        params = {"latitude": location["latitude"], "longitude": location["longitude"],
                  "hourly": "temperature_2m,precipitation_probability,wind_speed_10m,weather_code",
                  "wind_speed_unit": "kmh", "timezone": "Asia/Shanghai",
                  "start_date": args["date"], "end_date": args["date"]}
        payload = self.http.request("https://api.open-meteo.com/v1/forecast?" + urlencode(params))
        try:
            hourly = payload["hourly"]
            indices = [i for i, value in enumerate(hourly["time"]) if value[:10] == args["date"]
                       and 6 <= datetime.fromisoformat(value).hour <= 21]
            if len(indices) < 12:
                raise ToolFailure("no_data", "请求日期缺少完整的白天天气，不能作出判断")
            values = {key: [hourly[key][i] for i in indices] for key in (
                "temperature_2m", "precipitation_probability", "wind_speed_10m", "weather_code")}
            if any(v is None for items in values.values() for v in items):
                raise ToolFailure("no_data", "天气数据有缺失")
            return {"date": args["date"], "temperature_c": round(sum(values["temperature_2m"]) / len(indices), 1),
                    "precipitation_probability": max(values["precipitation_probability"]),
                    "wind_kph": max(values["wind_speed_10m"]),
                    "condition": "雷暴风险" if any(code >= 95 for code in values["weather_code"]) else "白天逐小时聚合",
                    "coverage": "daytime"}
        except (KeyError, TypeError, IndexError, ValueError):
            raise ToolFailure("invalid_response", "天气接口数据结构异常") from None


class AmapSearch:
    source = "amap_web"
    is_mock = False

    def __init__(self, http=None):
        self.http = http or JSONHTTP()

    def execute(self, name, args, context):
        key = os.environ.get("AMAP_API_KEY")
        if not key:
            raise ToolFailure("missing_api_key", "请设置 AMAP_API_KEY（Web 服务类型）")
        location = args["location"]
        coordinate = f"{location['longitude']:.6f},{location['latitude']:.6f}"
        if location["coordinate_system"] == "wgs84":
            converted = self.http.request("https://restapi.amap.com/v3/assistant/coordinate/convert?" + urlencode({
                "key": key, "locations": coordinate, "coordsys": "gps", "output": "JSON"}))
            if not isinstance(converted, dict) or converted.get("status") != "1":
                raise ToolFailure("coordinate_conversion_failed", "高德坐标转换失败；未继续搜索")
            coordinate = converted.get("locations", "")
            try:
                lon, lat = map(float, coordinate.split(","))
                if not (-180 <= lon <= 180 and -90 <= lat <= 90):
                    raise ValueError()
            except (ValueError, AttributeError):
                raise ToolFailure("invalid_response", "坐标转换响应无效")
        params = {"key": key, "location": coordinate, "keywords": args["query"],
                  "radius": args["radius_m"], "sortrule": "distance", "offset": 10,
                  "page": 1, "extensions": "base", "output": "JSON"}
        payload = self.http.request("https://restapi.amap.com/v3/place/around?" + urlencode(params))
        if not isinstance(payload, dict) or payload.get("status") != "1":
            raise ToolFailure("provider_rejected", "高德拒绝请求；请核查 Key 类型、额度与权限")
        try:
            places = []
            for item in payload["pois"]:
                longitude, latitude = map(float, item["location"].split(","))
                places.append({"id": "amap-" + item["id"], "name": item["name"],
                               "address": item.get("address") if isinstance(item.get("address"), str) else "",
                               "location": {"latitude": latitude, "longitude": longitude, "coordinate_system": "gcj02"},
                               "distance_m": float(item["distance"])})
            return {"candidates": places}
        except (KeyError, TypeError, ValueError, AttributeError):
            raise ToolFailure("invalid_response", "高德地点响应无效；未猜测地点") from None


class NavigationProposal:
    source = "uri_adapter"
    is_mock = False

    def execute(self, name, args, context):
        # Windows cannot detect an installed iPhone app. Emit both URLs for the Swift opener.
        return navigation_action(args, context)
