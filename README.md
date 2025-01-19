# Overlay

Минималистичный системный оверлей для macOS, отображающий время, статус батареи, IP-адреса и календарь.

## Основные функции

- Прозрачное окно поверх всех окон
- Информация в реальном времени:
  - Текущее время (12/24 часовой формат)
  - Статус и уровень заряда батареи с визуальным индикатором
  - Локальный IP адрес
  - Публичный IP адрес
  - Статус сетевого подключения
  - Встроенный календарь с праздниками
- Минималистичный интерфейс с кнопками управления
- Поддержка всех дисплеев и рабочих пространств
- Анимированное отображение календаря

## Системные требования

- macOS 10.10 или новее
- 64-битный процессор (Intel или Apple Silicon)
- 50MB свободного места
- Базовое сетевое подключение
- Права администратора для установки

## Установка

### Из релиза
1. Скачайте последний релиз
2. Распакуйте архив
3. Переместите Overlay.app в папку Applications

### Сборка из исходников
1. Клонируйте репозиторий:
```bash
git clone https://github.com/vos9/overlay-objc.git
cd overlay-objc
```

2. Сборка с использованием make:
```bash
make release
```

3. Приложение будет собрано в `build/release/Overlay.app`

## Управление

### Клавиатурные сокращения
- ⌘Q - Выход из приложения
- ⌘H - Скрыть оверлей
- ⌘M - Переместить на следующий дисплей
- ⌘R - Обновить все данные
- ESC - Выход из полноэкранного режима

### Кнопки интерфейса
- × - Закрыть приложение
- C - Показать/скрыть календарь

### Функции календаря
- Отображение текущего месяца
- Подсветка текущей даты
- Отображение праздников
- Выбор даты кликом

## Технические детали

### Архитектура
- Написано на Objective-C с использованием Cocoa framework
- Использует IOKit для мониторинга батареи
- Мониторинг сетевых интерфейсов для определения IP
- Обновления на основе событий с эффективными таймерами
- Минимальное использование CPU и памяти

### Производительность
- Легковесное управление окнами
- Эффективное рисование с использованием NSBezierPath
- Оптимизированный мониторинг состояния батареи
- Асинхронные сетевые операции для определения IP
- Эффективное использование памяти для строк

### Управление памятью
- Эффективное использование autorelease pool
- Минимальные выделения в куче
- Автоматическая очистка памяти
- Отсутствие утечек памяти
- Оптимизированное управление строками

### Использование сети
- Определение локального IP: доступ только для чтения к сетевому интерфейсу
- Определение публичного IP: один HTTP запрос каждые 5 минут
- Механизм резервного копирования для работы в автономном режиме
- Отсутствие фоновой сетевой активности
- Минимальное использование пропускной способности (<1KB на запрос)

### Управление питанием
- Низкое воздействие на CPU (<0.1% в режиме ожидания)
- Эффективный мониторинг батареи
- Обработка событий сна/пробуждения
- Уведомления о событиях питания
- Автоматическая пауза обновлений в режиме экономии заряда

### Безопасность
- Отсутствие сбора или хранения данных
- Локальная работа
- Отсутствие сетевого доступа, кроме определения публичного IP
- Отсутствие фоновых процессов
- Песочница приложения

## Использование

1. Запустите приложение
2. Оверлей появится поверх всех окон
3. Оверлей игнорирует щелчки мыши, кроме кнопки закрытия
4. Для выхода нажмите кнопку закрытия (×) в правом верхнем углу

## Разработка

### Конфигурации сборки

- Релизная сборка: `make release`
- Отладочная сборка: `make debug`
- Профилирующая сборка: `make profile`

### Дополнительные команды

- Запуск статического анализатора: `make analyze`
- Генерация отладочных символов: `make dsym`
- Создание дистрибутивного пакета: `make dist`
- Очистка файлов сборки: `make clean`
- Показать все команды: `make help`

### Опции сборки

```bash
# Типы сборки
make release    # Оптимизированная сборка с -O3
make debug      # Отладочная сборка с санитайзерами
make profile    # Сборка с поддержкой профилирования

# Инструменты разработки
make analyze    # Запуск статического анализатора кода
make dsym       # Генерация отладочных символов
make sign       # Подпись приложения

# Дистрибуция
make dist       # Создание дистрибутивного пакета
make bundle     # Создание пакета приложения
make install    # Установка в папку Applications
```

### Структура проекта

```
overlay-objc/
├── OverlayView.h/m       # Основная реализация представления
├── OverlayWindowController.h/m # Управление окнами
├── main.m               # Точка входа в приложение
├── Makefile            # Система сборки
└── README.md           # Документация
```

### Метрики производительности

| Метрика | Значение |
|--------|--------|
| Использование CPU (в режиме ожидания) | <0.1% |
| Использование памяти | ~10MB |
| Время запуска | <100ms |
| Влияние на батарею | Незначительное |
| Использование сети | <1KB/5мин |

### Известные ограничения

- Нет поддержки версий macOS ниже 10.10
- Ограничено системным шрифтом по умолчанию
- Только один экземпляр
- Нет интерфейса конфигурации (планируется)
- Определение публичного IP требует интернет-соединения

### Вклад

1. Форкните репозиторий
2. Создайте ветку для вашей функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте ваши изменения (`git commit -m 'Add amazing feature'`)
4. Отправьте ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## Устранение неполадок

### Общие проблемы

1. Окно не появляется
   - Проверьте, разрешает ли System Integrity Protection наложение окон
   - Проверьте разрешения на доступность

2. IP-адреса не отображаются
   - Проверьте сетевое подключение
   - Проверьте настройки брандмауэра
   - Подождите асинхронного обновления (до 5 секунд)

3. Проблемы со сборкой
   - Убедитесь, что установлены инструменты командной строки Xcode
   - Проверьте совместимость версии macOS
   - Убедитесь, что все зависимости выполнены

## Лицензия

Copyright © 2025 vos9.su. All rights reserved.

## Автор

Создано vos9.su

## История версий

- ALPHA_1.0.1 - Первый выпуск с базовой функциональностью
- Планируются будущие выпуски с дополнительными функциями
