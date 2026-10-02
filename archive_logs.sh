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