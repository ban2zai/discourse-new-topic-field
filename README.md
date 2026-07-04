# discourse-new-topic-field

Минимальный Discourse-плагин для сохранения внешнего GUID задачи в теме.

## Возможности

- читает `guid` из ссылки вида `/new-topic?category=...&tags=...&guid=...`;
- сохраняет `guid` в pre-initializer до редиректа Discourse с `/new-topic` на реальный список тем;
- показывает readonly-поле и плашку в composer;
- сохраняет значение в `TopicCustomField` темы;
- не даёт привязать один GUID к нескольким темам и останавливает создание темы из composer, если GUID уже занят;
- показывает автору темы сохранённый GUID без права изменения;
- даёт выбранным группам добавлять, менять и удалять GUID в существующей теме;
- опционально требует HMAC-подпись для ссылок создания темы с GUID;
- предоставляет JSON-поиск `GET /new-topic-field/topics?guid=<guid>`.

## HMAC-подпись ссылки

Для включения проверки:

1. задать `discourse_new_topic_field_signature_secret`;
2. включить `discourse_new_topic_field_require_signature`.

Подписывается строка с LF-разделителями:

```text
v1
guid=<guid>
expires=<unix_seconds>
nonce=<uuid>
```

В ссылку добавляются параметры:

```text
guid=<guid>&expires=<unix_seconds>&nonce=<uuid>&sig=<hmac_sha256_hex>
```

Быстро сгенерировать тестовую ссылку без 1С можно через helper:

```powershell
ruby script/generate_signed_new_topic_url.rb test-secret 09abcfac-0e44-11f1-86e9-a94ec75f6b04 https://forum.apogey.ru Обсуждения Техно
```

Перед тестом в админке Discourse нужно поставить такой же secret (`test-secret`) или заменить его в команде.
