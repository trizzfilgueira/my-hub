import os


class Config:
    HUB_NAME: str = os.getenv("HUB_NAME", "My Hub")
    HUB_PORT: int = int(os.getenv("HUB_PORT", "8765"))
    HUB_TOKEN: str = os.getenv("HUB_TOKEN", "")
    HUB_PASSWORD_HASH: str = os.getenv("HUB_PASSWORD_HASH", "")
    HUB_VERSION: str = os.getenv("HUB_VERSION", "1.0.0")
    INSTALL_DATE: str = os.getenv("INSTALL_DATE", "")
    HOST_PROC: str = os.getenv("HOST_PROC", "/proc")
    HOST_SYS: str = os.getenv("HOST_SYS", "/sys")

    # JWT settings
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_DAYS: int = 30


cfg = Config()
