#!/usr/bin/env bash

# Ожидаем: папка логов, папка архивов, порог в %, лимит в МиБ
if [ "$#" -ne 4 ]; then
    echo "Использование: bash archive_logs.sh ПАПКА_ЛОГОВ ПАПКА_АРХИВОВ ПОРОГ ЛИМИТ_МиБ"
    exit 2
fi

log_dir=$1
backup_dir=$2
threshold=$3
limit_mib=$4

if [ ! -d "$log_dir" ]; then
    echo "Ошибка: папка логов не существует: $log_dir"
    exit 1
fi

if [[ ! $threshold =~ ^(100|[1-9]?[0-9])$ ]]; then
    echo "Ошибка: порог должен быть целым числом от 0 до 100"
    exit 2
fi

if [[ ! $limit_mib =~ ^[1-9][0-9]*$ ]]; then
    echo "Ошибка: лимит должен быть положительным целым числом"
    exit 2
fi

printf 'Папка логов: %s\n' "$log_dir"
printf 'Папка архивов: %s\n' "$backup_dir"
printf 'Порог: %s%%\n' "$threshold"
printf 'Лимит: %s МиБ\n' "$limit_mib"

# Переводим лимит из МиБ в байты
limit_bytes=$((limit_mib * 1024 * 1024))
total_bytes=0
oldest_file=""

# * включает и скрытые файлы; пустая папка не создаёт ложного имени
shopt -s nullglob dotglob

for file in "$log_dir"/*; do
    # Учитываем только обычные файлы в этой папке
    if [[ -f "$file" && ! -L "$file" ]]; then
        file_bytes=$(wc -c < "$file")
        total_bytes=$((total_bytes + file_bytes))

        if [[ -z "$oldest_file" || "$file" -ot "$oldest_file" ]]; then
            oldest_file=$file
        fi
    fi
done

percent=$((total_bytes * 100 / limit_bytes))

printf 'Размер файлов: %s байт\n' "$total_bytes"
printf 'Заполнение: %s%%\n' "$percent"

if (( total_bytes * 100 > threshold * limit_bytes )); then
    echo "Порог превышен: позже здесь будет архивирование"
    printf 'Самый старый файл: %s\n' "$oldest_file"
else
    echo "Порог не превышен: архивирование не требуется"
fi
