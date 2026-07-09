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
ruby script/generate_signed_new_topic_url.rb test-secret 09abcfac-0e44-11f1-86e9-a94ec75f6b04
```

Перед тестом в админке Discourse нужно поставить такой же secret (`test-secret`) или заменить его в команде.

## Server-to-server lookup

Плагин владеет server-to-server API для связки `guid <-> topic_id`.

Для включения lookup endpoint'ов задайте отдельный secret setting:

```text
discourse_new_topic_field_lookup_token
```

Если setting пустой или URL token неверный, endpoint вернет `403`:

```json
{
  "ok": false,
  "error": "invalid_token"
}
```

Endpoint'ы не требуют Discourse login, session или API key. Доступ контролируется только URL token'ом.

### Поиск темы по GUID

```text
GET /topic-guid-fields/topics/by-guid/:guid/:token.json
```

Если тема найдена:

```json
{
  "ok": true,
  "found": true,
  "topic_id": 123,
  "guid": "09abcfac-0e44-11f1-86e9-a94ec75f6b04",
  "title": "Topic title",
  "slug": "topic-title",
  "url": "https://forum.example.com/t/topic-title/123",
  "created_at": "2026-07-09T10:00:00Z",
  "approval_status": {
    "available": false,
    "data": null
  }
}
```

Если GUID не найден:

```json
{
  "ok": true,
  "found": false,
  "topic_id": null,
  "guid": "09abcfac-0e44-11f1-86e9-a94ec75f6b04",
  "approval_status": {
    "available": false,
    "data": null
  }
}
```

### Поиск GUID по теме

```text
GET /topic-guid-fields/topics/by-topic/:topic_id/:token.json
```

Если тема найдена:

```json
{
  "ok": true,
  "found": true,
  "topic_id": 123,
  "guid": "09abcfac-0e44-11f1-86e9-a94ec75f6b04",
  "title": "Topic title",
  "slug": "topic-title",
  "url": "https://forum.example.com/t/topic-title/123",
  "created_at": "2026-07-09T10:00:00Z",
  "approval_status": {
    "available": false,
    "data": null
  }
}
```

Если тема не найдена:

```json
{
  "ok": true,
  "found": false,
  "topic_id": 999999,
  "guid": null,
  "approval_status": {
    "available": false,
    "data": null
  }
}
```

Если установлен `discourse-tz-approval` и доступен `TzApproval.topic_status_payload(topic)`, поле `approval_status.data` будет заполнено данными approval-плагина. Без approval-плагина GUID lookup работает независимо.
