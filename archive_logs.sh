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

# Используем абсолютный путь, чтобы относительные пути внутри архива
# сохраняли структуру подпапок независимо от способа запуска.
log_dir=$(cd -- "$log_dir" && pwd -P) || {
    echo "Ошибка: не удалось открыть папку логов" >&2
    exit 1
}

printf 'Папка логов: %s\n' "$log_dir"
printf 'Папка архивов: %s\n' "$backup_dir"
printf 'Порог: %s%%\n' "$threshold"
printf 'Лимит: %s МиБ\n' "$limit_mib"

# Переводим лимит из МиБ в байты
limit_bytes=$((limit_mib * 1024 * 1024))
total_bytes=0
files=()
sizes=()

# find обходит все подпапки; -print0 сохраняет имена с пробелами и переводами строк.
scan_list=$(mktemp) || {
    echo "Ошибка: не удалось подготовить список файлов" >&2
    exit 1
}
if ! find "$log_dir" -type f -print0 > "$scan_list"; then
    rm -f -- "$scan_list"
    echo "Ошибка: не удалось прочитать дерево папки логов" >&2
    exit 1
fi

while IFS= read -r -d '' file; do
    if ! file_bytes=$(wc -c < "$file"); then
        rm -f -- "$scan_list"
        echo "Ошибка: не удалось прочитать файл: $file" >&2
        exit 1
    fi
    total_bytes=$((total_bytes + file_bytes))
    files+=("$file")
    sizes+=("$file_bytes")
done < "$scan_list"
rm -f -- "$scan_list"

percent=$((total_bytes * 100 / limit_bytes))

printf 'Размер файлов: %s байт\n' "$total_bytes"
printf 'Заполнение: %s%%\n' "$percent"

if (( total_bytes * 100 > threshold * limit_bytes )); then
    # Сортируем файлы по времени изменения; при равной дате — по имени.
    for ((i = 0; i < ${#files[@]}; i++)); do
        oldest_index=$i
        for ((j = i + 1; j < ${#files[@]}; j++)); do
            candidate=${files[j]}
            current=${files[oldest_index]}
            if [[ "$candidate" -ot "$current" ]] ||
               [[ ! "$candidate" -nt "$current" && "$candidate" < "$current" ]]; then
                oldest_index=$j
            fi
        done
        if (( oldest_index != i )); then
            temp_file=${files[i]}
            files[i]=${files[oldest_index]}
            files[oldest_index]=$temp_file
            temp_size=${sizes[i]}
            sizes[i]=${sizes[oldest_index]}
            sizes[oldest_index]=$temp_size
        fi
    done

    # Берём минимальное число самых старых файлов для достижения порога.
    selected_files=()
    remaining_bytes=$total_bytes
    for ((i = 0; i < ${#files[@]}; i++)); do
        selected_files+=("${files[i]}")
        remaining_bytes=$((remaining_bytes - sizes[i]))
        if (( remaining_bytes * 100 <= threshold * limit_bytes )); then
            break
        fi
    done

    printf 'Порог превышен. Выбрано файлов: %s\n' "${#selected_files[@]}"
    printf 'Для архива: %s\n' "${selected_files[@]}"
    printf 'Размер после удаления исходников: %s байт\n' "$remaining_bytes"

    if ! mkdir -p -- "$backup_dir"; then
        echo "Ошибка: не удалось создать папку архивов: $backup_dir" >&2
        exit 1
    fi

    log_abs=$(cd -- "$log_dir" && pwd -P) || exit 1
    backup_abs=$(cd -- "$backup_dir" && pwd -P) || exit 1
    if [[ "$backup_abs" == "$log_abs" || "$backup_abs" == "$log_abs/"* ]]; then
        echo "Ошибка: папка архивов должна находиться вне папки логов" >&2
        exit 1
    fi

    # mktemp создаёт уникальное имя, чтобы не перезаписать прежний архив.
    archive_temp=$(mktemp "$backup_dir/logs_XXXXXXXX") || {
        echo "Ошибка: не удалось подготовить файл архива" >&2
        exit 1
    }
    compression_option=-z
    archive_extension=.tar.gz
    if [[ ${LAB1_MAX_COMPRESSION:-} == 1 ]]; then
        compression_option=--lzma
        archive_extension=.tar.lzma
        if ! command -v lzma >/dev/null 2>&1; then
            rm -f -- "$archive_temp"
            echo "Ошибка: для режима LZMA нужна команда lzma" >&2
            exit 1
        fi
    fi
    archive_file="$archive_temp$archive_extension"
    selected_names=()
    for file in "${selected_files[@]}"; do
        selected_names+=("${file#"$log_dir"/}")
    done

    # Пока tar не завершился успешно и архив не прочитан, исходники не трогаем.
    if ! tar -c "$compression_option" -f "$archive_temp" -C "$log_dir" -- "${selected_names[@]}" ||
       ! tar -t "$compression_option" -f "$archive_temp" >/dev/null; then
        rm -f -- "$archive_temp"
        echo "Ошибка: архив не создан; исходные файлы сохранены" >&2
        exit 1
    fi
    # Жёсткая ссылка создаёт итоговое имя, только если оно ещё не занято.
    if ! ln -- "$archive_temp" "$archive_file"; then
        rm -f -- "$archive_temp"
        echo "Ошибка: не удалось сохранить архив без перезаписи; исходные файлы сохранены" >&2
        exit 1
    fi
    if ! rm -- "$archive_temp"; then
        echo "Ошибка: архив создан, но временный файл не удалён; исходные файлы сохранены" >&2
        exit 1
    fi

    printf 'Архив создан: %s\n' "$archive_file"
    for file in "${selected_files[@]}"; do
        if ! rm -- "$file"; then
            echo "Ошибка: не удалось удалить исходный файл: $file" >&2
            exit 1
        fi
    done
    printf 'Удалено исходных файлов: %s\n' "${#selected_files[@]}"
else
    echo "Порог не превышен: архивирование не требуется"
fi
