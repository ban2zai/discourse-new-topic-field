import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";
import TaskGuidComposerField from "../components/task-guid-composer-field";
import TaskGuidTopicHeader from "../components/task-guid-topic-header";
import { captureTaskGuid } from "../lib/task-guid-cache";

async function linkedTopic(guid) {
  const response = await fetch(
    `/new-topic-field/topics.json?guid=${encodeURIComponent(guid)}`,
    {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
      },
    }
  );

  if (!response.ok) {
    throw new Error(`GUID lookup failed with status ${response.status}`);
  }

  const payload = await response.json();
  return payload.topics?.[0];
}

export default apiInitializer((api) => {
  captureTaskGuid();

  api.serializeOnCreate("task_guid");
  api.renderInOutlet("composer-fields", TaskGuidComposerField);
  api.renderInOutlet("topic-title", TaskGuidTopicHeader);

  api.onPageChange((url) => captureTaskGuid(url));

  api.modifyClass(
    "model:composer",
    (Superclass) =>
      class extends Superclass {
        async beforeSave() {
          await super.beforeSave(...arguments);

          if (
            this.siteSettings.discourse_new_topic_field_enabled === false ||
            !this.creatingTopic ||
            !this.task_guid
          ) {
            return;
          }

          let topic;
          try {
            topic = await linkedTopic(this.task_guid);
          } catch {
            this.dialog.dialog({
              type: "alert",
              message: i18n("discourse_new_topic_field.topic.lookup_failed"),
            });

            return Promise.reject();
          }

          if (topic) {
            this.dialog.dialog({
              type: "alert",
              message: i18n("discourse_new_topic_field.topic.duplicate_guid"),
            });

            return Promise.reject();
          }
        }
      }
  );
});
