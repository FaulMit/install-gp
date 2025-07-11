#!/bin/bash

# Название архива с установочным файлом GlobalProtect для версий < 23.10
ARCHIVE_NAME="PanGPLinux-6.1.0-c45.tgz"
# Название DEB-пакета GlobalProtect для версий < 23.10
# ВНИМАНИЕ: Это предположительное имя DEB-пакета, проверьте его актуальность после распаковки!
DEB_PACKAGE_NAME="GlobalProtect_UI_deb-6.1.0.0-44.deb"
# Прямая ссылка для скачивания архива GlobalProtect
DOWNLOAD_GP_URL="https://cloud.rozetka.ua/s/og7BDCJDPsMfrmA/download/PanGPLinux-6.1.0-c45.tgz"

# Имя файла сертификата и ссылка для его скачивания
CERT_FILENAME="Root256.crt"
CERT_DOWNLOAD_URL="https://lake.rozetka.com.ua/PUPCA.cer"


echo "Начинаем автоматическую установку GlobalProtect и настройку сертификатов для Ubuntu < 23.10..."

# Переходим в директорию, где находится скрипт, для удобства работы с файлами
echo "Переходим в директорию, где находится скрипт: $(dirname "$0")"
cd "$(dirname "$0")"

# --- Шаг 1: Автоматическая установка корневого сертификата в ОС ---
echo "--- Установка корневого сертификата в ОС Linux ---"

# Создаем директорию для дополнительных сертификатов, если ее нет
echo "Создание директории /usr/share/ca-certificates/extra/..."
sudo mkdir -p /usr/share/ca-certificates/extra/

# Скачиваем сертификат
echo "Скачиваем сертификат с $CERT_DOWNLOAD_URL и сохраняем как $CERT_FILENAME..."
sudo wget -O /etc/ssl/certs/"$CERT_FILENAME" "$CERT_DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось скачать сертификат '$CERT_FILENAME' с '$CERT_DOWNLOAD_URL'."
    echo "Пожалуйста, проверьте ссылку или ваше интернет-соединение."
    exit 1
fi

# Копируем сертификат в системное хранилище
echo "Копируем сертификат в /usr/share/ca-certificates/extra/..."
sudo cp /etc/ssl/certs/"$CERT_FILENAME" /usr/share/ca-certificates/extra/"$CERT_FILENAME"

# Добавляем сертификат в конфигурационный файл ca-certificates, если его там нет
echo "Добавляем запись о сертификате в /etc/ca-certificates.conf, если ее нет..."
if [[ $(grep "extra/${CERT_FILENAME}" /etc/ca-certificates.conf | wc -l) == 0 ]]; then
    # Делаем резервную копию файла перед изменением
    sudo cp /etc/ca-certificates.conf /etc/ca-certificates.conf.bak
    echo "extra/$CERT_FILENAME" | sudo tee -a /etc/ca-certificates.conf > /dev/null
    echo "Запись о сертификате добавлена в /etc/ca-certificates.conf."
else
    echo "Запись о сертификате уже существует в /etc/ca-certificates.conf."
fi

# Обновляем системные сертификаты
echo "Обновляем системные сертификаты..."
sudo update-ca-certificates
echo "Установка корневого сертификата в ОС завершена."

# --- Шаг 2: Обновление списка пакетов и их обновление ---
echo "--- Обновляем список пакетов и устанавливаем обновления ---"
sudo apt update && sudo apt upgrade -y

# --- Шаг 3: Загрузка архива GlobalProtect ---
echo "--- Скачиваем архив с GlobalProtect по прямой ссылке: $DOWNLOAD_GP_URL ---"
# Используем -O для сохранения файла под заданным именем ARCHIVE_NAME
wget "$DOWNLOAD_GP_URL" -O "$ARCHIVE_NAME"

# Проверяем, успешно ли скачался архив GlobalProtect
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось скачать архив GlobalProtect '$ARCHIVE_NAME' с '$DOWNLOAD_GP_URL'."
    echo "Пожалуйста, проверьте ссылку или ваше интернет-соединение."
    exit 1
fi
echo "Архив GlobalProtect '$ARCHIVE_NAME' успешно скачан."

# --- Шаг 4: Разархивирование файла GlobalProtect ---
echo "--- Разархивируем $ARCHIVE_NAME ---"
if [ -f "$ARCHIVE_NAME" ]; then
    tar -xvf "./$ARCHIVE_NAME"
    echo "Архив GlobalProtect успешно разархивирован."
else
    echo "Ошибка: Архив GlobalProtect $ARCHIVE_NAME не найден после скачивания. Это неожиданно."
    exit 1
fi

# --- Шаг 5: Запуск установки приложения GlobalProtect (с помощью dpkg) ---
echo "--- Запускаем установку GlobalProtect с помощью dpkg ---"
if [ -f "$DEB_PACKAGE_NAME" ]; then
    # Используем dpkg -i для установки .deb пакета
    sudo dpkg -i "./$DEB_PACKAGE_NAME"
    # Решаем возможные зависимости, если dpkg выдал ошибки
    sudo apt --fix-broken install -y
    echo "GlobalProtect успешно установлен."
else
    echo "Ошибка: DEB-пакет $DEB_PACKAGE_NAME не найден. Убедитесь, что он был разархивирован из архива."
    exit 1
fi

# --- Шаг 6: Настройка DNS (для Ubuntu с systemd-resolved) ---
echo "--- Редактируем /etc/systemd/resolved.conf ---"
# Проверяем, существует ли строка DNSStubListenerExtra=127.0.0.1:53
if grep -q "DNSStubListenerExtra=127.0.0.1:53" /etc/systemd/resolved.conf; then
    echo "Строка 'DNSStubListenerExtra=127.0.0.1:53' уже присутствует в /etc/systemd/resolved.conf."
elif grep -q "DNSStubListenerExtra=" /etc/systemd/resolved.conf; then
    # Если есть другая строка DNSStubListenerExtra, заменяем её
    sudo sed -i 's/^#\?DNSStubListenerExtra=.*/DNSStubListenerExtra=127.0.0.1:53/' /etc/systemd/resolved.conf
    echo "Строка 'DNSStubListenerExtra' обновлена в /etc/systemd/resolved.conf."
else
    # Если строки нет, добавляем её в конец файла
    echo "DNSStubListenerExtra=127.0.0.1:53" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
    echo "Строка 'DNSStubListenerExtra=127.0.0.1:53' добавлена в /etc/systemd/resolved.conf."
fi

echo "--- Настраиваем DNS ---"
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved

echo "Установка GlobalProtect и настройка DNS завершены."

# --- ВАЖНО: Ручная установка сертификата в браузеры ---
echo ""
echo "--- ВАЖНО: Ручная установка сертификата в браузеры ---"
echo "Автоматическая установка сертификатов в браузеры (Firefox, Google Chrome) невозможна через скрипт."
echo "Пожалуйста, выполните следующие шаги вручную для каждого используемого браузера:"
echo "Скачайте сертификат по ссылке: $CERT_DOWNLOAD_URL"
echo ""
echo "Для Firefox:"
echo "1. Откройте Firefox и перейдите по ссылке: about:preferences#privacy"
echo "2. Прокрутите вниз до раздела 'Сертификаты'."
echo "3. Нажмите кнопку 'Просмотр сертификатов...'"
echo "4. Перейдите на вкладку 'Центры сертификации'."
echo "5. Нажмите 'Импорт...' и выберите скачанный файл сертификата."
echo "6. Отметьте галочки доверия для этого сертификата."
echo ""
echo "Для Google Chrome:"
echo "1. Откройте Google Chrome и перейдите по ссылке: chrome://settings/certificates"
echo "2. Выберите вкладку 'Центры сертификации'."
echo "3. Нажмите 'Импорт...' и выберите скачанный файл сертификата."
echo "4. Следуйте инструкциям для установки сертификата в доверенные."
echo ""
echo "После выполнения всех шагов, ваша система и браузеры будут настроены."
