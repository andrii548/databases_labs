"""Database Initialization and Verification Utility.

Reads DB configuration from app/config/app.yml, verifies connection,
and optionally executes lab3.sql to initialize or reset tables.
"""

import os
import sys
import yaml
import pymysql


def get_db_config():
    config_path = os.path.join(os.path.dirname(__file__), "app", "config", "app.yml")
    if not os.path.exists(config_path):
        print(f"[-] Файл конфігурації не знайдено: {config_path}")
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}

    return config.get("database", {})


def verify_and_init():
    db_conf = get_db_config()
    user = db_conf.get("user", "root")
    password = db_conf.get("password", "")
    host = db_conf.get("host", "localhost")
    port = db_conf.get("port", 3306)
    db_name = db_conf.get("name", "flightradar_db")

    print(f"[i] Підключення до MySQL: {user}@{host}:{port}...")

    try:
        conn = pymysql.connect(
            host=host,
            user=user,
            password=password,
            port=port,
            charset="utf8mb4",
            autocommit=True,
        )
        print("[+] Успішно підключено до MySQL сервера!")
    except Exception as e:
        print(f"[-] Не вдалося підключитися до MySQL: {e}")
        print("[!] Переконайтеся, що служба MySQL запущена та пароль у app/config/app.yml вказано вірно.")
        return

    cursor = conn.cursor()

    cursor.execute("SHOW DATABASES LIKE %s", (db_name,))
    db_exists = cursor.fetchone()

    sql_file_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "lab3", "lab3.sql"))

    if not db_exists:
        print(f"[!] База даних '{db_name}' відсутня. Створюємо...")
        cursor.execute(f"CREATE DATABASE IF NOT EXISTS `{db_name}` DEFAULT CHARACTER SET utf8mb4;")
        print(f"[+] Базу даних '{db_name}' створено!")

    cursor.execute(f"USE `{db_name}`;")

    cursor.execute("SHOW TABLES;")
    tables = cursor.fetchall()

    if len(tables) >= 13:
        print(f"[+] База даних містить {len(tables)} таблиць:")
        for t in tables:
            print(f"    - {t[0]}")
        print("\n[+] База готова до роботи з REST API!")
    else:
        print(f"[!] У базі знайдено лише {len(tables)} таблиць. Потрібно імпортувати схему з {sql_file_path}")
        if os.path.exists(sql_file_path):
            print(f"[i] Імпортуємо SQL скрипт...")
            with open(sql_file_path, "r", encoding="utf-8") as sql_file:
                sql_commands = sql_file.read().split(";")
                for cmd in sql_commands:
                    cmd_clean = cmd.strip()
                    if cmd_clean:
                        try:
                            cursor.execute(cmd_clean)
                        except Exception as cmd_err:
                            print(f"[!] Помилка виконання команди: {cmd_err}")
            print(f"[+] Схему успішно імпортовано!")
        else:
            print(f"[-] Файл {sql_file_path} не знайдено.")

    cursor.close()
    conn.close()


if __name__ == "__main__":
    verify_and_init()

