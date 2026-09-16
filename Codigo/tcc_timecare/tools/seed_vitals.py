#!/usr/bin/env python3
"""Populate or clear simulated ESP32 vital-sign readings in Firebase RTDB.

The script uses the same REST endpoint as the Flutter app and only requires
Python 3. It is intended for local development before the physical sensor is
available.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_URL = "https://time-care-642b1-default-rtdb.firebaseio.com"
DEFAULT_PATH = "user_test/sinais_vitais"


def request(base_url: str, path: str, method: str, payload: object | None = None) -> object | None:
    url = f"{base_url.rstrip('/')}/{path.strip('/')}.json"
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with urlopen(req, timeout=15) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Firebase respondeu {error.code}: {details}") from error
    except URLError as error:
        raise RuntimeError(f"Não foi possível acessar o Firebase: {error.reason}") from error


def simulated_readings(count: int, interval_minutes: int, start: datetime, outlier_count: int) -> dict[str, dict[str, object]]:
    readings: dict[str, dict[str, object]] = {}
    # Spread test anomalies through the middle of the series. Keeping them away
    # from both ends makes the robust baseline test less dependent on ordering.
    positions = {
        round((index + 1) * (count - 1) / (outlier_count + 1))
        for index in range(outlier_count)
    }
    for index in range(count):
        timestamp = start + timedelta(minutes=index * interval_minutes)
        milliseconds = int(timestamp.timestamp() * 1000)
        # Values are intentionally plausible, not clinical recommendations.
        measurement: dict[str, object] = {
            "timestamp": milliseconds,
            "bpm": random.randint(62, 88),
            "spo2": random.randint(96, 100),
            "temperatura": round(random.uniform(36.1, 37.1), 1),
            "source": "simulated",
            "simulated": True,
        }
        if index in positions:
            # Deliberately atypical but medically plausible values for testing
            # the personal-baseline outlier screen. They are not diagnoses.
            measurement.update({
                "bpm": random.choice((130, 145, 155)),
                "spo2": random.choice((86, 88, 90)),
                "temperatura": random.choice((38.8, 39.2, 39.5)),
                "simulatedOutlier": True,
            })
        readings[str(milliseconds)] = measurement
    return readings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Gerencia dados simulados de sinais vitais no Firebase.")
    parser.add_argument("command", choices=("seed", "clear"), help="seed cria medições; clear apaga o nó configurado.")
    parser.add_argument("--base-url", default=DEFAULT_URL, help="URL do Firebase Realtime Database.")
    parser.add_argument("--path", default=DEFAULT_PATH, help="Nó do banco a manipular.")
    parser.add_argument("--count", type=int, default=57, help="Quantidade de leituras para seed (padrão: 57).")
    parser.add_argument("--interval-minutes", type=int, default=360, help="Intervalo entre leituras (padrão: 360 / 6 horas).")
    parser.add_argument("--start", help="Início em ISO-8601; padrão: últimas N medições até agora.")
    parser.add_argument("--outliers", type=int, default=3, help="Quantidade de leituras atípicas para teste (padrão: 3; use 0 para desativar).")
    parser.add_argument("--confirm-clear", action="store_true", help="Obrigatório para executar clear.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "clear":
        if not args.confirm_clear:
            print("Operação bloqueada: use --confirm-clear para apagar todas as medições desse nó.", file=sys.stderr)
            return 2
        request(args.base_url, args.path, "DELETE")
        print(f"Medições removidas de '{args.path}'.")
        return 0

    if args.count < 1 or args.interval_minutes < 1 or args.outliers < 0 or args.outliers >= args.count:
        print("--count e --interval-minutes precisam ser maiores que zero; --outliers deve ser entre 0 e count-1.", file=sys.stderr)
        return 2
    if args.start:
        start = datetime.fromisoformat(args.start.replace("Z", "+00:00"))
        if start.tzinfo is None:
            start = start.replace(tzinfo=timezone.utc)
    else:
        start = datetime.now(timezone.utc) - timedelta(minutes=args.count * args.interval_minutes)
    readings = simulated_readings(args.count, args.interval_minutes, start, args.outliers)
    request(args.base_url, args.path, "PATCH", readings)
    print(f"{len(readings)} medições simuladas inseridas em '{args.path}' ({args.outliers} atípicas para teste).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"Erro: {error}", file=sys.stderr)
        raise SystemExit(1)
