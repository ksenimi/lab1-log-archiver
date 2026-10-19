#!/usr/bin/env bash

# Папка, в которой находятся скрипты проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Основной скрипт, который мы тестируем
ARCHIVER="$SCRIPT_DIR/archive_logs.sh"

# Временная папка для всех тестов
TEST_ROOT="$(mktemp -d)"

# После завершения тестов удалить все тестовые данные
trap 'rm -rf "$TEST_ROOT"' EXIT

# Счётчики результатов
PASSED=0
FAILED=0

# Общий лимит для тестов
LIMIT_MIB=600
LIMIT_BYTES=$((LIMIT_MIB * 1024 * 1024))


# ==================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==================================================

pass_test() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
}

fail_test() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
}


# Создать чистые папки для теста
create_test_environment() {
    LOG_DIR="$TEST_ROOT/log"
    BACKUP_DIR="$TEST_ROOT/backup"

    rm -rf "$LOG_DIR" "$BACKUP_DIR"

    mkdir -p "$LOG_DIR" || return 1
    mkdir -p "$BACKUP_DIR" || return 1
}


# Создать файл заданного размера в МиБ
create_file() {
    local file="$1"
    local size_mib="$2"

    dd if=/dev/zero of="$file" bs=1M count="$size_mib" status=none
}


# Посчитать размер обычных файлов непосредственно в папке.
# Это та же модель размера, которая используется в основном скрипте.
get_log_size_bytes() {
    local total=0
    local file
    local size

    while IFS= read -r -d '' file; do
        if [[ -f "$file" && ! -L "$file" ]]; then
            size=$(wc -c < "$file") || return 1
            total=$((total + size))
        fi
    done < <(find "$LOG_DIR" -type f -print0)

    echo "$total"
}


# Найти обычные tar.gz архивы
find_gz_archives() {
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.gz" -print
}


# Найти обычные tar.lzma архивы
find_lzma_archives() {
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.lzma" -print
}


# Проверить, что существует ровно один обычный архив
get_single_gz_archive() {
    local archives
    local count

    archives="$(find_gz_archives)"
    count="$(printf '%s\n' "$archives" | sed '/^$/d' | wc -l)"

    if [ "$count" -eq 1 ]; then
        printf '%s\n' "$archives"
        return 0
    fi

    return 1
}


# Проверить, что существует ровно один LZMA-архив
get_single_lzma_archive() {
    local archives
    local count

    archives="$(find_lzma_archives)"
    count="$(printf '%s\n' "$archives" | sed '/^$/d' | wc -l)"

    if [ "$count" -eq 1 ]; then
        printf '%s\n' "$archives"
        return 0
    fi

    return 1
}


# Запустить основной скрипт и сохранить его код завершения
run_archiver() {
    "$@" >/dev/null 2>&1
    return $?
}


# ==================================================
# ПРОВЕРКА ОСНОВНОГО СКРИПТА
# ==================================================

if [ ! -f "$ARCHIVER" ]; then
    echo "Ошибка: не найден файл:"
    echo "$ARCHIVER"
    echo
    echo "Положите archive_logs.sh рядом с test_archive.sh."
    exit 1
fi


echo "========================================"
echo "Тестирование archive_logs.sh"
echo "========================================"
echo


# ==================================================
# ТЕСТ 1
# Порог не превышен
# ==================================================

echo "Тест 1: порог не превышен"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # 520 МиБ из лимита 600 МиБ = 86,6%.
    # При пороге 90% архивирование происходить не должно.
    create_file "$LOG_DIR/file1.log" 260
    create_file "$LOG_DIR/file2.log" 260

    THRESHOLD=90
    TARGET_BYTES=$((THRESHOLD * LIMIT_BYTES / 100))

    run_archiver bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" "$THRESHOLD" "$LIMIT_MIB"
    RESULT=$?

    ARCHIVE_COUNT="$(find_gz_archives | sed '/^$/d' | wc -l)"
    LOG_SIZE="$(get_log_size_bytes)"

    if [ "$RESULT" -eq 0 ] &&
       [ "$ARCHIVE_COUNT" -eq 0 ] &&
       [ -f "$LOG_DIR/file1.log" ] &&
       [ -f "$LOG_DIR/file2.log" ] &&
       [ "$LOG_SIZE" -eq $((520 * 1024 * 1024)) ] &&
       [ "$LOG_SIZE" -le "$TARGET_BYTES" ]; then

        pass_test "при непревышенном пороге архив не создаётся, файлы остаются, код возврата 0"
    else
        fail_test "при непревышенном пороге результат или код возврата неправильные"
    fi
fi


# ==================================================
# ТЕСТ 2
# Порог превышен
# ==================================================

echo
echo "Тест 2: порог превышен"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # 600 МиБ из лимита 600 МиБ = 100%.
    # При пороге 70% нужно уменьшить размер до 420 МиБ или меньше.
    #
    # Два файла по 300 МиБ.
    # Для достижения порога достаточно удалить один файл.
    create_file "$LOG_DIR/file1.log" 300
    create_file "$LOG_DIR/file2.log" 300

    THRESHOLD=70
    TARGET_BYTES=$((THRESHOLD * LIMIT_BYTES / 100))

    run_archiver bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" "$THRESHOLD" "$LIMIT_MIB"
    RESULT=$?

    ARCHIVE="$(get_single_gz_archive)"
    LOG_SIZE="$(get_log_size_bytes)"

    # Определяем, какой из двух файлов был удалён
    REMOVED_FILE=""

    if [ ! -f "$LOG_DIR/file1.log" ] &&
       [ -f "$LOG_DIR/file2.log" ]; then
        REMOVED_FILE="file1.log"
    elif [ -f "$LOG_DIR/file1.log" ] &&
         [ ! -f "$LOG_DIR/file2.log" ]; then
        REMOVED_FILE="file2.log"
    fi

    # Проверяем, что архив действительно содержит удалённый файл
    ARCHIVE_CONTAINS_REMOVED_FILE=0

    if [ -n "$ARCHIVE" ] && [ -n "$REMOVED_FILE" ] &&
       tar -tzf "$ARCHIVE" 2>/dev/null | grep -Fxq "$REMOVED_FILE"; then
        ARCHIVE_CONTAINS_REMOVED_FILE=1
    fi

    if [ "$RESULT" -eq 0 ] &&
       [ -n "$ARCHIVE" ] &&
       tar -tzf "$ARCHIVE" >/dev/null 2>&1 &&
       [ -n "$REMOVED_FILE" ] &&
       [ "$ARCHIVE_CONTAINS_REMOVED_FILE" -eq 1 ] &&
       [ "$LOG_SIZE" -le "$TARGET_BYTES" ]; then

        pass_test "при превышении порога создаётся корректный архив, удалённый файл сохранён в архиве, размер уменьшается до порога, код возврата 0"
    else
        fail_test "архивирование при превышении порога работает неправильно"
    fi
fi


# ==================================================
# ТЕСТ 3
# Другой порог меняет результат
# ==================================================

echo
echo "Тест 3: используется переданный порог"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # Те же исходные данные, что в тесте 1:
    # 520 МиБ из 600 МиБ = 86,6%.
    # В тесте 1 порог 90% — архивирования нет.
    # Здесь порог 80% — архивирование должно произойти.
    create_file "$LOG_DIR/file1.log" 260
    create_file "$LOG_DIR/file2.log" 260

    THRESHOLD=80
    TARGET_BYTES=$((THRESHOLD * LIMIT_BYTES / 100))

    run_archiver bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" "$THRESHOLD" "$LIMIT_MIB"
    RESULT=$?

    ARCHIVE="$(get_single_gz_archive)"
    LOG_SIZE="$(get_log_size_bytes)"

    if [ -n "$ARCHIVE" ] &&
       [ "$RESULT" -eq 0 ] &&
       tar -tzf "$ARCHIVE" >/dev/null 2>&1 &&
       [ "$LOG_SIZE" -le "$TARGET_BYTES" ] &&
       { [ ! -f "$LOG_DIR/file1.log" ] || [ ! -f "$LOG_DIR/file2.log" ]; } &&
       tar -tzf "$ARCHIVE" | grep -qE '(^|/)file[12]\.log$'; then

        pass_test "изменение порога действительно меняет результат для одинаковых исходных данных"
    else
        fail_test "скрипт не использует переданный порог правильно"
    fi
fi


# ==================================================
# ТЕСТ 4
# Самые старые файлы выбираются первыми
# ==================================================

echo
echo "Тест 4: выбираются самые старые файлы"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # Всего 600 МиБ.
    create_file "$LOG_DIR/old.log" 100
    create_file "$LOG_DIR/middle.log" 100
    create_file "$LOG_DIR/new.log" 100
    create_file "$LOG_DIR/big.log" 300

    # Устанавливаем разные даты изменения
    touch -d "2020-01-01 10:00:00" "$LOG_DIR/old.log"
    touch -d "2021-01-01 10:00:00" "$LOG_DIR/middle.log"
    touch -d "2022-01-01 10:00:00" "$LOG_DIR/new.log"
    touch -d "2023-01-01 10:00:00" "$LOG_DIR/big.log"

    THRESHOLD=70
    TARGET_BYTES=$((THRESHOLD * LIMIT_BYTES / 100))

    run_archiver bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" "$THRESHOLD" "$LIMIT_MIB"
    RESULT=$?

    ARCHIVE="$(get_single_gz_archive)"
    LOG_SIZE="$(get_log_size_bytes)"

    if [ -n "$ARCHIVE" ] &&
       [ "$RESULT" -eq 0 ] &&
       tar -tzf "$ARCHIVE" >/dev/null 2>&1 &&
       [ "$LOG_SIZE" -le "$TARGET_BYTES" ] &&
       [ ! -f "$LOG_DIR/old.log" ] &&
       [ ! -f "$LOG_DIR/middle.log" ] &&
       [ -f "$LOG_DIR/new.log" ] &&
       [ -f "$LOG_DIR/big.log" ] &&
       tar -tzf "$ARCHIVE" | grep -qE '(^|/)old\.log$' &&
       tar -tzf "$ARCHIVE" | grep -qE '(^|/)middle\.log$' &&
       ! tar -tzf "$ARCHIVE" | grep -qE '(^|/)new\.log$' &&
       ! tar -tzf "$ARCHIVE" | grep -qE '(^|/)big\.log$'; then

        pass_test "архивируются самые старые файлы, новые остаются, размер после удаления не превышает порог"
    else
        fail_test "выбраны неправильные файлы для архива"
    fi
fi


# ==================================================
# ТЕСТ 5
# Ошибка подготовки папки архивов
# ==================================================

echo
echo "Тест 5: ошибка подготовки папки архивов"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # 600 МиБ — порог 70% превышен.
    create_file "$LOG_DIR/file1.log" 300
    create_file "$LOG_DIR/file2.log" 300

    # Создаём обычный файл вместо папки архивов.
    # mkdir -p не сможет создать каталог поверх существующего файла.
    INVALID_BACKUP_PATH="$TEST_ROOT/not_a_directory"
    : > "$INVALID_BACKUP_PATH"

    THRESHOLD=70
    run_archiver bash "$ARCHIVER" "$LOG_DIR" "$INVALID_BACKUP_PATH" "$THRESHOLD" "$LIMIT_MIB"
    RESULT=$?

    LOG_SIZE="$(get_log_size_bytes)"

    if [ "$RESULT" -ne 0 ] &&
       [ "$LOG_SIZE" -eq $((600 * 1024 * 1024)) ] &&
       [ -f "$LOG_DIR/file1.log" ] &&
       [ -f "$LOG_DIR/file2.log" ] &&
       [ -f "$INVALID_BACKUP_PATH" ]; then

        pass_test "при ошибке подготовки папки архивов исходные файлы сохраняются и возвращается код ошибки"
    else
        fail_test "при ошибке подготовки папки архивов результат неправильный"
    fi
fi


# ==================================================
# ТЕСТ 6
# LZMA
# ==================================================

echo
echo "Тест 6: LZMA"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # 600 МиБ — порог 70% превышен.
    create_file "$LOG_DIR/file1.log" 300
    create_file "$LOG_DIR/file2.log" 300

    if ! command -v lzma >/dev/null 2>&1; then
        fail_test "команда lzma не установлена"
    else
        THRESHOLD=70
        TARGET_BYTES=$((THRESHOLD * LIMIT_BYTES / 100))

        LAB1_MAX_COMPRESSION=1 \
            run_archiver bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" "$THRESHOLD" "$LIMIT_MIB"
        RESULT=$?

        LZMA_ARCHIVE="$(get_single_lzma_archive)"
        LOG_SIZE="$(get_log_size_bytes)"

        if [ -n "$LZMA_ARCHIVE" ] &&
           [ "$RESULT" -eq 0 ] &&
           tar -t --lzma -f "$LZMA_ARCHIVE" >/dev/null 2>&1 &&
           [ "$LOG_SIZE" -le "$TARGET_BYTES" ] &&
           { [ ! -f "$LOG_DIR/file1.log" ] || [ ! -f "$LOG_DIR/file2.log" ]; }; then

            pass_test "LZMA-архив создан, читается, исходная папка уменьшена до порога, код возврата 0"
        else
            fail_test "LZMA-архив не создан или работает неправильно"
        fi
    fi
fi


# ==================================================
# ТЕСТ 7
# Файлы во вложенных папках
# ==================================================

echo
echo "Тест 7: обработка вложенных папок"

if ! create_test_environment; then
    fail_test "не удалось подготовить тестовую среду"
else
    # Создаём вложенную структуру каталогов.
    mkdir -p "$LOG_DIR/folder1/folder2" "$LOG_DIR/folder3"

    # Создаём файлы общим размером 600 МиБ.
    create_file "$LOG_DIR/root.log" 100
    create_file "$LOG_DIR/folder1/old.log" 100
    create_file "$LOG_DIR/folder1/folder2/middle.log" 100
    create_file "$LOG_DIR/folder3/new.log" 300

    # Назначаем даты изменения.
    touch -d "2020-01-01 10:00:00" "$LOG_DIR/folder1/old.log"
    touch -d "2021-01-01 10:00:00" "$LOG_DIR/folder1/folder2/middle.log"
    touch -d "2024-01-01 10:00:00" "$LOG_DIR/root.log"
    touch -d "2023-01-01 10:00:00" "$LOG_DIR/folder3/new.log"

    THRESHOLD=70
    TARGET_BYTES=$((THRESHOLD * LIMIT_BYTES / 100))

    echo "Запускаем основной скрипт для вложенных папок..."

    if bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" "$THRESHOLD" "$LIMIT_MIB"; then
        RESULT=0
    else
        RESULT=$?
    fi

    ARCHIVE="$(get_single_gz_archive)"
    LOG_SIZE="$(get_log_size_bytes)"

    # Если архив найден, получаем список его файлов.
    ARCHIVE_LIST=""
    if [ -n "$ARCHIVE" ]; then
        ARCHIVE_LIST="$(tar -tzf "$ARCHIVE" 2>/dev/null)"
    fi

    # Проверяем, что архив содержит два самых старых файла.
    if [ -n "$ARCHIVE" ] &&
       [ "$RESULT" -eq 0 ] &&
       printf '%s\n' "$ARCHIVE_LIST" | grep -Fxq "folder1/old.log" &&
       printf '%s\n' "$ARCHIVE_LIST" | grep -Fxq "folder1/folder2/middle.log" &&
       ! printf '%s\n' "$ARCHIVE_LIST" | grep -Fxq "root.log" &&
       ! printf '%s\n' "$ARCHIVE_LIST" | grep -Fxq "folder3/new.log" &&
       [ ! -f "$LOG_DIR/folder1/old.log" ] &&
       [ ! -f "$LOG_DIR/folder1/folder2/middle.log" ] &&
       [ -f "$LOG_DIR/root.log" ] &&
       [ -f "$LOG_DIR/folder3/new.log" ] &&
       [ "$LOG_SIZE" -eq $((400 * 1024 * 1024)) ] &&
       [ "$LOG_SIZE" -le "$TARGET_BYTES" ]; then

        pass_test "вложенные папки обрабатываются, самые старые файлы архивируются с сохранением путей"
    else
        fail_test "обработка вложенных папок работает неправильно"

    fi
fi


# ==================================================
# ИТОГ
# ==================================================

echo
echo "========================================"
echo "Результат тестирования"
echo "========================================"
echo "Пройдено: $PASSED"
echo "Провалено: $FAILED"

if [ "$FAILED" -eq 0 ]; then
    echo "Все тесты пройдены."
    exit 0
else
    echo "Есть ошибки."
    exit 1
fi
