#!/bin/bash

# --- Переменные для сертификата (общие для всех версий) ---
CERT_FILENAME="Root256.crt"
CERT_DOWNLOAD_URL="https://lake.rozetka.com.ua/PUPCA.cer"

# --- Проверка операционной системы и её версии ---
echo "Проверяем операционную систему..."
OS_NAME=$(lsb_release -is 2>/dev/null)
if [ "$OS_NAME" != "Ubuntu" ]; then
    echo "Ошибка: Этот скрипт предназначен только для Ubuntu."
    echo "Ваша система: $OS_NAME"
    exit 1
fi

OS_VERSION=$(lsb_release -rs 2>/dev/null)
if [ -z "$OS_VERSION" ]; then
    echo "Ошибка: Не удалось определить версию Ubuntu. Пожалуйста, убедитесь, что утилита 'lsb_release' установлена."
    exit 1
fi

# Переменные для GlobalProtect, которые будут установлены в зависимости от версии
ARCHIVE_NAME=""
DEB_PACKAGE_NAME=""
DOWNLOAD_GP_URL=""
GP_VERSION_STRING="" # Используем для определения метода установки
INSTALL_METHOD=""    # Переменная для хранения метода установки

# Определяем, какую версию GlobalProtect устанавливать, основываясь на версии Ubuntu
# Ubuntu < 23.10 (например, 20.04, 22.04 LTS)
if awk -v ver="$OS_VERSION" 'BEGIN {exit !(ver < 23.10)}'; then
    GP_VERSION_STRING="6.1.0"
    ARCHIVE_NAME="PanGPLinux-6.1.0-c45.tgz"
    DEB_PACKAGE_NAME="GlobalProtect_UI_deb-6.1.0.0-44.deb"
    DOWNLOAD_GP_URL="https://cloud.rozetka.ua/s/og7BDCJDPsMfrmA/download/PanGPLinux-6.1.0-c45.tgz"
    INSTALL_METHOD="dpkg"
    echo "Определена Ubuntu версии $OS_VERSION (менее 23.10). Будет установлен GlobalProtect версии $GP_VERSION_STRING."

# Ubuntu >= 24.04 (например, 24.04 LTS, 24.10)
elif awk -v ver="$OS_VERSION" 'BEGIN {exit !(ver >= 24.04)}'; then
    GP_VERSION_STRING="6.2.0"
    ARCHIVE_NAME="PanGPLinux-6.2.0-c10.tgz"
    DEB_PACKAGE_NAME="GlobalProtect_UI_deb-6.2.0.1-265.deb"
    DOWNLOAD_GP_URL="https://cloud.rozetka.ua/s/rPaTLHw4yFbcDLZ/download/PanGPLinux-6.2.0-c10.tgz"
    INSTALL_METHOD="apt"
    echo "Определена Ubuntu версии $OS_VERSION (24.04 или выше). Будет установлен GlobalProtect версии $GP_VERSION_STRING."

# Версии между 23.10 и 24.04 (включая 23.10, если бы она была выпущена, и 23.04) не поддерживаются.
else
    echo "Ошибка: Ваша версия Ubuntu ($OS_VERSION) не поддерживается этим скриптом."
    echo "Скрипт поддерживает Ubuntu версий < 23.10 или >= 24.04."
    echo "Пожалуйста, обновите или переустановите ОС на поддерживаемую версию."
    exit 1
fi

echo "Система проверена. Продолжаем установку GlobalProtect версии $GP_VERSION_STRING..."
echo "---"

echo "Начинаем автоматическую установку GlobalProtect и настройку сертификатов..."

# Переходим в директорию, где находится скрипт, для удобства работы с файлами
# Сохраняем путь к самому скрипту до cd, чтобы удалить его в конце
SCRIPT_PATH="$(readlink -f "$0")"
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
echo "--- Скачиваем архив с GlobalProtect по прямой ссылке: $DOWNLOAD_GP_URL в /tmp ---"
# Скачиваем архив во временную директорию /tmp для последующей очистки
wget "$DOWNLOAD_GP_URL" -O /tmp/"$ARCHIVE_NAME"
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось скачать архив GlobalProtect '$ARCHIVE_NAME' с '$DOWNLOAD_GP_URL'."
    echo "Пожалуйста, проверьте ссылку или ваше интернет-соединение."
    exit 1
fi
echo "Архив GlobalProtect '$ARCHIVE_NAME' успешно скачан."

# --- Шаг 4: Разархивирование файла GlobalProtect ---
echo "--- Разархивируем $ARCHIVE_NAME из /tmp в текущую директорию ---"
# Распаковываем из /tmp в текущую директорию скрипта
# tar -xvf /tmp/"$ARCHIVE_NAME"
# Для более надежной очистки, сначала получаем список файлов из архива
# а затем распаковываем.
# Важно: список файлов для удаления должен быть получен ДО распаковки,
# если архив сам себя удаляет, или из временного местоположения архива.
# Здесь мы читаем список из /tmp/$ARCHIVE_NAME.
EXTRACTED_FILES_TO_CLEANUP=$(tar -tf "/tmp/$ARCHIVE_NAME" | grep -v '^\.$' | grep -v '^\.\.$' | sort -r)

tar -xvf "/tmp/$ARCHIVE_NAME"
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось разархивировать архив GlobalProtect '$ARCHIVE_NAME'."
    echo "Пожалуйста, убедитесь, что архив не поврежден."
    exit 1
fi
echo "Архив GlobalProtect успешно разархивирован."


# --- Шаг 5: Запуск установки приложения GlobalProtect ---
echo "--- Запускаем установку GlobalProtect ---"
if [ -f "$DEB_PACKAGE_NAME" ]; then
    if [ "$INSTALL_METHOD" == "dpkg" ]; then
        echo "Используем dpkg -i для установки DEB-пакета..."
        sudo dpkg -i "./$DEB_PACKAGE_NAME"
        if [ $? -ne 0 ]; then
            echo "Предупреждение: Установка GlobalProtect через dpkg завершилась с ошибкой. Попытка исправить зависимости..."
            sudo apt --fix-broken install -y
            # Повторная попытка установки после исправления зависимостей, если apt --fix-broken install не установил
            echo "Повторная попытка установки GlobalProtect после исправления зависимостей..."
            sudo dpkg -i "./$DEB_PACKAGE_NAME"
            if [ $? -ne 0 ]; then
                echo "Ошибка: Не удалось установить GlobalProtect даже после попытки исправить зависимости."
                exit 1
            fi
        fi
    elif [ "$INSTALL_METHOD" == "apt" ]; then
        echo "Используем apt install для установки DEB-пакета..."
        sudo apt install "./$DEB_PACKAGE_NAME" -y
        if [ $? -ne 0 ]; then
            echo "Предупреждение: Установка GlobalProtect через apt завершилась с ошибкой. Попытка исправить зависимости..."
            sudo apt --fix-broken install -y
            # Повторная попытка установки после исправления зависимостей
            sudo apt install "./$DEB_PACKAGE_NAME" -y
            if [ $? -ne 0 ]; then
                echo "Ошибка: Не удалось установить GlobalProtect даже после попытки исправить зависимости."
                exit 1
            fi
        fi
    fi
    echo "GlobalProtect успешно установлен."
else
    echo "Ошибка: DEB-пакет $DEB_PACKAGE_NAME не найден. Убедитесь, что он был разархивирован из архива."
    exit 1
fi

# --- Шаг 6: Редактирование файла /etc/systemd/resolved.conf ---
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

# --- Шаг 7: Последовательное выполнение команд для DNS ---
echo "--- Настраиваем DNS ---"
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
#sudo systemctl status systemd-resolved # Эта команда необязательна, но выводит статус

echo "Установка GlobalProtect и настройка DNS завершены."

# --- Шаг 8: Очистка скачанных и распакованных файлов ---
echo "--- Очистка временных файлов ---"
if [ -f "/tmp/$ARCHIVE_NAME" ]; then
    echo "Очистка распакованных файлов из архива '$ARCHIVE_NAME'..."
    # Проходим по списку файлов, которые были в архиве, и удаляем их
    for item in $EXTRACTED_FILES_TO_CLEANUP; do
        if [ -e "$item" ]; then # Проверяем, существует ли этот элемент в текущей директории
            echo "Удаление: $item"
            rm -rf "$item" # Удаляем файл или директорию рекурсивно
        fi
    done

    echo "Удаляем скачанный архив из /tmp: $ARCHIVE_NAME"
    rm "/tmp/$ARCHIVE_NAME"
fi
echo "Очистка завершена."

# --- Шаг 9: Самоудаление скрипта ---
echo "--- Самоудаление скрипта ---"
if [ -f "$SCRIPT_PATH" ]; then
    echo "Удаляем сам скрипт: $SCRIPT_PATH"
    rm -- "$SCRIPT_PATH"
    echo "Скрипт успешно удален. Возможно, вы увидите сообщение 'No such file or directory' для следующей команды, это нормально."
fi

# --- Инструкции по ручной установке сертификата в браузеры ---
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
echo "Все временные файлы и сам скрипт были удалены."