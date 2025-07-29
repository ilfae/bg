
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Проверка поддержки VT
if ($PSVersionTable.PSVersion.Major -ge 5 -and $host.UI.RawUI -ne $null) {
    $host.UI.RawUI.SupportsVirtualTerminal = $true
}
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

function Generate-RandomString {
    param([int]$Length)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $result = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $result
}

function Modify-CursorJSFiles {
    Write-Host ""
    Write-Host "$BLUE🔧 [Модификация ядра]$NC Начало модификации JS-файлов ядра Cursor для обхода идентификации устройства..."
    Write-Host ""

    $cursorAppPath = "${env:LOCALAPPDATA}\Programs\Cursor"
    if (-not (Test-Path $cursorAppPath)) {
        $alternatePaths = @(
            "${env:ProgramFiles}\Cursor",
            "${env:ProgramFiles(x86)}\Cursor",
            "${env:USERPROFILE}\AppData\Local\Programs\Cursor"
        )

        foreach ($path in $alternatePaths) {
            if (Test-Path $path) {
                $cursorAppPath = $path
                break
            }
        }

        if (-not (Test-Path $cursorAppPath)) {
            Write-Host "$RED❌ [Ошибка]$NC Путь установки Cursor не найден"
            Write-Host "$YELLOW💡 [Подсказка]$NC Убедитесь, что Cursor установлен правильно"
            return $false
        }
    }

    Write-Host "$GREEN✅ [Обнаружение]$NC Найден путь установки: $cursorAppPath"

    $newUuid = [System.Guid]::NewGuid().ToString().ToLower()
    $machineId = "auth0|user_$(Generate-RandomString -Length 32)"
    $deviceId = [System.Guid]::NewGuid().ToString().ToLower()
    $macMachineId = Generate-RandomString -Length 64

    Write-Host "$GREEN🔑 [Генерация]$NC Сгенерированы новые идентификаторы устройства"

    $jsFiles = @(
        "$cursorAppPath\resources\app\out\vs\workbench\api\node\extensionHostProcess.js",
        "$cursorAppPath\resources\app\out\main.js",
        "$cursorAppPath\resources\app\out\vs\code\node\cliProcessMain.js"
    )

    $modifiedCount = 0
    $needModification = $false

    Write-Host "$BLUE🔍 [Проверка]$NC Проверка состояния JS-файлов..."
    foreach ($file in $jsFiles) {
        if (-not (Test-Path $file)) {
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Файл не существует: $(Split-Path $file -Leaf)"
            continue
        }

        $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -notmatch "return crypto\.randomUUID\(\)") {
            Write-Host "$BLUE📝 [Требуется]$NC Файл требует модификации: $(Split-Path $file -Leaf)"
            $needModification = $true
            break
        } else {
            Write-Host "$GREEN✅ [Модифицирован]$NC Файл уже модифицирован: $(Split-Path $file -Leaf)"
        }
    }

    if (-not $needModification) {
        Write-Host "$GREEN✅ [Пропуск]$NC Все JS-файлы уже модифицированы"
        return $true
    }

    Write-Host "$BLUE🔄 [Закрытие]$NC Завершение процессов Cursor для модификации файлов..."
    Stop-AllCursorProcesses -MaxRetries 3 -WaitSeconds 3 | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$env:TEMP\Cursor_JS_Backup_$timestamp"

    Write-Host "$BLUE💾 [Резервирование]$NC Создание резервной копии JS-файлов Cursor..."
    try {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        foreach ($file in $jsFiles) {
            if (Test-Path $file) {
                $fileName = Split-Path $file -Leaf
                Copy-Item $file "$backupPath\$fileName" -Force
            }
        }
        Write-Host "$GREEN✅ [Резервирование]$NC Резервная копия создана: $backupPath"
    } catch {
        Write-Host "$RED❌ [Ошибка]$NC Ошибка создания резервной копии: $($_.Exception.Message)"
        return $false
    }

    Write-Host "$BLUE🔧 [Модификация]$NC Начало модификации JS-файлов..."

    foreach ($file in $jsFiles) {
        if (-not (Test-Path $file)) {
            Write-Host "$YELLOW⚠️  [Пропуск]$NC Файл не существует: $(Split-Path $file -Leaf)"
            continue
        }

        Write-Host "$BLUE📝 [Обработка]$NC Обработка файла: $(Split-Path $file -Leaf)"

        try {
            $content = Get-Content $file -Raw -Encoding UTF8

            if ($content -match "return crypto\.randomUUID\(\)" -or $content -match "// Cursor ID модификация") {
                Write-Host "$GREEN✅ [Пропуск]$NC Файл уже модифицирован"
                $modifiedCount++
                continue
            }

            $timestampVar = [DateTimeOffset]::Now.ToUnixTimeSeconds()
            $injectCode = @"
import crypto from 'crypto';
const originalRandomUUID_${timestampVar} = crypto.randomUUID;
crypto.randomUUID = function() {
    return '${newUuid}';
};
globalThis.getMachineId = function() { return '${machineId}'; };
globalThis.getDeviceId = function() { return '${deviceId}'; };
globalThis.macMachineId = '${macMachineId}';
if (typeof window !== 'undefined') {
    window.getMachineId = globalThis.getMachineId;
    window.getDeviceId = globalThis.getDeviceId;
    window.macMachineId = globalThis.macMachineId;
}
console.log('Идентификаторы устройства Cursor успешно изменены');
"@

            if ($content -match "IOPlatformUUID") {
                Write-Host "$BLUE🔍 [Обнаружение]$NC Найдено ключевое слово IOPlatformUUID"

                if ($content -match "function a\$") {
                    $content = $content -replace "function a\$\(t\)\{switch", "function a`$(t){return crypto.randomUUID(); switch"
                    Write-Host "$GREEN✅ [Успех]$NC Функция a`$ успешно модифицирована"
                    $modifiedCount++
                    continue
                }

                $content = $injectCode + $content
                Write-Host "$GREEN✅ [Успех]$NC Универсальная инъекция выполнена успешно"
                $modifiedCount++
            }
            elseif ($content -match "function t\$\(\)" -or $content -match "async function y5") {
                Write-Host "$BLUE🔍 [Обнаружение]$NC Найдены функции идентификации устройства"

                if ($content -match "function t\$\(\)") {
                    $content = $content -replace "function t\$\(\)\{", "function t`$(){return `"00:00:00:00:00:00`";"
                    Write-Host "$GREEN✅ [Успех]$NC Функция получения MAC-адреса модифицирована"
                }

                if ($content -match "async function y5") {
                    $content = $content -replace "async function y5\(t\)\{", "async function y5(t){return crypto.randomUUID();"
                    Write-Host "$GREEN✅ [Успех]$NC Функция идентификации устройства модифицирована"
                }

                $modifiedCount++
            }
            else {
                Write-Host "$YELLOW⚠️  [Предупреждение]$NC Шаблоны функций не найдены, используется универсальная инъекция"
                $content = $injectCode + $content
                $modifiedCount++
            }

            Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline
            Write-Host "$GREEN✅ [Завершено]$NC Файл успешно модифицирован: $(Split-Path $file -Leaf)"

        } catch {
            Write-Host "$RED❌ [Ошибка]$NC Ошибка модификации файла: $($_.Exception.Message)"
            $fileName = Split-Path $file -Leaf
            $backupFile = "$backupPath\$fileName"
            if (Test-Path $backupFile) {
                Copy-Item $backupFile $file -Force
                Write-Host "$YELLOW🔄 [Восстановление]$NC Файл восстановлен из резервной копии"
            }
        }
    }

    if ($modifiedCount -gt 0) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Завершено]$NC Успешно модифицировано $modifiedCount JS-файлов"
        Write-Host "$BLUE💾 [Резервирование]$NC Резервные копии: $backupPath"
        Write-Host "$BLUE💡 [Информация]$NC Функция JS-инъекции активирована"
        return $true
    } else {
        Write-Host "$RED❌ [Сбой]$NC Файлы не были модифицированы"
        return $false
    }
}

function Remove-CursorTrialFolders {
    Write-Host ""
    Write-Host "$GREEN🎯 [Основная функция]$NC Выполнение удаления пробных папок Cursor Pro..."
    Write-Host "$BLUE📋 [Описание]$NC Эта функция удалит указанные папки Cursor для сброса пробного периода"
    Write-Host ""

    $foldersToDelete = @()
    $adminPaths = @(
        "C:\Users\Administrator\.cursor",
        "C:\Users\Administrator\AppData\Roaming\Cursor"
    )
    $currentUserPaths = @(
        "$env:USERPROFILE\.cursor",
        "$env:APPDATA\Cursor"
    )
    $foldersToDelete += $adminPaths
    $foldersToDelete += $currentUserPaths

    Write-Host "$BLUE📂 [Проверка]$NC Будут проверены следующие папки:"
    foreach ($folder in $foldersToDelete) {
        Write-Host "   📁 $folder"
    }
    Write-Host ""

    $deletedCount = 0
    $skippedCount = 0
    $errorCount = 0

    foreach ($folder in $foldersToDelete) {
        Write-Host "$BLUE🔍 [Проверка]$NC Проверка папки: $folder"

        if (Test-Path $folder) {
            try {
                Write-Host "$YELLOW⚠️  [Предупреждение]$NC Папка обнаружена, удаление..."
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Host "$GREEN✅ [Успех]$NC Папка удалена: $folder"
                $deletedCount++
            }
            catch {
                Write-Host "$RED❌ [Ошибка]$NC Ошибка удаления папки: $folder"
                Write-Host "$RED💥 [Детали]$NC Ошибка: $($_.Exception.Message)"
                $errorCount++
            }
        } else {
            Write-Host "$YELLOW⏭️  [Пропуск]$NC Папка не существует: $folder"
            $skippedCount++
        }
        Write-Host ""
    }

    Write-Host "$GREEN📊 [Статистика]$NC Результаты выполнения:"
    Write-Host "   ✅ Удалено: $deletedCount папок"
    Write-Host "   ⏭️  Пропущено: $skippedCount папок"
    Write-Host "   ❌ Ошибок: $errorCount папок"
    Write-Host ""

    if ($deletedCount -gt 0) {
        Write-Host "$GREEN🎉 [Завершено]$NC Удаление пробных папок Cursor Pro завершено!"

        Write-Host "$BLUE🔧 [Восстановление]$NC Создание структуры каталогов..."
        $cursorAppData = "$env:APPDATA\Cursor"
        $cursorLocalAppData = "$env:LOCALAPPDATA\cursor"
        $cursorUserProfile = "$env:USERPROFILE\.cursor"

        try {
            if (-not (Test-Path $cursorAppData)) {
                New-Item -ItemType Directory -Path $cursorAppData -Force | Out-Null
            }
            if (-not (Test-Path $cursorUserProfile)) {
                New-Item -ItemType Directory -Path $cursorUserProfile -Force | Out-Null
            }
            Write-Host "$GREEN✅ [Завершено]$NC Структура каталогов восстановлена"
        } catch {
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Ошибка создания каталогов: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW🤔 [Информация]$NC Целевые папки не найдены, возможно уже удалены"
    }
    Write-Host ""
}

function Restart-CursorAndWait {
    Write-Host ""
    Write-Host "$GREEN🔄 [Перезапуск]$NC Перезапуск Cursor для генерации конфигурации..."

    if (-not $global:CursorProcessInfo) {
        Write-Host "$RED❌ [Ошибка]$NC Информация о процессе Cursor отсутствует"
        return $false
    }

    $cursorPath = $global:CursorProcessInfo.Path
    if ($cursorPath -is [array]) {
        $cursorPath = $cursorPath[0]
    }

    if ([string]::IsNullOrEmpty($cursorPath)) {
        Write-Host "$RED❌ [Ошибка]$NC Путь к Cursor не определен"
        return $false
    }

    Write-Host "$BLUE📍 [Путь]$NC Используемый путь: $cursorPath"

    if (-not (Test-Path $cursorPath)) {
        Write-Host "$RED❌ [Ошибка]$NC Исполняемый файл Cursor не найден: $cursorPath"

        $backupPaths = @(
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:PROGRAMFILES\Cursor\Cursor.exe",
            "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
        )

        $foundPath = $null
        foreach ($backupPath in $backupPaths) {
            if (Test-Path $backupPath) {
                $foundPath = $backupPath
                Write-Host "$GREEN💡 [Обнаружение]$NC Использован альтернативный путь: $foundPath"
                break
            }
        }

        if (-not $foundPath) {
            Write-Host "$RED❌ [Ошибка]$NC Действительный исполняемый файл Cursor не найден"
            return $false
        }

        $cursorPath = $foundPath
    }

    try {
        Write-Host "$GREEN🚀 [Запуск]$NC Запуск Cursor..."
        $process = Start-Process -FilePath $cursorPath -PassThru -WindowStyle Hidden

        Write-Host "$YELLOW⏳ [Ожидание]$NC Ожидание генерации конфигурации (20 секунд)..."
        Start-Sleep -Seconds 20

        $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
        $maxWait = 45
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Write-Host "$YELLOW⏳ [Ожидание]$NC Ожидание генерации конфигурации... ($waited/$maxWait сек)"
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN✅ [Успех]$NC Конфигурационный файл сгенерирован: $configPath"
            Write-Host "$YELLOW⏳ [Ожидание]$NC Финальная проверка записи (5 секунд)..."
            Start-Sleep -Seconds 5
        } else {
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Конфигурационный файл не сгенерирован"
            Write-Host "$BLUE💡 [Подсказка]$NC Может потребоваться ручной запуск Cursor"
        }

        Write-Host "$YELLOW🔄 [Закрытие]$NC Завершение Cursor для модификации конфигурации..."
        if ($process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000)
        }

        Get-Process -Name "Cursor" -ErrorAction SilentlyContinue | Stop-Process -Force
        Get-Process -Name "cursor" -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-Host "$GREEN✅ [Завершено]$NC Процедура перезапуска завершена"
        return $true

    } catch {
        Write-Host "$RED❌ [Ошибка]$NC Ошибка перезапуска Cursor: $($_.Exception.Message)"
        Write-Host "$BLUE💡 [Отладка]$NC Детали ошибки: $($_.Exception.GetType().FullName)"
        return $false
    }
}

function Stop-AllCursorProcesses {
    param(
        [int]$MaxRetries = 3,
        [int]$WaitSeconds = 5
    )

    Write-Host "$BLUE🔒 [Проверка процессов]$NC Проверка и завершение связанных процессов Cursor..."

    $cursorProcessNames = @(
        "Cursor",
        "cursor",
        "Cursor Helper",
        "Cursor Helper (GPU)",
        "Cursor Helper (Plugin)",
        "Cursor Helper (Renderer)",
        "CursorUpdater"
    )

    for ($retry = 1; $retry -le $MaxRetries; $retry++) {
        Write-Host "$BLUE🔍 [Проверка]$NC Попытка $retry/$MaxRetries..."

        $foundProcesses = @()
        foreach ($processName in $cursorProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                $foundProcesses += $processes
                Write-Host "$YELLOW⚠️  [Обнаружение]$NC Процесс: $processName (PID: $($processes.Id -join ', '))"
            }
        }

        if ($foundProcesses.Count -eq 0) {
            Write-Host "$GREEN✅ [Успех]$NC Все процессы Cursor завершены"
            return $true
        }

        Write-Host "$YELLOW🔄 [Завершение]$NC Завершение $($foundProcesses.Count) процессов Cursor..."

        foreach ($process in $foundProcesses) {
            try {
                $process.CloseMainWindow() | Out-Null
                Write-Host "$BLUE  • Graceful закрытие: $($process.ProcessName) (PID: $($process.Id))$NC"
            } catch {
                Write-Host "$YELLOW  • Graceful закрытие не удалось: $($process.ProcessName)$NC"
            }
        }

        Start-Sleep -Seconds 3

        foreach ($processName in $cursorProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                foreach ($process in $processes) {
                    try {
                        Stop-Process -Id $process.Id -Force
                        Write-Host "$RED  • Принудительное завершение: $($process.ProcessName) (PID: $($process.Id))$NC"
                    } catch {
                        Write-Host "$RED  • Принудительное завершение не удалось: $($process.ProcessName)$NC"
                    }
                }
            }
        }

        if ($retry -lt $MaxRetries) {
            Write-Host "$YELLOW⏳ [Ожидание]$NC Ожидание $WaitSeconds секунд перед повторной проверкой..."
            Start-Sleep -Seconds $WaitSeconds
        }
    }

    Write-Host "$RED❌ [Сбой]$NC Процессы Cursor все еще активны после $MaxRetries попыток"
    return $false
}

function Test-FileAccessibility {
    param([string]$FilePath)
    Write-Host "$BLUE🔐 [Проверка прав]$NC Проверка прав доступа: $(Split-Path $FilePath -Leaf)"

    if (-not (Test-Path $FilePath)) {
        Write-Host "$RED❌ [Ошибка]$NC Файл не существует"
        return $false
    }

    try {
        $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        $fileStream.Close()
        Write-Host "$GREEN✅ [Права]$NC Файл доступен для чтения/записи"
        return $true
    } catch [System.IO.IOException] {
        Write-Host "$RED❌ [Блокировка]$NC Файл заблокирован другим процессом: $($_.Exception.Message)"
        return $false
    } catch [System.UnauthorizedAccessException] {
        Write-Host "$YELLOW⚠️  [Права]$NC Недостаточно прав, попытка исправления..."

        try {
            $file = Get-Item $FilePath
            if ($file.IsReadOnly) {
                $file.IsReadOnly = $false
                Write-Host "$GREEN✅ [Исправление]$NC Атрибут 'только чтение' снят"
            }

            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            Write-Host "$GREEN✅ [Права]$NC Права доступа успешно исправлены"
            return $true
        } catch {
            Write-Host "$RED❌ [Права]$NC Не удалось исправить права: $($_.Exception.Message)"
            return $false
        }
    } catch {
        Write-Host "$RED❌ [Ошибка]$NC Неизвестная ошибка: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-CursorInitialization {
    Write-Host ""
    Write-Host "$GREEN🧹 [Инициализация]$NC Очистка окружения Cursor..."
    $BASE_PATH = "$env:APPDATA\Cursor\User"

    $filesToDelete = @(
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb"),
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb.backup")
    )

    $folderToCleanContents = Join-Path -Path $BASE_PATH -ChildPath "History"
    $folderToDeleteCompletely = Join-Path -Path $BASE_PATH -ChildPath "workspaceStorage"

    Write-Host "$BLUE🔍 [Отладка]$NC Базовый путь: $BASE_PATH"

    foreach ($file in $filesToDelete) {
        Write-Host "$BLUE🔍 [Проверка]$NC Проверка файла: $file"
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force -ErrorAction Stop
                Write-Host "$GREEN✅ [Успех]$NC Файл удален: $file"
            }
            catch {
                Write-Host "$RED❌ [Ошибка]$NC Ошибка удаления файла ${file}: $($_.Exception.Message)"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Пропуск]$NC Файл не существует: $file"
        }
    }

    Write-Host "$BLUE🔍 [Проверка]$NC Проверка папки: $folderToCleanContents"
    if (Test-Path $folderToCleanContents) {
        try {
            Get-ChildItem -Path $folderToCleanContents -Recurse | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-Host "$GREEN✅ [Успех]$NC Содержимое папки очищено: $folderToCleanContents"
        }
        catch {
            Write-Host "$RED❌ [Ошибка]$NC Ошибка очистки папки ${folderToCleanContents}: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW⚠️  [Пропуск]$NC Папка не существует: $folderToCleanContents"
    }

    Write-Host "$BLUE🔍 [Проверка]$NC Проверка папки: $folderToDeleteCompletely"
    if (Test-Path $folderToDeleteCompletely) {
        try {
            Remove-Item -Path $folderToDeleteCompletely -Recurse -Force -ErrorAction Stop
            Write-Host "$GREEN✅ [Успех]$NC Папка удалена: $folderToDeleteCompletely"
        }
        catch {
            Write-Host "$RED❌ [Ошибка]$NC Ошибка удаления папки ${folderToDeleteCompletely}: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW⚠️  [Пропуск]$NC Папка не существует: $folderToDeleteCompletely"
    }

    Write-Host "$GREEN✅ [Завершено]$NC Очистка окружения Cursor завершена"
    Write-Host ""
}

function Update-MachineGuid {
    try {
        Write-Host "$BLUE🔧 [Реестр]$NC Модификация системного реестра (MachineGuid)..."

        $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        if (-not (Test-Path $registryPath)) {
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Путь в реестре отсутствует: $registryPath, создание..."
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "$GREEN✅ [Информация]$NC Путь реестра создан"
        }

        $originalGuid = ""
        try {
            $currentGuid = Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction SilentlyContinue
            if ($currentGuid) {
                $originalGuid = $currentGuid.MachineGuid
                Write-Host "$GREEN✅ [Информация]$NC Текущее значение реестра:"
                Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
                Write-Host "    MachineGuid    REG_SZ    $originalGuid"
            } else {
                Write-Host "$YELLOW⚠️  [Предупреждение]$NC Значение MachineGuid отсутствует, будет создано новое"
            }
        } catch {
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Ошибка чтения реестра: $($_.Exception.Message)"
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Будет создано новое значение MachineGuid"
        }

        $backupFile = $null
        if ($originalGuid) {
            $backupFile = "$BACKUP_DIR\MachineGuid_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            Write-Host "$BLUE💾 [Резервирование]$NC Создание резервной копии реестра..."
            $backupResult = Start-Process "reg.exe" -ArgumentList "export", "`"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography`"", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($backupResult.ExitCode -eq 0) {
                Write-Host "$GREEN✅ [Резервирование]$NC Резервная копия создана: $backupFile"
            } else {
                Write-Host "$YELLOW⚠️  [Предупреждение]$NC Ошибка создания резервной копии, продолжение..."
                $backupFile = $null
            }
        }

        $newGuid = [System.Guid]::NewGuid().ToString()
        Write-Host "$BLUE🔄 [Генерация]$NC Новый MachineGuid: $newGuid"

        Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid -Force -ErrorAction Stop

        $verifyGuid = (Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($verifyGuid -ne $newGuid) {
            throw "Проверка реестра не удалась: полученное значение ($verifyGuid) не соответствует ожидаемому ($newGuid)"
        }

        Write-Host "$GREEN✅ [Успех]$NC Реестр успешно обновлен:"
        Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
        Write-Host "    MachineGuid    REG_SZ    $newGuid"
        return $true
    }
    catch {
        Write-Host "$RED❌ [Ошибка]$NC Ошибка работы с реестром: $($_.Exception.Message)"

        if ($backupFile -and (Test-Path $backupFile)) {
            Write-Host "$YELLOW🔄 [Восстановление]$NC Восстановление из резервной копии..."
            $restoreResult = Start-Process "reg.exe" -ArgumentList "import", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($restoreResult.ExitCode -eq 0) {
                Write-Host "$GREEN✅ [Восстановление]$NC Исходное значение реестра восстановлено"
            } else {
                Write-Host "$RED❌ [Ошибка]$NC Ошибка восстановления, выполните вручную: $backupFile"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Предупреждение]$NC Резервная копия не найдена, автоматическое восстановление невозможно"
        }

        return $false
    }
}

function Test-CursorEnvironment {
    param([string]$Mode = "FULL")
    Write-Host ""
    Write-Host "$BLUE🔍 [Проверка окружения]$NC Проверка окружения Cursor..."

    $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
    $cursorAppData = "$env:APPDATA\Cursor"
    $issues = @()

    if (-not (Test-Path $configPath)) {
        $issues += "Конфигурационный файл отсутствует: $configPath"
    } else {
        try {
            $content = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $content | ConvertFrom-Json -ErrorAction Stop
            Write-Host "$GREEN✅ [Проверка]$NC Формат конфигурационного файла корректен"
        } catch {
            $issues += "Ошибка формата конфигурационного файла: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path $cursorAppData)) {
        $issues += "Директория данных приложения отсутствует: $cursorAppData"
    }

    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:PROGRAMFILES\Cursor\Cursor.exe",
        "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
    )

    $cursorFound = $false
    foreach ($path in $cursorPaths) {
        if (Test-Path $path) {
            Write-Host "$GREEN✅ [Проверка]$NC Найдена установка Cursor: $path"
            $cursorFound = $true
            break
        }
    }

    if (-not $cursorFound) {
        $issues += "Установка Cursor не обнаружена, убедитесь в корректности установки"
    }

    if ($issues.Count -eq 0) {
        Write-Host "$GREEN✅ [Проверка окружения]$NC Все проверки пройдены"
        return @{ Success = $true; Issues = @() }
    } else {
        Write-Host "$RED❌ [Проверка окружения]$NC Обнаружено $($issues.Count) проблем:"
        foreach ($issue in $issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        return @{ Success = $false; Issues = $issues }
    }
}

function Modify-MachineCodeConfig {
    param([string]$Mode = "FULL")
    Write-Host ""
    Write-Host "$GREEN🛠️  [Конфигурация]$NC Модификация конфигурации машинного кода..."

    $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"

    if (-not (Test-Path $configPath)) {
        Write-Host "$RED❌ [Ошибка]$NC Конфигурационный файл отсутствует: $configPath"
        Write-Host ""
        Write-Host "$YELLOW💡 [Решение]$NC Выполните следующие шаги:"
        Write-Host "$BLUE  1️⃣  Запустите Cursor вручную$NC"
        Write-Host "$BLUE  2️⃣  Дождитесь полной загрузки (~30 секунд)$NC"
        Write-Host "$BLUE  3️⃣  Закройте Cursor$NC"
        Write-Host "$BLUE  4️⃣  Перезапустите скрипт$NC"
        Write-Host ""
        Write-Host "$YELLOW⚠️  [Альтернатива]$NC Если проблема сохраняется:"
        Write-Host "$BLUE  • Выберите 'Сброс окружения + модификация машинного кода'$NC"
        Write-Host "$BLUE  • Эта опция автоматически сгенерирует конфигурационный файл$NC"
        Write-Host ""

        $userChoice = Read-Host "Попытаться запустить Cursor для генерации конфига? (y/n)"
        if ($userChoice -match "^(y|yes)$") {
            Write-Host "$BLUE🚀 [Попытка]$NC Попытка запуска Cursor..."
            return Start-CursorToGenerateConfig
        }
        return $false
    }

    if ($Mode -eq "MODIFY_ONLY") {
        Write-Host "$BLUE🔒 [Проверка безопасности]$NC Обеспечение полного завершения процессов Cursor"
        if (-not (Stop-AllCursorProcesses -MaxRetries 3 -WaitSeconds 3)) {
            Write-Host "$RED❌ [Ошибка]$NC Не удалось завершить процессы Cursor"
            $userChoice = Read-Host "Продолжить принудительно? (y/n)"
            if ($userChoice -notmatch "^(y|yes)$") {
                return $false
            }
        }
    }

    if (-not (Test-FileAccessibility -FilePath $configPath)) {
        Write-Host "$RED❌ [Ошибка]$NC Нет доступа к конфигурационному файлу"
        return $false
    }

    try {
        Write-Host "$BLUE🔍 [Валидация]$NC Проверка формата конфигурационного файла..."
        $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $originalContent | ConvertFrom-Json -ErrorAction Stop
        Write-Host "$GREEN✅ [Валидация]$NC Формат конфигурационного файла корректен"

        $telemetryProperties = @('telemetry.machineId', 'telemetry.macMachineId', 'telemetry.devDeviceId', 'telemetry.sqmId')
        foreach ($prop in $telemetryProperties) {
            if ($config.PSObject.Properties[$prop]) {
                $value = $config.$prop
                $displayValue = if ($value.Length -gt 20) { "$($value.Substring(0,20))..." } else { $value }
                Write-Host "$GREEN  ✓ ${prop}$NC = $displayValue"
            } else {
                Write-Host "$YELLOW  - ${prop}$NC (отсутствует, будет создано)"
            }
        }
        Write-Host ""
    } catch {
        Write-Host "$RED❌ [Ошибка]$NC Ошибка формата конфигурационного файла: $($_.Exception.Message)"
        Write-Host "$YELLOW💡 [Рекомендация]$NC Файл поврежден, используйте 'Сброс окружения + модификация машинного кода'"
        return $false
    }

    $maxRetries = 3
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        $retryCount++
        Write-Host ""
        Write-Host "$BLUE🔄 [Попытка]$NC Попытка модификации $retryCount/$maxRetries..."

        try {
            Write-Host "$BLUE⏳ [Прогресс]$NC 1/6 - Генерация новых идентификаторов устройства..."
            $MAC_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            $UUID = [System.Guid]::NewGuid().ToString()
            $prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
            $prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
            $randomBytes = New-Object byte[] 32
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($randomBytes)
            $randomPart = [System.BitConverter]::ToString($randomBytes) -replace '-',''
            $rng.Dispose()
            $MACHINE_ID = "${prefixHex}${randomPart}"
            $SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"
            Write-Host "$GREEN✅ [Прогресс]$NC 1/6 - Идентификаторы устройства сгенерированы"

            Write-Host "$BLUE⏳ [Прогресс]$NC 2/6 - Создание директории для резервных копий..."
            $backupDir = "$env:APPDATA\Cursor\User\globalStorage\backups"
            if (-not (Test-Path $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
            }

            $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')_retry$retryCount"
            $backupPath = "$backupDir\$backupName"
            Write-Host "$BLUE⏳ [Прогресс]$NC 3/6 - Создание резервной копии конфигурации..."
            Copy-Item $configPath $backupPath -ErrorAction Stop

            if (Test-Path $backupPath) {
                $backupSize = (Get-Item $backupPath).Length
                $originalSize = (Get-Item $configPath).Length
                if ($backupSize -eq $originalSize) {
                    Write-Host "$GREEN✅ [Прогресс]$NC 3/6 - Резервная копия создана: $backupName"
                } else {
                    Write-Host "$YELLOW⚠️  [Предупреждение]$NC Размер резервной копии не соответствует, продолжение"
                }
            } else {
                throw "Ошибка создания резервной копии"
            }

            Write-Host "$BLUE⏳ [Прогресс]$NC 4/6 - Чтение оригинальной конфигурации в память..."
            $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $originalContent | ConvertFrom-Json -ErrorAction Stop
            Write-Host "$BLUE⏳ [Прогресс]$NC 5/6 - Обновление конфигурации в памяти..."

            $propertiesToUpdate = @{
                'telemetry.machineId' = $MACHINE_ID
                'telemetry.macMachineId' = $MAC_MACHINE_ID
                'telemetry.devDeviceId' = $UUID
                'telemetry.sqmId' = $SQM_ID
            }

            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $value = $property.Value

                if ($config.PSObject.Properties[$key]) {
                    $config.$key = $value
                    Write-Host "$BLUE  ✓ Обновлено свойство: ${key}$NC"
                } else {
                    $config | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
                    Write-Host "$BLUE  + Добавлено свойство: ${key}$NC"
                }
            }

            Write-Host "$BLUE⏳ [Прогресс]$NC 6/6 - Атомарная запись новой конфигурации..."
            $tempPath = "$configPath.tmp"
            $updatedJson = $config | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($tempPath, $updatedJson, [System.Text.Encoding]::UTF8)

            $tempContent = Get-Content $tempPath -Raw -Encoding UTF8
            $tempConfig = $tempContent | ConvertFrom-Json
            $tempVerificationPassed = $true
            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $tempConfig.$key

                if ($actualValue -ne $expectedValue) {
                    $tempVerificationPassed = $false
                    Write-Host "$RED  ✗ Проверка временного файла не пройдена: ${key}$NC"
                    break
                }
            }

            if (-not $tempVerificationPassed) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                throw "Проверка временного файла не пройдена"
            }

            Remove-Item $configPath -Force
            Move-Item $tempPath $configPath
            $file = Get-Item $configPath
            $file.IsReadOnly = $false

            Write-Host "$BLUE🔍 [Финальная проверка]$NC Валидация новой конфигурации..."
            $verifyContent = Get-Content $configPath -Raw -Encoding UTF8
            $verifyConfig = $verifyContent | ConvertFrom-Json
            $verificationPassed = $true
            $verificationResults = @()

            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $verifyConfig.$key

                if ($actualValue -eq $expectedValue) {
                    $verificationResults += "✓ ${key}: успешно"
                } else {
                    $verificationResults += "✗ ${key}: сбой (ожидалось: ${expectedValue}, получено: ${actualValue})"
                    $verificationPassed = $false
                }
            }

            Write-Host "$BLUE📋 [Результаты проверки]$NC"
            foreach ($result in $verificationResults) {
                Write-Host "   $result"
            }

            if ($verificationPassed) {
                Write-Host "$GREEN✅ [Успех]$NC Попытка модификации $retryCount успешна!"
                Write-Host ""
                Write-Host "$GREEN🎉 [Завершено]$NC Модификация конфигурации машинного кода завершена!"
                Write-Host "$BLUE📋 [Детали]$NC Обновленные идентификаторы:"
                Write-Host "   🔹 machineId: $MACHINE_ID"
                Write-Host "   🔹 macMachineId: $MAC_MACHINE_ID"
                Write-Host "   🔹 devDeviceId: $UUID"
                Write-Host "   🔹 sqmId: $SQM_ID"
                Write-Host ""
                Write-Host "$GREEN💾 [Резервирование]$NC Оригинальная конфигурация: $backupName"

                Write-Host "$BLUE🔒 [Защита]$NC Применение защиты конфигурационного файла..."
                try {
                    $configFile = Get-Item $configPath
                    $configFile.IsReadOnly = $true
                    Write-Host "$GREEN✅ [Защита]$NC Файл конфигурации защищен от перезаписи"
                    Write-Host "$BLUE💡 [Подсказка]$NC Путь: $configPath"
                } catch {
                    Write-Host "$YELLOW⚠️  [Защита]$NC Ошибка установки атрибута 'только чтение': $($_.Exception.Message)"
                    Write-Host "$BLUE💡 [Рекомендация]$NC Установите атрибут вручную через свойства файла"
                }
                Write-Host "$BLUE 🔒 [Безопасность]$NC Для применения изменений перезапустите Cursor"
                return $true
            } else {
                Write-Host "$RED❌ [Сбой]$NC Попытка $retryCount не прошла проверку"
                if ($retryCount -lt $maxRetries) {
                    Write-Host "$BLUE🔄 [Восстановление]$NC Восстановление резервной копии, повторная попытка..."
                    Copy-Item $backupPath $configPath -Force
                    Start-Sleep -Seconds 2
                    continue
                } else {
                    Write-Host "$RED❌ [Финальный сбой]$NC Все попытки провалились, восстановление оригинальной конфигурации"
                    Copy-Item $backupPath $configPath -Force
                    return $false
                }
            }

        } catch {
            Write-Host "$RED❌ [Исключение]$NC Ошибка при попытке ${retryCount}: $($_.Exception.Message)"
            Write-Host "$BLUE💡 [Отладка]$NC Тип ошибки: $($_.Exception.GetType().FullName)"

            if (Test-Path "$configPath.tmp") {
                Remove-Item "$configPath.tmp" -Force -ErrorAction SilentlyContinue
            }

            if ($retryCount -lt $maxRetries) {
                Write-Host "$BLUE🔄 [Восстановление]$NC Восстановление резервной копии, повторная попытка..."
                if (Test-Path $backupPath) {
                    Copy-Item $backupPath $configPath -Force
                }
                Start-Sleep -Seconds 3
                continue
            } else {
                Write-Host "$RED❌ [Финальный сбой]$NC Все попытки провалились"
                if (Test-Path $backupPath) {
                    Write-Host "$BLUE🔄 [Восстановление]$NC Восстановление из резервной копии..."
                    try {
                        Copy-Item $backupPath $configPath -Force
                        Write-Host "$GREEN✅ [Восстановление]$NC Оригинальная конфигурация восстановлена"
                    } catch {
                        Write-Host "$RED❌ [Ошибка]$NC Ошибка восстановления: $($_.Exception.Message)"
                    }
                }
                return $false
            }
        }
    }

    Write-Host "$RED❌ [Финальный сбой]$NC Модификация не удалась после $maxRetries попыток"
    return $false
}

function Start-CursorToGenerateConfig {
    Write-Host "$BLUE🚀 [Запуск]$NC Попытка запуска Cursor для генерации конфигурации..."

    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:PROGRAMFILES\Cursor\Cursor.exe",
        "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
    )

    $cursorPath = $null
    foreach ($path in $cursorPaths) {
        if (Test-Path $path) {
            $cursorPath = $path
            break
        }
    }

    if (-not $cursorPath) {
        Write-Host "$RED❌ [Ошибка]$NC Установка Cursor не обнаружена"
        return $false
    }

    try {
        Write-Host "$BLUE📍 [Путь]$NC Используемый путь: $cursorPath"
        $process = Start-Process -FilePath $cursorPath -PassThru -WindowStyle Normal
        Write-Host "$GREEN🚀 [Запуск]$NC Cursor запущен, PID: $($process.Id)"

        Write-Host "$YELLOW⏳ [Ожидание]$NC Ожидание полной загрузки Cursor (~30 секунд)..."
        Write-Host "$BLUE💡 [Подсказка]$NC Закройте Cursor после полной загрузки"

        $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
        $maxWait = 60
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Start-Sleep -Seconds 2
            $waited += 2
            if ($waited % 10 -eq 0) {
                Write-Host "$YELLOW⏳ [Ожидание]$NC Ожидание генерации конфигурации... ($waited/$maxWait сек)"
            }
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN✅ [Успех]$NC Конфигурационный файл сгенерирован!"
            Write-Host "$BLUE💡 [Подсказка]$NC Закройте Cursor и перезапустите скрипт"
            return $true
        } else {
            Write-Host "$YELLOW⚠️  [Таймаут]$NC Конфигурационный файл не сгенерирован вовремя"
            Write-Host "$BLUE💡 [Рекомендация]$NC Выполните действия в Cursor вручную для генерации"
            return $false
        }

    } catch {
        Write-Host "$RED❌ [Ошибка]$NC Ошибка запуска Cursor: $($_.Exception.Message)"
        return $false
    }
}

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[Ошибка]$NC Запустите скрипт с правами администратора"
    Write-Host "Щелкните правой кнопкой и выберите 'Запуск от имени администратора'"
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

Clear-Host
Write-Host @"

    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN🚀   Инструмент продления пробного периода Cursor Pro $NC"
Write-Host "$YELLOW📱  Канал: 【煎饼果子卷AI】 $NC"
Write-Host "$YELLOW🤝  Присоединяйтесь к сообществу для изучения Cursor и ИИ $NC"
Write-Host "$YELLOW💡  [Важно] Бесплатный инструмент, поддержите канал 【煎饼果子卷AI】 $NC"
Write-Host ""
Write-Host "$YELLOW💰  [Объявление] Продажа лицензий CursorPro EDU (гарантия 1 год) $NC"
Write-Host "$BLUE================================$NC"

Write-Host ""
Write-Host "$GREEN🎯 [Выбор режима]$NC Выберите действие:"
Write-Host ""
Write-Host "$BLUE  1️⃣  Только модификация машинного кода$NC"
Write-Host "$YELLOW      • Изменение машинного кода$NC"
Write-Host "$YELLOW      • Инъекция JS в системные файлы$NC"
Write-Host "$YELLOW      • Без удаления данных$NC"
Write-Host "$YELLOW      • Сохранение настроек$NC"
Write-Host ""
Write-Host "$BLUE  2️⃣  Сброс окружения + модификация кода$NC"
Write-Host "$RED      • Полный сброс (удаление папок)$NC"
Write-Host "$RED      • ⚠️  Настройки будут утеряны$NC"
Write-Host "$YELLOW      • Модификация машинного кода$NC"
Write-Host "$YELLOW      • Инъекция JS$NC"
Write-Host "$YELLOW      • Полная функциональность$NC"
Write-Host ""

do {
    $userChoice = Read-Host "Введите выбор (1 или 2)"
    if ($userChoice -eq "1") {
        Write-Host "$GREEN✅ [Выбор]$NC Выбрано: Только модификация машинного кода"
        $executeMode = "MODIFY_ONLY"
        break
    } elseif ($userChoice -eq "2") {
        Write-Host "$GREEN✅ [Выбор]$NC Выбрано: Сброс окружения + модификация кода"
        Write-Host "$RED⚠️  [Важно]$NC Будут удалены все конфигурационные файлы!"
        $confirmReset = Read-Host "Подтвердите сброс (введите yes для подтверждения)"
        if ($confirmReset -eq "yes") {
            $executeMode = "RESET_AND_MODIFY"
            break
        } else {
            Write-Host "$YELLOW👋 [Отмена]$NC Действие отменено пользователем"
            continue
        }
    } else {
        Write-Host "$RED❌ [Ошибка]$NC Некорректный ввод, используйте 1 или 2"
    }
} while ($true)

Write-Host ""

if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN📋 [Процесс]$NC Режим модификации машинного кода:"
    Write-Host "$BLUE  1️⃣  Проверка конфигурации Cursor$NC"
    Write-Host "$BLUE  2️⃣  Резервное копирование конфига$NC"
    Write-Host "$BLUE  3️⃣  Модификация машинного кода$NC"
    Write-Host "$BLUE  4️⃣  Отображение результатов$NC"
    Write-Host ""
    Write-Host "$YELLOW⚠️  [Примечания]$NC"
    Write-Host "$YELLOW  • Данные не удаляются$NC"
    Write-Host "$YELLOW  • Настройки сохраняются$NC"
    Write-Host "$YELLOW  • Автоматическое резервное копирование$NC"
} else {
    Write-Host "$GREEN📋 [Процесс]$NC Режим сброса окружения:"
    Write-Host "$BLUE  1️⃣  Проверка и завершение процессов Cursor$NC"
    Write_Host "$BLUE  2️⃣  Сохранение информации о пути$NC"
    Write_Host "$BLUE  3️⃣  Удаление пробных папок$NC"
    Write_Host "$BLUE      📁 C:\Users\Administrator\.cursor$NC"
    Write_Host "$BLUE      📁 C:\Users\Administrator\AppData\Roaming\Cursor$NC"
    Write_Host "$BLUE      📁 C:\Users\%USERNAME%\.cursor$NC"
    Write_Host "$BLUE      📁 C:\Users\%USERNAME%\AppData\Roaming\Cursor$NC"
    Write_Host "$BLUE  3.5 Восстановление структуры каталогов$NC"
    Write_Host "$BLUE  4️⃣  Перезапуск Cursor$NC"
    Write_Host "$BLUE  5️⃣  Ожидание генерации конфига (до 45 сек)$NC"
    Write_Host "$BLUE  6️⃣  Завершение Cursor$NC"
    Write_Host "$BLUE  7️⃣  Модификация нового конфига$NC"
    Write_Host "$BLUE  8️⃣  Отображение статистики$NC"
    Write_Host ""
    Write_Host "$YELLOW⚠️  [Примечания]$NC"
    Write_Host "$YELLOW  • Не используйте Cursor во время работы скрипта$NC"
    Write_Host "$YELLOW  • Закройте все окна Cursor перед запуском$NC"
    Write_Host "$YELLOW  • Требуется перезапуск Cursor после завершения$NC"
    Write_Host "$YELLOW  • Автоматическое резервное копирование$NC"
}
Write_Host ""

Write_Host "$GREEN🤔 [Подтверждение]$NC Подтвердите понимание процесса"
$confirmation = Read_Host "Продолжить выполнение? (y/yes для продолжения)"
if ($confirmation -notmatch "^(y|yes)$") {
    Write_Host "$YELLOW👋 [Выход]$NC Выполнение отменено"
    Read_Host "Нажмите Enter для выхода"
    exit 0
}
Write_Host "$GREEN✅ [Подтверждение]$NC Подтверждение получено"
Write_Host ""

function Get-CursorVersion {
    try {
        $packagePath = "$env:LOCALAPPDATA\\Programs\\cursor\\resources\\app\\package.json"
        if (Test-Path $packagePath) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write_Host "$GREEN[Информация]$NC Версия Cursor: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        $altPath = "$env:LOCALAPPDATA\\cursor\\resources\\app\\package.json"
        if (Test-Path $altPath) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write_Host "$GREEN[Информация]$NC Версия Cursor: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write_Host "$YELLOW[Предупреждение]$NC Версия Cursor не определена"
        return $null
    }
    catch {
        Write_Host "$RED[Ошибка]$NC Ошибка определения версии: $_"
        return $null
    }
}

$cursorVersion = Get-CursorVersion
Write_Host ""
Write_Host "$YELLOW💡 [Важно]$NC Поддерживаются последние версии 1.0.x"
Write_Host ""

Write_Host "$GREEN🔍 [Проверка]$NC Проверка процессов Cursor..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE🔍 [Отладка]$NC Информация о процессе ${processName}:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" |
        Select-Object ProcessId, ExecutablePath, CommandLine |
        Format-List
}

$MAX_RETRIES = 5
$WAIT_TIME = 1

function Close-CursorProcessAndSaveInfo {
    param($processName)
    $global:CursorProcessInfo = $null
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Write_Host "$YELLOW⚠️  [Предупреждение]$NC Обнаружен процесс $processName"
        $firstProcess = if ($processes -is [array]) { $processes[0] } else { $processes }
        $processPath = $firstProcess.Path

        if ($processPath -is [array]) {
            $processPath = $processPath[0]
        }

        $global:CursorProcessInfo = @{
            ProcessName = $firstProcess.ProcessName
            Path = $processPath
            StartTime = $firstProcess.StartTime
        }
        Write_Host "$GREEN💾 [Сохранение]$NC Информация о процессе сохранена: $($global:CursorProcessInfo.Path)"
        Get-ProcessDetails $processName
        Write_Host "$YELLOW🔄 [Действие]$NC Завершение $processName..."
        Stop-Process -Name $processName -Force

        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }

            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write_Host "$RED❌ [Ошибка]$NC Не удалось завершить $processName после $MAX_RETRIES попыток"
                Get-ProcessDetails $processName
                Write_Host "$RED💥 [Ошибка]$NC Завершите процесс вручную и повторите"
                Read_Host "Нажмите Enter для выхода"
                exit 1
            }
            Write_Host "$YELLOW⏳ [Ожидание]$NC Ожидание завершения... ($retryCount/$MAX_RETRIES)"
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write_Host "$GREEN✅ [Успех]$NC $processName успешно завершен"
    } else {
        Write_Host "$BLUE💡 [Информация]$NC Процесс $processName не запущен"
        $cursorPaths = @(
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:PROGRAMFILES\Cursor\Cursor.exe",
            "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
        )

        foreach ($path in $cursorPaths) {
            if (Test-Path $path) {
                $global:CursorProcessInfo = @{
                    ProcessName = "Cursor"
                    Path = $path
                    StartTime = $null
                }
                Write_Host "$GREEN💾 [Обнаружение]$NC Путь установки: $path"
                break
            }
        }

        if (-not $global:CursorProcessInfo) {
            Write_Host "$YELLOW⚠️  [Предупреждение]$NC Путь установки не найден, используется путь по умолчанию"
            $global:CursorProcessInfo = @{
                ProcessName = "Cursor"
                Path = "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
                StartTime = $null
            }
        }
    }
}

if (-not (Test-Path $BACKUP_DIR)) {
    try {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write_Host "$GREEN✅ [Директория резерва]$NC Создана: $BACKUP_DIR"
    } catch {
        Write_Host "$YELLOW⚠️  [Предупреждение]$NC Ошибка создания директории: $($_.Exception.Message)"
    }
}

if ($executeMode -eq "MODIFY_ONLY") {
    Write_Host "$GREEN🚀 [Запуск]$NC Запуск режима модификации машинного кода..."
    $envCheck = Test-CursorEnvironment -Mode "MODIFY_ONLY"
    if (-not $envCheck.Success) {
        Write_Host ""
        Write_Host "$RED❌ [Ошибка окружения]$NC Обнаружены проблемы:"
        foreach ($issue in $envCheck.Issues) {
            Write_Host "$RED  • ${issue}$NC"
        }
        Write_Host ""
        Write_Host "$YELLOW💡 [Рекомендация]$NC Выберите:"
        Write_Host "$BLUE  1️⃣  'Сброс окружения + модификация кода' (рекомендуется)$NC"
        Write_Host "$BLUE  2️⃣  Запустите Cursor вручную и повторите$NC"
        Write_Host "$BLUE  3️⃣  Проверьте установку Cursor$NC"
        Write_Host ""
        Read_Host "Нажмите Enter для выхода"
        exit 1
    }

    $configSuccess = Modify-MachineCodeConfig -Mode "MODIFY_ONLY"

    if ($configSuccess) {
        Write_Host ""
        Write_Host "$GREEN🎉 [Конфигурация]$NC Модификация машинного кода завершена!"
        Write_Host "$BLUE🔧 [Реестр]$NC Модификация системного реестра..."
        $registrySuccess = Update-MachineGuid
        Write_Host ""
        Write_Host "$BLUE🔧 [Обход идентификации]$NC Выполнение JS-инъекции..."
        $jsSuccess = Modify-CursorJSFiles

        if ($registrySuccess) {
            Write_Host "$GREEN✅ [Реестр]$NC Системный реестр успешно обновлен"
            if ($jsSuccess) {
                Write_Host "$GREEN✅ [JS-инъекция]$NC Инъекция выполнена успешно"
                Write_Host ""
                Write_Host "$GREEN🎉 [Завершено]$NC Все операции успешно выполнены!"
                Write_Host "$BLUE📋 [Детали]$NC Выполнено:"
                Write_Host "$GREEN  ✓ Конфигурация Cursor (storage.json)$NC"
                Write_Host "$GREEN  ✓ Системный реестр (MachineGuid)$NC"
                Write_Host "$GREEN  ✓ JS-инъекция в ядро$NC"
            } else {
                Write_Host "$YELLOW⚠️  [JS-инъекция]$NC Сбой инъекции, остальные операции успешны"
                Write_Host ""
                Write_Host "$GREEN🎉 [Завершено]$NC Основные операции успешно выполнены"
                Write_Host "$BLUE📋 [Детали]$NC Выполнено:"
                Write_Host "$GREEN  ✓ Конфигурация Cursor (storage.json)$NC"
                Write_Host "$GREEN  ✓ Системный реестр (MachineGuid)$NC"
                Write_Host "$YELLOW  ⚠ JS-инъекция в ядро (частично)$NC"
            }
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write_Host "$GREEN✅ [Защита]$NC Конфигурация защищена от перезаписи"
                Write_Host "$BLUE💡 [Подсказка]$NC Путь: $configPath"
            } catch {
                Write_Host "$YELLOW⚠️  [Защита]$NC Ошибка установки защиты: $($_.Exception.Message)"
                Write_Host "$BLUE💡 [Рекомендация]$NC Установите атрибут вручную"
            }
        } else {
            Write_Host "$YELLOW⚠️  [Реестр]$NC Ошибка модификации реестра"
            if ($jsSuccess) {
                Write_Host "$GREEN✅ [JS-инъекция]$NC Инъекция выполнена успешно"
                Write_Host ""
                Write_Host "$YELLOW🎉 [Частично]$NC Основные операции выполнены, реестр не изменен"
                Write_Host "$BLUE💡 [Рекомендация]$NC Требуются права администратора"
                Write_Host "$BLUE📋 [Детали]$NC Выполнено:"
                Write_Host "$GREEN  ✓ Конфигурация Cursor (storage.json)$NC"
                Write_Host "$YELLOW  ⚠ Системный реестр (MachineGuid)$NC"
                Write_Host "$GREEN  ✓ JS-инъекция в ядро$NC"
            } else {
                Write_Host "$YELLOW⚠️  [JS-инъекция]$NC Сбой инъекции"
                Write_Host ""
                Write_Host "$YELLOW🎉 [Частично]$NC Конфигурация изменена, реестр и инъекция не выполнены"
                Write_Host "$BLUE💡 [Рекомендация]$NC Требуются права администратора"
            }
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write_Host "$GREEN✅ [Защита]$NC Конфигурация защищена от перезаписи"
                Write_Host "$BLUE💡 [Подсказка]$NC Путь: $configPath"
            } catch {
                Write_Host "$YELLOW⚠️  [Защита]$NC Ошибка установки защиты: $($_.Exception.Message)"
                Write_Host "$BLUE💡 [Рекомендация]$NC Установите атрибут вручную"
            }
        }
        Write_Host "$BLUE💡 [Информация]$NC Запустите Cursor для применения изменений"
    } else {
        Write_Host ""
        Write_Host "$RED❌ [Сбой]$NC Модификация машинного кода не удалась!"
        Write_Host "$YELLOW💡 [Рекомендация]$NC Используйте 'Сброс окружения + модификация кода'"
    }
} else {
    Write_Host "$GREEN🚀 [Запуск]$NC Запуск режима сброса окружения..."
    Close-CursorProcessAndSaveInfo "Cursor"
    if (-not $global:CursorProcessInfo) {
        Close-CursorProcessAndSaveInfo "cursor"
    }

    Write_Host ""
    Write_Host "$RED🚨 [Важно]$NC ============================================"
    Write_Host "$YELLOW⚠️  [Безопасность]$NC Cursor имеет строгую систему контроля!"
    Write_Host "$YELLOW⚠️  [Требуется]$NC Полное удаление указанных папок без остатка"
    Write_Host "$YELLOW⚠️  [Защита]$NC Только полная очистка гарантирует продление пробного периода"
    Write_Host "$RED🚨 [Важно]$NC ============================================"
    Write_Host ""

    Write_Host "$GREEN🚀 [Запуск]$NC Запуск основной функциональности..."
    Remove-CursorTrialFolders
    Restart-CursorAndWait
    $configSuccess = Modify-MachineCodeConfig
    Invoke-CursorInitialization

    if ($configSuccess) {
        Write_Host ""
        Write_Host "$GREEN🎉 [Конфигурация]$NC Модификация машинного кода завершена!"
        Write_Host "$BLUE🔧 [Реестр]$NC Модификация системного реестра..."
        $registrySuccess = Update-MachineGuid
        Write_Host ""
        Write_Host "$BLUE🔧 [Обход идентификации]$NC Выполнение JS-инъекции..."
        $jsSuccess = Modify-CursorJSFiles

        if ($registrySuccess) {
            Write_Host "$GREEN✅ [Реестр]$NC Системный реестр успешно обновлен"
            if ($jsSuccess) {
                Write_Host "$GREEN✅ [JS-инъекция]$NC Инъекция выполнена успешно"
                Write_Host ""
                Write_Host "$GREEN🎉 [Завершено]$NC Все операции успешно выполнены!"
                Write_Host "$BLUE📋 [Детали]$NC Выполнено:"
                Write_Host "$GREEN  ✓ Удаление пробных папок$NC"
                Write_Host "$GREEN  ✓ Очистка окружения$NC"
                Write_Host "$GREEN  ✓ Генерация конфигурации$NC"
                Write_Host "$GREEN  ✓ Модификация машинного кода$NC"
                Write_Host "$GREEN  ✓ Модификация реестра$NC"
                Write_Host "$GREEN  ✓ JS-инъекция в ядро$NC"
            } else {
                Write_Host "$YELLOW⚠️  [JS-инъекция]$NC Сбой инъекции, остальные операции успешны"
                Write_Host ""
                Write_Host "$GREEN🎉 [Завершено]$NC Основные операции успешно выполнены"
                Write_Host "$BLUE📋 [Детали]$NC Выполнено:"
                Write_Host "$GREEN  ✓ Удаление пробных папок$NC"
                Write_Host "$GREEN  ✓ Очистка окружения$NC"
                Write_Host "$GREEN  ✓ Генерация конфигурации$NC"
                Write_Host "$GREEN  ✓ Модификация машинного кода$NC"
                Write_Host "$GREEN  ✓ Модификация реестра$NC"
                Write_Host "$YELLOW  ⚠ JS-инъекция в ядро (частично)$NC"
            }
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write_Host "$GREEN✅ [Защита]$NC Конфигурация защищена от перезаписи"
                Write_Host "$BLUE💡 [Подсказка]$NC Путь: $configPath"
            } catch {
                Write_Host "$YELLOW⚠️  [Защита]$NC Ошибка установки защиты: $($_.Exception.Message)"
                Write_Host "$BLUE💡 [Рекомендация]$NC Установите атрибут вручную"
            }
        } else {
            Write_Host "$YELLOW⚠️  [Реестр]$NC Ошибка модификации реестра"
            if ($jsSuccess) {
                Write_Host "$GREEN✅ [JS-инъекция]$NC Инъекция выполнена успешно"
                Write_Host ""
                Write_Host "$YELLOW🎉 [Частично]$NC Основные операции выполнены, реестр не изменен"
                Write_Host "$BLUE💡 [Рекомендация]$NC Требуются права администратора"
                Write_Host "$BLUE📋 [Детали]$NC Выполнено:"
                Write_Host "$GREEN  ✓ Удаление пробных папок$NC"
                Write_Host "$GREEN  ✓ Очистка окружения$NC"
                Write_Host "$GREEN  ✓ Генерация конфигурации$NC"
                Write_Host "$GREEN  ✓ Модификация машинного кода$NC"
                Write_Host "$YELLOW  ⚠ Модификация реестра$NC"
                Write_Host "$GREEN  ✓ JS-инъекция в ядро$NC"
            } else {
                Write_Host "$YELLOW⚠️  [JS-инъекция]$NC Сбой инъекции"
                Write_Host ""
                Write_Host "$YELLOW🎉 [Частично]$NC Основные операции выполнены, реестр и инъекция не выполнены"
                Write_Host "$BLUE💡 [Рекомендация]$NC Требуются права администратора"
            }
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write_Host "$GREEN✅ [Защита]$NC Конфигурация защищена от перезаписи"
                Write_Host "$BLUE💡 [Подсказка]$NC Путь: $configPath"
            } catch {
                Write_Host "$YELLOW⚠️  [Защита]$NC Ошибка установки защиты: $($_.Exception.Message)"
                Write_Host "$BLUE💡 [Рекомендация]$NC Установите атрибут вручную"
            }
        }
    } else {
        Write_Host ""
        Write_Host "$RED❌ [Сбой]$NC Модификация машинного кода не удалась!"
        Write_Host "$YELLOW💡 [Рекомендация]$NC Проверьте ошибки и повторите"
    }
}

Write_Host ""
Write_Host "$GREEN================================$NC"
Write_Host "$YELLOW📱  Канал: 【煎饼果子卷AI】 - сообщество по Cursor и ИИ $NC"
Write_Host "$GREEN================================$NC"
Write_Host ""

Write_Host "$GREEN🎉 [Завершено]$NC Инструмент машинного кода Cursor успешно выполнен!"
Write_Host "$BLUE💡 [Информация]$NC При возникновении проблем обратитесь к каналу"
Write_Host ""
Read_Host "Нажмите Enter для выхода"
exit 0