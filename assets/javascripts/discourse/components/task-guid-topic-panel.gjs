import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content;
}

function setTopicGuid(topic, guid) {
  if (typeof topic?.set === "function") {
    topic.set("task_guid", guid);
  } else if (topic) {
    topic.task_guid = guid;
  }
}

export default class TaskGuidTopicPanel extends Component {
  @service siteSettings;
  @service dialog;

  @tracked guid = "";
  @tracked saving = false;

  constructor(owner, args) {
    super(owner, args);
    this.guid = this.topic?.task_guid || "";
  }

  get post() {
    return this.args.post;
  }

  get topic() {
    return this.post?.topic;
  }

  get shouldRender() {
    return (
      this.siteSettings.discourse_new_topic_field_enabled &&
      this.post?.post_number === 1 &&
      this.topic?.can_manage_task_guid
    );
  }

  get buttonLabel() {
    return this.saving
      ? i18n("discourse_new_topic_field.topic.saving")
      : i18n("discourse_new_topic_field.topic.save");
  }

  @action
  updateGuid(event) {
    this.guid = event.target.value;
  }

  @action
  async saveGuid() {
    const guid = this.guid.trim();
    if (!guid) {
      this.dialog.dialog({
        type: "alert",
        message: i18n("discourse_new_topic_field.errors.guid_required"),
      });
      return;
    }

    const token = csrfToken();
    const headers = {
      Accept: "application/json",
      "Content-Type": "application/json",
    };

    if (token) {
      headers["X-CSRF-Token"] = token;
    }

    this.saving = true;

    try {
      const response = await fetch(
        `/new-topic-field/topics/${this.topic.id}/guid.json`,
        {
          method: "PUT",
          credentials: "same-origin",
          headers,
          body: JSON.stringify({ guid }),
        }
      );

      if (!response.ok) {
        if (response.status === 409) {
          this.dialog.dialog({
            type: "alert",
            message: i18n("discourse_new_topic_field.topic.duplicate_guid"),
          });
          return;
        }

        throw new Error(`GUID update failed with status ${response.status}`);
      }

      const payload = await response.json();
      this.guid = payload.guid || guid;
      setTopicGuid(this.topic, this.guid);
    } catch {
      this.dialog.dialog({
        type: "alert",
        message: i18n("discourse_new_topic_field.topic.save_failed"),
      });
    } finally {
      this.saving = false;
    }
  }

  <template>
    {{#if this.shouldRender}}
      <div class="new-topic-field-topic-panel" data-new-topic-field-topic-panel>
        <label class="new-topic-field-topic-panel__label">
          <span>{{i18n "discourse_new_topic_field.guid_label"}}</span>
          <input
            type="text"
            value={{this.guid}}
            class="new-topic-field-input"
            data-new-topic-field-topic-guid
            {{on "input" this.updateGuid}}
          />
        </label>

        <button
          type="button"
          class="btn btn-primary new-topic-field-topic-panel__save"
          disabled={{this.saving}}
          {{on "click" this.saveGuid}}
        >
          {{this.buttonLabel}}
        </button>
      </div>
    {{/if}}
  </template>
}
