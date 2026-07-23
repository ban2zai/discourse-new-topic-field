import { trustHTML } from "@ember/template";
import { escapeExpression } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";

export default function duplicateGuidMessage(topic) {
  const message = i18n("discourse_new_topic_field.topic.duplicate_guid");

  if (!topic?.url) {
    return message;
  }

  const linkLabel = i18n(
    "discourse_new_topic_field.topic.duplicate_guid_link"
  );

  return trustHTML(
    `${escapeExpression(message)} <a href="${escapeExpression(
      topic.url
    )}" target="_blank" rel="noopener noreferrer">${escapeExpression(
      linkLabel
    )}</a>`
  );
}
