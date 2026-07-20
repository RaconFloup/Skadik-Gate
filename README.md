# Skadik-Gate

VPN клиент для OpenWRT роутеров с интеграцией Remnawave панели.

## Возможности

- **Подписка**: Автоматическая загрузка серверов из Remnawave
- **Протоколы**: VLESS, Trojan, Shadowsocks
- **TPROXY**: Прозрачный прокси для всего LAN-трафика
- **Per-device**: Управление маршрутизацией по MAC/IP
- **Failover**: Автопереключение на запасной сервер
- **LuCI**: Веб-интерфейс для управления

## Установка

### Способ 1: Quick install (рекомендуется)

```bash
ssh root@router
wget -O /tmp/install.sh https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/install.sh
chmod +x /tmp/install.sh
/tmp/install.sh
```

### Способ 2: Package feed (для обновлений)

```bash
ssh root@router

# Добавь feed
wget -O /tmp/add-feed.sh https://raw.githubusercontent.com/RaconFloup/Skadik-Gate/main/add-feed.sh
chmod +x /tmp/add-feed.sh
/tmp/add-feed.sh

# Установи пакеты
opkg update
opkg install skadik-gate luci-app-skadik-gate
```

### Способ 3: .ipk пакеты

```bash
# Скопируй пакеты на роутер
scp build/ipk/*.ipk root@router:/tmp/

# Установи
ssh root@router
opkg install /tmp/skadik-gate_*.ipk /tmp/luci-app-skadik-gate_*.ipk
```

## Настройка

### 1. Укажи URL подписки

```bash
skadik-gate config set main.subscription_url "https://panel.com/api/v1/client/subscribe?token=XXX"
```

### 2. Загрузи серверы

```bash
skadik-gate sub update
skadik-gate sub list
```

### 3. Запусти VPN

```bash
skadik-gate start
```

### 4. LuCI интерфейс

Открой в браузере: `http://router-ip/cgi-bin/luci/admin/vpn/skadik-gate`

## CLI команды

```bash
skadik-gate status                    # Статус сервиса
skadik-gate start/stop/restart        # Управление

skadik-gate sub update                # Обновить подписку
skadik-gate sub list                  # Список нод
skadik-gate sub switch <node>         # Переключить ноду
skadik-gate sub test                  # Проверить связь

skadik-gate rules list                # Список правил
skadik-gate rules add "YouTube" direct domain "youtube.com"
skadik-gate rules add "Ads" block geosite "category-ads-all"

skadik-gate devices list              # Список устройств
skadik-gate devices add "Phone" "AA:BB:CC:DD:EE:FF" proxy
```

## Пакеты для сборки

```bash
# Windows
.\build.ps1

# Linux
./build.sh x86_64        # Для x86_64 роутеров
./build.sh aarch64       # Для ARM64 роутеров
./build-ipk.sh           # Без SDK
```

## Требования

- OpenWRT 24.10 или новее
- Пакеты: xray-core, curl, kmod-nft-tproxy, nftables, ip-full
- Для LuCI: luci-base, luci-compat

## Лицензия

AGPL-3.0
