"""Metriques materielles du Raspberry Pi, lues dans /proc et /sys.

Aucune dependance externe : psutil apporterait peu ici et alourdirait
l'installation sur un Pi.
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path

_THERMAL = Path("/sys/class/thermal/thermal_zone0/temp")
_MODEL = Path("/sys/firmware/devicetree/base/model")

# Bits renvoyes par `vcgencmd get_throttled`. Les bits bas decrivent l'etat
# courant, les bits hauts memorisent ce qui s'est produit depuis le demarrage.
_THROTTLE_FLAGS = {
    0: "under_voltage_now",
    1: "arm_frequency_capped_now",
    2: "currently_throttled",
    3: "soft_temperature_limit_now",
    16: "under_voltage_occurred",
    17: "arm_frequency_capped_occurred",
    18: "throttling_occurred",
    19: "soft_temperature_limit_occurred",
}


@dataclass(frozen=True)
class SystemStats:
    hostname: str
    model: str | None
    kernel: str | None
    uptime_seconds: int
    load_1: float
    load_5: float
    load_15: float
    cpu_temp_c: float | None
    mem_total_bytes: int | None
    mem_available_bytes: int | None
    throttled: dict

    def to_dict(self) -> dict:
        return asdict(self)


def _read_first_line(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip("\x00").strip()
    except OSError:
        return None


def uptime_seconds() -> int:
    raw = _read_first_line(Path("/proc/uptime"))
    if not raw:
        return 0
    try:
        return int(float(raw.split()[0]))
    except (ValueError, IndexError):
        return 0


def load_average() -> tuple[float, float, float]:
    raw = _read_first_line(Path("/proc/loadavg"))
    if not raw:
        return (0.0, 0.0, 0.0)
    parts = raw.split()
    try:
        return (float(parts[0]), float(parts[1]), float(parts[2]))
    except (ValueError, IndexError):
        return (0.0, 0.0, 0.0)


def cpu_temperature() -> float | None:
    raw = _read_first_line(_THERMAL)
    if not raw:
        return None
    try:
        # Exprimee en millidegres.
        return round(int(raw) / 1000.0, 1)
    except ValueError:
        return None


def memory() -> tuple[int | None, int | None]:
    try:
        content = Path("/proc/meminfo").read_text(encoding="utf-8")
    except OSError:
        return (None, None)

    values: dict[str, int] = {}
    for line in content.splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if parts:
            try:
                values[key] = int(parts[0]) * 1024  # exprime en kibioctets
            except ValueError:
                continue
    return (values.get("MemTotal"), values.get("MemAvailable"))


def throttled() -> dict:
    """Decode `vcgencmd get_throttled`.

    C'est le diagnostic le plus utile sur un Pi : une alimentation trop faible
    se manifeste par des corruptions de donnees et des services qui tombent,
    sans jamais rien laisser dans les journaux applicatifs.
    """
    binary = shutil.which("vcgencmd")
    if binary is None:
        return {"available": False}

    try:
        result = subprocess.run(
            [binary, "get_throttled"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return {"available": False}

    if result.returncode != 0 or "=" not in result.stdout:
        return {"available": False}

    try:
        value = int(result.stdout.strip().split("=")[1], 16)
    except (ValueError, IndexError):
        return {"available": False}

    flags = {name: bool(value & (1 << bit)) for bit, name in _THROTTLE_FLAGS.items()}
    flags["available"] = True
    flags["raw"] = value
    return flags


def collect() -> SystemStats:
    total, available = memory()
    one, five, fifteen = load_average()
    return SystemStats(
        hostname=_read_first_line(Path("/etc/hostname")) or "",
        model=_read_first_line(_MODEL),
        kernel=_read_first_line(Path("/proc/sys/kernel/osrelease")),
        uptime_seconds=uptime_seconds(),
        load_1=one,
        load_5=five,
        load_15=fifteen,
        cpu_temp_c=cpu_temperature(),
        mem_total_bytes=total,
        mem_available_bytes=available,
        throttled=throttled(),
    )
