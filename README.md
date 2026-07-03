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
- предоставляет JSON-поиск `GET /new-topic-field/topics?guid=<guid>`.

Проверка внешнего токена пока не реализована намеренно. Точка расширения для неё:
`DiscourseNewTopicField::TopicsController#authorize_external_search!`.
