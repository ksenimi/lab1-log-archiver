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

    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"
}


# Создать файл заданного размера в МиБ
create_file() {
    local file="$1"
    local size_mib="$2"

    dd if=/dev/zero of="$file" bs=1M count="$size_mib" status=none
}


# Найти созданный обычный архив
find_gz_archive() {
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.gz" -print -quit
}


# Найти созданный LZMA-архив
find_lzma_archive() {
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.lzma" -print -quit
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
# Порог НЕ превышен
# ==================================================

echo "Тест 1: порог не превышен"

create_test_environment

# Всего 520 МиБ.
# Лимит 600 МиБ.
# 520 / 600 = 86,6%.
# При пороге 90% архивирование происходить не должно.
create_file "$LOG_DIR/file1.log" 260
create_file "$LOG_DIR/file2.log" 260

bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" 90 600 >/dev/null

ARCHIVE="$(find_gz_archive)"

if [ -z "$ARCHIVE" ] &&
   [ -f "$LOG_DIR/file1.log" ] &&
   [ -f "$LOG_DIR/file2.log" ]; then

    pass_test "при непревышенном пороге архив не создаётся"
else
    fail_test "при непревышенном пороге произошло архивирование"
fi


# ==================================================
# ТЕСТ 2
# Порог превышен
# ==================================================

echo
echo "Тест 2: порог превышен"

create_test_environment

# 600 МиБ из лимита 600 МиБ = 100%.
# При пороге 70% архивирование должно произойти.
create_file "$LOG_DIR/file1.log" 300
create_file "$LOG_DIR/file2.log" 300

bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" 70 600 >/dev/null

ARCHIVE="$(find_gz_archive)"

if [ -n "$ARCHIVE" ] &&
   { [ ! -f "$LOG_DIR/file1.log" ] || [ ! -f "$LOG_DIR/file2.log" ]; } &&
   tar -tzf "$ARCHIVE" >/dev/null 2>&1; then

    pass_test "при превышении порога создаётся корректный архив и исходные файлы удаляются"
else
    fail_test "архивирование при превышении порога работает неправильно"
fi


# ==================================================
# ТЕСТ 3
# Самые старые файлы выбираются первыми
# ==================================================

echo
echo "Тест 3: выбираются самые старые файлы"

create_test_environment

# Всего 600 МиБ.
create_file "$LOG_DIR/old.log" 100
create_file "$LOG_DIR/middle.log" 100
create_file "$LOG_DIR/new.log" 100
create_file "$LOG_DIR/big.log" 300

# Устанавливаем разные даты изменения.
touch -d "2020-01-01 10:00:00" "$LOG_DIR/old.log"
touch -d "2021-01-01 10:00:00" "$LOG_DIR/middle.log"
touch -d "2022-01-01 10:00:00" "$LOG_DIR/new.log"
touch -d "2023-01-01 10:00:00" "$LOG_DIR/big.log"

bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" 70 600 >/dev/null

ARCHIVE="$(find_gz_archive)"

# Чтобы опуститься с 600 МиБ до 70% от 600 МиБ,
# нужно оставить максимум 420 МиБ.
#
# Скрипт должен выбрать:
# old.log    100 МиБ
# middle.log 100 МиБ
#
# После их удаления останется 400 МиБ.
if [ -n "$ARCHIVE" ] &&
   [ ! -f "$LOG_DIR/old.log" ] &&
   [ ! -f "$LOG_DIR/middle.log" ] &&
   [ -f "$LOG_DIR/new.log" ] &&
   [ -f "$LOG_DIR/big.log" ] &&
   tar -tzf "$ARCHIVE" | grep -q "old.log" &&
   tar -tzf "$ARCHIVE" | grep -q "middle.log" &&
   ! tar -tzf "$ARCHIVE" | grep -q "new.log" &&
   ! tar -tzf "$ARCHIVE" | grep -q "big.log"; then

    pass_test "архивируются самые старые файлы"
else
    fail_test "выбраны неправильные файлы для архива"
fi


# ==================================================
# ТЕСТ 4
# Переданный порог действительно используется
# ==================================================

echo
echo "Тест 4: используется переданный порог"

create_test_environment

# 520 МиБ из 600 МиБ = 86,6%.
#
# Если передать 90%, архивирования быть не должно.
# Это проверяет, что скрипт действительно использует
# переданный порог, а не всегда 70%.
create_file "$LOG_DIR/file1.log" 260
create_file "$LOG_DIR/file2.log" 260

bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" 90 600 >/dev/null

ARCHIVE="$(find_gz_archive)"

if [ -z "$ARCHIVE" ] &&
   [ -f "$LOG_DIR/file1.log" ] &&
   [ -f "$LOG_DIR/file2.log" ]; then

    pass_test "переданный порог 90% используется правильно"
else
    fail_test "скрипт не использует переданный порог"
fi


# ==================================================
# ТЕСТ 5
# Ошибка при создании папки архивов
# ==================================================

echo
echo "Тест 5: ошибка архивирования"

create_test_environment

create_file "$LOG_DIR/file1.log" 300
create_file "$LOG_DIR/file2.log" 300

# Создаём файл с таким именем.
# Скрипт попытается использовать его как папку архивов,
# но создать папку с таким именем не сможет.
BAD_BACKUP="$TEST_ROOT/not_a_directory"
touch "$BAD_BACKUP"

bash "$ARCHIVER" "$LOG_DIR" "$BAD_BACKUP" 70 600 >/dev/null 2>&1
RESULT=$?

if [ "$RESULT" -ne 0 ] &&
   [ -f "$LOG_DIR/file1.log" ] &&
   [ -f "$LOG_DIR/file2.log" ]; then

    pass_test "при ошибке архивирования исходные файлы сохраняются"
else
    fail_test "при ошибке архивирования исходные файлы были удалены"
fi


# ==================================================
# ТЕСТ 6
# LZMA
# ==================================================

echo
echo "Тест 6: LZMA"

create_test_environment

create_file "$LOG_DIR/file1.log" 300
create_file "$LOG_DIR/file2.log" 300

LAB1_MAX_COMPRESSION=1 \
    bash "$ARCHIVER" "$LOG_DIR" "$BACKUP_DIR" 70 600 >/dev/null

LZMA_ARCHIVE="$(find_lzma_archive)"

if [ -n "$LZMA_ARCHIVE" ] &&
   tar -t --lzma -f "$LZMA_ARCHIVE" >/dev/null 2>&1; then

    pass_test "LZMA-архив создан и читается"
else
    fail_test "LZMA-архив не создан или повреждён"
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
