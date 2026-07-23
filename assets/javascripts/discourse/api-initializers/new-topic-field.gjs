import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";
import TaskGuidComposerField from "../components/task-guid-composer-field";
import TaskGuidTopicHeader from "../components/task-guid-topic-header";
import duplicateGuidMessage from "../lib/duplicate-guid-message";
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
  const topic = payload.topics?.[0];

  return {
    linked: payload.linked === true || Boolean(topic),
    topic,
  };
}

async function validateSignature(guid, expires, nonce, sig) {
  const params = new URLSearchParams({ guid, expires, nonce, sig });
  const response = await fetch(
    `/new-topic-field/signature/validate.json?${params.toString()}`,
    {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
      },
    }
  );

  if (!response.ok) {
    throw new Error(`GUID signature validation failed with status ${response.status}`);
  }
}

export default apiInitializer((api) => {
  captureTaskGuid();

  api.serializeOnCreate("task_guid");
  api.serializeOnCreate("task_guid_expires");
  api.serializeOnCreate("task_guid_nonce");
  api.serializeOnCreate("task_guid_sig");
  api.renderInOutlet("composer-fields", TaskGuidComposerField);
  api.renderInOutlet("topic-above-posts", TaskGuidTopicHeader);

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

          if (this.siteSettings.discourse_new_topic_field_require_signature) {
            try {
              await validateSignature(
                this.task_guid,
                this.task_guid_expires,
                this.task_guid_nonce,
                this.task_guid_sig
              );
            } catch {
              this.dialog.dialog({
                type: "alert",
                message: i18n("discourse_new_topic_field.topic.invalid_signature"),
              });

              return Promise.reject();
            }
          }

          let guidLink;
          try {
            guidLink = await linkedTopic(this.task_guid);
          } catch {
            this.dialog.dialog({
              type: "alert",
              message: i18n("discourse_new_topic_field.topic.lookup_failed"),
            });

            return Promise.reject();
          }

          if (guidLink.linked) {
            this.dialog.dialog({
              type: "alert",
              message: duplicateGuidMessage(guidLink.topic),
            });

            return Promise.reject();
          }
        }
      }
  );
});
