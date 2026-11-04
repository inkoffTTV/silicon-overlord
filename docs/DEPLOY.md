# Как запустить сервер игры на своём VPS (пошагово, для новичка)

Эта инструкция для сервера с **Ubuntu 22.04 / 24.04** или **Debian 12** (у вас: 4 ядра, 8 ГБ, Германия).
Нигде ниже не нужно никому сообщать пароль или SSH-ключ — все команды вы вводите сами на своём сервере.

Что получится: игровой сервер работает постоянно, сам запускается после перезагрузки VPS, сохраняет все
компании в файл базы данных и раз в сутки делает резервную копию. Игроки подключаются к `ws://IP-сервера:7350/ws`
(или к `wss://ваш-домен/ws`, если настроите домен — см. шаг 10).

Сколько ресурсов нужно (замерено): 50 компаний на скорости ×8 одновременно — около 27 % одного ядра и ~75 МБ
памяти. Ваш VPS справится с запасом.

---

## Шаг 1. Войти на сервер

На своём компьютере откройте терминал (Windows: «PowerShell», macOS/Linux: «Терминал») и введите
(вместо `1.2.3.4` — IP вашего VPS из панели хостинга):

```
ssh root@1.2.3.4
```

Если хостинг выдал пользователя не `root`, пишите его имя вместо `root`. Все команды ниже начинаются с `sudo` —
это «выполнить с правами администратора». Если вы вошли как `root`, `sudo` тоже работает.

Копируйте команды по одной (или блоком) и нажимайте Enter. Строки, начинающиеся с `#`, — пояснения, их вводить не нужно.

## Шаг 2. Установить нужные программы

```
sudo apt update
sudo apt install -y python3 python3-venv python3-pip git
```

Проверка: `python3 --version` должен показать 3.10 или новее.

## Шаг 3. Скачать игру

```
sudo git clone https://github.com/inkoffTTV/silicon-overlord /opt/silicon-overlord
```

Игра окажется в папке `/opt/silicon-overlord`.

## Шаг 4. Создать отдельного пользователя для сервера

Так безопаснее: сервер не будет работать с правами администратора.

```
sudo useradd --system --no-create-home --shell /usr/sbin/nologin silicon
```

## Шаг 5. Установить библиотеки Python (в «виртуальное окружение»)

```
sudo python3 -m venv /opt/silicon-overlord/venv
sudo /opt/silicon-overlord/venv/bin/pip install -r /opt/silicon-overlord/server/requirements.txt
sudo mkdir -p /opt/silicon-overlord/server/data
sudo chown -R silicon:silicon /opt/silicon-overlord
```

## Шаг 6. Пробный запуск (по желанию, но полезно)

```
sudo -u silicon /opt/silicon-overlord/venv/bin/python /opt/silicon-overlord/server/main.py --port 7350 --data /opt/silicon-overlord/server/data
```

Должна появиться строка `Silicon Overlord server listening on ws://0.0.0.0:7350/ws`. Остановите сервер
клавишами **Ctrl+C** (он сохранит данные и выйдет).

Можно ещё прогнать встроенные тесты (около минуты, должно закончиться словами `ALL PASSED`):

```
cd /opt/silicon-overlord && sudo -u silicon venv/bin/python server/tests/run.py
```

## Шаг 7. Сделать из сервера службу (автозапуск)

```
sudo cp /opt/silicon-overlord/server/deploy/silicon-overlord.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now silicon-overlord
sudo systemctl status silicon-overlord
```

В выводе `status` должно быть зелёное **active (running)**. Выйти из просмотра — клавиша `q`.

Полезные команды:

| Что сделать | Команда |
|---|---|
| остановить | `sudo systemctl stop silicon-overlord` |
| запустить | `sudo systemctl start silicon-overlord` |
| перезапустить | `sudo systemctl restart silicon-overlord` |
| состояние | `sudo systemctl status silicon-overlord` |

При остановке и перезапуске сервер сначала сохраняет все компании (это занимает секунду).

## Шаг 8. Открыть порт 7350 в файрволе

**Важно: сначала разрешите SSH, иначе вы потеряете доступ к серверу!**

```
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 7350/tcp
sudo ufw enable
sudo ufw status
```

На вопрос `Proceed with operation (y|n)?` ответьте `y`. Если у хостинга есть свой файрвол в панели управления —
откройте там тоже порт **7350/TCP**.

Проверка с вашего компьютера: откройте в браузере `http://1.2.3.4:7350/health` (ваш IP). Должно показать `ok`.
В игре (клиент Godot) адрес сервера: `ws://1.2.3.4:7350/ws`.

## Шаг 9. Логи (журнал сервера)

```
# смотреть в реальном времени (выход — Ctrl+C)
sudo journalctl -u silicon-overlord -f
# последние 200 строк
sudo journalctl -u silicon-overlord -n 200
# за последний час
sudo journalctl -u silicon-overlord --since "1 hour ago"
```

Раз в 5 минут сервер пишет строку `stats:` — сколько компаний загружено, сколько игроков онлайн и сколько
процессорного времени уходит на игровой «тик». Ошибки помечены словом `ERROR`.

## Шаг 10 (по желанию). Домен и защищённое соединение wss://

Нужен домен (например, `game.example.ru`), у которого DNS-запись **A** указывает на IP вашего VPS (настраивается
у регистратора домена). Тогда можно поставить Caddy — он сам получит бесплатный HTTPS-сертификат.
Это ещё и полезно для игроков из России: соединение идёт через стандартный порт 443 и реже режется провайдерами.

```
sudo apt install -y caddy
sudo cp /opt/silicon-overlord/server/deploy/Caddyfile.example /etc/caddy/Caddyfile
sudo nano /etc/caddy/Caddyfile
```

В редакторе замените `game.example.com` на свой домен, сохраните (**Ctrl+O**, Enter) и выйдите (**Ctrl+X**). Затем:

```
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo systemctl reload caddy
```

Проверка: `https://ваш-домен/health` в браузере показывает `ok`. Адрес сервера для игры: `wss://ваш-домен/ws`.
Когда все игроки перешли на `wss://`, порт 7350 снаружи можно закрыть: `sudo ufw delete allow 7350/tcp`.

## Шаг 11. Обновление игры (когда вышла новая версия)

```
sudo -u silicon git -C /opt/silicon-overlord pull
sudo -u silicon /opt/silicon-overlord/venv/bin/pip install -r /opt/silicon-overlord/server/requirements.txt
sudo systemctl restart silicon-overlord
sudo systemctl status silicon-overlord
```

Сохранения не пропадают: они лежат в `server/data`, git их не трогает. Старые сохранения автоматически
переводятся на новую версию при загрузке компании.

## Шаг 12. Резервные копии

Все сохранения — это один файл `/opt/silicon-overlord/server/data/silicon.db` (рядом могут лежать служебные
`silicon.db-wal` и `silicon.db-shm`). Скрипт делает правильную копию даже во время игры:

```
sudo /opt/silicon-overlord/server/deploy/backup.sh
```

Копия появится в `/var/backups/silicon-overlord/` (сжатый файл `silicon-ГГГГММДД-ЧЧММ.db.gz`).

Автоматически каждый день в 04:30 (хранить 14 дней):

```
echo '30 4 * * * root /opt/silicon-overlord/server/deploy/backup.sh >/dev/null 2>&1' | sudo tee /etc/cron.d/silicon-overlord-backup
```

Скачать копии к себе на компьютер (команда вводится на ВАШЕМ компьютере, не на сервере):

```
scp root@1.2.3.4:/var/backups/silicon-overlord/*.db.gz .
```

Восстановить из копии (пример с файлом `silicon-20261104-0430.db.gz`):

```
sudo systemctl stop silicon-overlord
cd /opt/silicon-overlord/server/data
sudo rm -f silicon.db-wal silicon.db-shm
sudo sh -c 'gunzip -c /var/backups/silicon-overlord/silicon-20261104-0430.db.gz > silicon.db'
sudo chown silicon:silicon silicon.db
sudo systemctl start silicon-overlord
```

## Если что-то не работает

| Симптом | Что проверить |
|---|---|
| `status` показывает failed | `sudo journalctl -u silicon-overlord -n 50` — последняя ошибка внизу |
| `Address already in use` | порт занят: `sudo ss -ltnp \| grep 7350`, остановите лишний процесс или выберите другой порт в `/etc/systemd/system/silicon-overlord.service` (`--port`), затем `sudo systemctl daemon-reload && sudo systemctl restart silicon-overlord` |
| `/health` не открывается снаружи | файрвол: `sudo ufw status` (должно быть `7350/tcp ALLOW`), файрвол в панели хостинга |
| `ModuleNotFoundError` | не выполнен шаг 5 (pip install) |
| `Permission denied` в логах | `sudo chown -R silicon:silicon /opt/silicon-overlord` |

Параметры запуска (`server/main.py`): `--port` (по умолчанию 7350), `--data` (папка с базой), `--autosave`
(секунды между автосохранениями, 60), `--idle-unload` (через сколько секунд после ухода последнего игрока
компания выгружается из памяти, 60), `--log-level` (INFO/DEBUG/WARNING).
